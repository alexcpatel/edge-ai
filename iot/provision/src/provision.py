#!/usr/bin/env python3
"""
Device provisioning for Edge AI devices.

Run from dev machine - SSHs into device to install dependencies,
generate keys, and register with AWS IoT Core.
"""

import json
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path

import boto3
import click

THING_TYPE = "edge-ai-device"
POLICY_NAME = "edge-ai-device-policy"
IOT_CERTS_DIR = "/etc/aws-iot"
AMAZON_ROOT_CA_URL = "https://www.amazontrust.com/repository/AmazonRootCA1.pem"

PYTHON_PACKAGES = [
    "awscli",
    "awsiotsdk",
    "numpy",
    "paho-mqtt",
    "boto3",
    "requests",
]


@dataclass
class DeviceConnection:
    host: str
    user: str = "root"
    port: int = 22

    def run(self, cmd: str, check: bool = True) -> str:
        """Run command on device via SSH."""
        ssh_cmd = [
            "ssh",
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-p", str(self.port),
            f"{self.user}@{self.host}",
            cmd,
        ]
        result = subprocess.run(ssh_cmd, capture_output=True, text=True)
        if check and result.returncode != 0:
            raise RuntimeError(f"SSH command failed: {result.stderr}")
        return result.stdout.strip()

    def copy_to(self, local_path: str, remote_path: str):
        """Copy file to device via SCP."""
        scp_cmd = [
            "scp",
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-P", str(self.port),
            local_path,
            f"{self.user}@{self.host}:{remote_path}",
        ]
        subprocess.run(scp_cmd, check=True)

    def copy_from(self, remote_path: str, local_path: str):
        """Copy file from device via SCP."""
        scp_cmd = [
            "scp",
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-P", str(self.port),
            f"{self.user}@{self.host}:{remote_path}",
            local_path,
        ]
        subprocess.run(scp_cmd, check=True)


class IoTProvisioner:
    def __init__(self, region: str = None):
        self.iot = boto3.client("iot", region_name=region)
        self.region = region or boto3.session.Session().region_name

    def get_thing(self, thing_name: str) -> dict | None:
        try:
            return self.iot.describe_thing(thingName=thing_name)
        except self.iot.exceptions.ResourceNotFoundException:
            return None

    def get_thing_principals(self, thing_name: str) -> list[str]:
        try:
            response = self.iot.list_thing_principals(thingName=thing_name)
            return response.get("principals", [])
        except self.iot.exceptions.ResourceNotFoundException:
            return []

    def cleanup_thing(self, thing_name: str):
        """Remove thing and all attached certificates."""
        principals = self.get_thing_principals(thing_name)

        for principal_arn in principals:
            cert_id = principal_arn.split("/")[-1]
            self.iot.detach_thing_principal(thingName=thing_name, principal=principal_arn)

            policies = self.iot.list_attached_policies(target=principal_arn)
            for policy in policies.get("policies", []):
                self.iot.detach_policy(policyName=policy["policyName"], target=principal_arn)

            self.iot.update_certificate(certificateId=cert_id, newStatus="INACTIVE")
            self.iot.delete_certificate(certificateId=cert_id, forceDelete=True)

        if self.get_thing(thing_name):
            self.iot.delete_thing(thingName=thing_name)

    def create_certificate_from_csr(self, csr_pem: str) -> dict:
        """Create certificate from CSR."""
        response = self.iot.create_certificate_from_csr(
            certificateSigningRequest=csr_pem,
            setAsActive=True,
        )
        return {
            "certificate_arn": response["certificateArn"],
            "certificate_pem": response["certificatePem"],
        }

    def provision(self, thing_name: str, csr_pem: str) -> dict:
        """Provision device. Idempotent."""
        self.cleanup_thing(thing_name)

        self.iot.create_thing(thingName=thing_name, thingTypeName=THING_TYPE)

        cert = self.create_certificate_from_csr(csr_pem)
        self.iot.attach_thing_principal(thingName=thing_name, principal=cert["certificate_arn"])
        self.iot.attach_policy(policyName=POLICY_NAME, target=cert["certificate_arn"])

        endpoint = self.iot.describe_endpoint(endpointType="iot:Data-ATS")

        return {
            "thing_name": thing_name,
            "certificate_arn": cert["certificate_arn"],
            "certificate_pem": cert["certificate_pem"],
            "endpoint": endpoint["endpointAddress"],
        }


def install_dependencies(dev: DeviceConnection):
    """Install Python packages on device."""
    click.echo("Installing Python packages...")
    packages = " ".join(PYTHON_PACKAGES)
    dev.run(f"pip3 install {packages}")


def get_device_id(dev: DeviceConnection) -> str:
    """Get device serial number."""
    try:
        serial = dev.run("cat /sys/firmware/devicetree/base/serial-number")
        return serial.rstrip("\x00")
    except RuntimeError:
        return dev.run("hostname")


def generate_key_on_device(dev: DeviceConnection, device_id: str) -> str:
    """Generate ECDSA key and CSR on device, return CSR."""
    click.echo("Generating ECDSA P-256 key pair on device...")

    dev.run(f"mkdir -p {IOT_CERTS_DIR}")

    # Generate private key
    dev.run(f"openssl ecparam -name prime256v1 -genkey -noout -out {IOT_CERTS_DIR}/private.pem.key")

    # Generate CSR
    dev.run(
        f'openssl req -new -key {IOT_CERTS_DIR}/private.pem.key '
        f'-out {IOT_CERTS_DIR}/device.csr -subj "/CN={device_id}"'
    )

    # Set permissions
    dev.run(f"chmod 600 {IOT_CERTS_DIR}/private.pem.key")

    # Retrieve CSR
    with tempfile.NamedTemporaryFile(mode="w", suffix=".csr", delete=False) as f:
        csr_path = f.name
    dev.copy_from(f"{IOT_CERTS_DIR}/device.csr", csr_path)
    csr_pem = Path(csr_path).read_text()
    Path(csr_path).unlink()

    return csr_pem


def save_credentials_to_device(dev: DeviceConnection, cert_pem: str, endpoint: str, thing_name: str):
    """Save certificate and config to device."""
    click.echo("Saving credentials to device...")

    # Write certificate
    with tempfile.NamedTemporaryFile(mode="w", suffix=".crt", delete=False) as f:
        f.write(cert_pem)
        cert_path = f.name
    dev.copy_to(cert_path, f"{IOT_CERTS_DIR}/certificate.pem.crt")
    Path(cert_path).unlink()

    # Download Amazon Root CA
    click.echo("Downloading Amazon Root CA...")
    dev.run(f"curl -s -o {IOT_CERTS_DIR}/AmazonRootCA1.pem {AMAZON_ROOT_CA_URL}")

    # Write config
    config = {
        "endpoint": endpoint,
        "thing_name": thing_name,
        "cert_path": f"{IOT_CERTS_DIR}/certificate.pem.crt",
        "key_path": f"{IOT_CERTS_DIR}/private.pem.key",
        "ca_path": f"{IOT_CERTS_DIR}/AmazonRootCA1.pem",
    }
    with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
        json.dump(config, f, indent=2)
        config_path = f.name
    dev.copy_to(config_path, f"{IOT_CERTS_DIR}/config.json")
    Path(config_path).unlink()

    # Set permissions
    dev.run(f"chmod 600 {IOT_CERTS_DIR}/*")


def verify_connection(dev: DeviceConnection):
    """Verify IoT connection from device."""
    click.echo("Verifying IoT connection...")
    verify_script = '''
python3 -c "
import json
from awsiot import mqtt_connection_builder

config = json.load(open('/etc/aws-iot/config.json'))
conn = mqtt_connection_builder.mtls_from_path(
    endpoint=config['endpoint'],
    cert_filepath=config['cert_path'],
    pri_key_filepath=config['key_path'],
    ca_filepath=config['ca_path'],
    client_id=config['thing_name'],
)
conn.connect().result(timeout=10)
print('IoT connection verified!')
conn.disconnect().result()
"
'''
    result = dev.run(verify_script.strip())
    click.echo(result)


@click.command()
@click.argument("device_host")
@click.option("--user", default="root", help="SSH user")
@click.option("--port", default=22, help="SSH port")
@click.option("--region", default=None, help="AWS region")
@click.option("--skip-deps", is_flag=True, help="Skip dependency installation")
@click.option("--skip-verify", is_flag=True, help="Skip connection verification")
@click.option("--dry-run", is_flag=True, help="Show what would be done")
def main(device_host: str, user: str, port: int, region: str, skip_deps: bool, skip_verify: bool, dry_run: bool):
    """
    Provision a device with AWS IoT Core.

    DEVICE_HOST is the IP address or hostname of the device.
    """
    dev = DeviceConnection(host=device_host, user=user, port=port)

    click.echo(f"Connecting to {user}@{device_host}:{port}...")
    device_id = get_device_id(dev)
    thing_name = f"edge-ai-{device_id}"

    click.echo(f"Device ID: {device_id}")
    click.echo(f"Thing name: {thing_name}")

    if dry_run:
        click.echo("Dry run - no changes made")
        return

    if not skip_deps:
        install_dependencies(dev)

    csr_pem = generate_key_on_device(dev, device_id)

    click.echo("Registering with AWS IoT Core...")
    provisioner = IoTProvisioner(region=region)
    result = provisioner.provision(thing_name, csr_pem)

    save_credentials_to_device(dev, result["certificate_pem"], result["endpoint"], thing_name)

    if not skip_verify:
        verify_connection(dev)

    click.echo(f"\nProvisioning complete!")
    click.echo(f"  Thing: {thing_name}")
    click.echo(f"  Endpoint: {result['endpoint']}")
    click.echo(f"  Credentials: {IOT_CERTS_DIR}/")


if __name__ == "__main__":
    main()
