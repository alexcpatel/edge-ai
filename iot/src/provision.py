#!/usr/bin/env python3
"""
Device provisioning for AWS IoT Core.

Generates ECDSA P-256 key on device, creates certificate via CSR,
and registers with IoT Core. Idempotent - safe to run multiple times.

Note: AWS IoT doesn't support ED25519, ECDSA P-256 is used instead.
"""

import json
import subprocess
from pathlib import Path

import boto3
import click
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.x509.oid import NameOID

IOT_CERTS_DIR = Path("/etc/aws-iot")
THING_TYPE = "edge-ai-device"
POLICY_NAME = "edge-ai-device-policy"


def get_device_id() -> str:
    """Get unique device ID from hardware (Jetson serial number)."""
    try:
        result = subprocess.run(
            ["cat", "/sys/firmware/devicetree/base/serial-number"],
            capture_output=True,
            text=True,
            check=True,
        )
        return result.stdout.strip().rstrip("\x00")
    except (subprocess.CalledProcessError, FileNotFoundError):
        import socket
        return socket.gethostname()


def generate_key_and_csr(device_id: str) -> tuple[bytes, bytes]:
    """Generate ECDSA P-256 private key and CSR on device."""
    private_key = ec.generate_private_key(ec.SECP256R1())

    csr = (
        x509.CertificateSigningRequestBuilder()
        .subject_name(
            x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, device_id)])
        )
        .sign(private_key, hashes.SHA256())
    )

    private_key_pem = private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )
    csr_pem = csr.public_bytes(serialization.Encoding.PEM)

    return private_key_pem, csr_pem


class IoTProvisioner:
    def __init__(self, region: str = None):
        self.iot = boto3.client("iot", region_name=region)
        self.region = region or boto3.session.Session().region_name

    def get_thing(self, thing_name: str) -> dict | None:
        """Get thing if it exists."""
        try:
            return self.iot.describe_thing(thingName=thing_name)
        except self.iot.exceptions.ResourceNotFoundException:
            return None

    def get_thing_principals(self, thing_name: str) -> list[str]:
        """Get certificates attached to a thing."""
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

            self.iot.detach_thing_principal(
                thingName=thing_name, principal=principal_arn
            )

            policies = self.iot.list_attached_policies(target=principal_arn)
            for policy in policies.get("policies", []):
                self.iot.detach_policy(
                    policyName=policy["policyName"], target=principal_arn
                )

            self.iot.update_certificate(
                certificateId=cert_id, newStatus="INACTIVE"
            )
            self.iot.delete_certificate(certificateId=cert_id, forceDelete=True)

        if self.get_thing(thing_name):
            self.iot.delete_thing(thingName=thing_name)

    def ensure_thing_type(self) -> str:
        """Create thing type if it doesn't exist."""
        try:
            self.iot.describe_thing_type(thingTypeName=THING_TYPE)
        except self.iot.exceptions.ResourceNotFoundException:
            self.iot.create_thing_type(
                thingTypeName=THING_TYPE,
                thingTypeProperties={
                    "thingTypeDescription": "Edge AI device running Yocto"
                },
            )
        return THING_TYPE

    def ensure_policy(self) -> str:
        """Create IoT policy if it doesn't exist."""
        policy_document = {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Action": ["iot:Connect"],
                    "Resource": [
                        f"arn:aws:iot:{self.region}:*:client/${{iot:Connection.Thing.ThingName}}"
                    ],
                },
                {
                    "Effect": "Allow",
                    "Action": ["iot:Publish", "iot:Receive"],
                    "Resource": [
                        f"arn:aws:iot:{self.region}:*:topic/${{iot:Connection.Thing.ThingName}}/*",
                        f"arn:aws:iot:{self.region}:*:topic/$aws/things/${{iot:Connection.Thing.ThingName}}/*",
                    ],
                },
                {
                    "Effect": "Allow",
                    "Action": ["iot:Subscribe"],
                    "Resource": [
                        f"arn:aws:iot:{self.region}:*:topicfilter/${{iot:Connection.Thing.ThingName}}/*",
                        f"arn:aws:iot:{self.region}:*:topicfilter/$aws/things/${{iot:Connection.Thing.ThingName}}/*",
                    ],
                },
            ],
        }

        try:
            self.iot.get_policy(policyName=POLICY_NAME)
            self.iot.create_policy_version(
                policyName=POLICY_NAME,
                policyDocument=json.dumps(policy_document),
                setAsDefault=True,
            )
            self._cleanup_old_policy_versions()
        except self.iot.exceptions.ResourceNotFoundException:
            self.iot.create_policy(
                policyName=POLICY_NAME,
                policyDocument=json.dumps(policy_document),
            )
        return POLICY_NAME

    def _cleanup_old_policy_versions(self):
        """Remove non-default policy versions (max 5 allowed)."""
        versions = self.iot.list_policy_versions(policyName=POLICY_NAME)
        for v in versions.get("policyVersions", []):
            if not v["isDefaultVersion"]:
                self.iot.delete_policy_version(
                    policyName=POLICY_NAME, policyVersionId=v["versionId"]
                )

    def provision(self, thing_name: str, csr_pem: bytes) -> dict:
        """Provision device with IoT Core. Idempotent."""
        self.cleanup_thing(thing_name)

        self.ensure_thing_type()
        policy_name = self.ensure_policy()

        self.iot.create_thing(thingName=thing_name, thingTypeName=THING_TYPE)

        cert_response = self.iot.create_certificate_from_csr(
            certificateSigningRequest=csr_pem.decode(),
            setAsActive=True,
        )

        cert_arn = cert_response["certificateArn"]
        cert_pem = cert_response["certificatePem"]

        self.iot.attach_thing_principal(thingName=thing_name, principal=cert_arn)
        self.iot.attach_policy(policyName=policy_name, target=cert_arn)

        endpoint = self.iot.describe_endpoint(endpointType="iot:Data-ATS")

        return {
            "thing_name": thing_name,
            "certificate_arn": cert_arn,
            "certificate_pem": cert_pem,
            "endpoint": endpoint["endpointAddress"],
        }


def save_credentials(
    private_key_pem: bytes, cert_pem: str, endpoint: str, thing_name: str
):
    """Save credentials to device filesystem."""
    IOT_CERTS_DIR.mkdir(parents=True, exist_ok=True)

    (IOT_CERTS_DIR / "private.pem.key").write_bytes(private_key_pem)
    (IOT_CERTS_DIR / "certificate.pem.crt").write_text(cert_pem)

    config = {
        "endpoint": endpoint,
        "thing_name": thing_name,
        "cert_path": str(IOT_CERTS_DIR / "certificate.pem.crt"),
        "key_path": str(IOT_CERTS_DIR / "private.pem.key"),
        "ca_path": str(IOT_CERTS_DIR / "AmazonRootCA1.pem"),
    }
    (IOT_CERTS_DIR / "config.json").write_text(json.dumps(config, indent=2))

    for f in IOT_CERTS_DIR.iterdir():
        f.chmod(0o600)


@click.command()
@click.option("--region", default=None, help="AWS region")
@click.option("--device-id", default=None, help="Override device ID")
@click.option("--dry-run", is_flag=True, help="Show what would be done")
def main(region: str, device_id: str, dry_run: bool):
    """Provision this device with AWS IoT Core."""
    device_id = device_id or get_device_id()
    thing_name = f"edge-ai-{device_id}"

    click.echo(f"Device ID: {device_id}")
    click.echo(f"Thing name: {thing_name}")

    if dry_run:
        click.echo("Dry run - no changes made")
        return

    click.echo("Generating ECDSA P-256 key pair...")
    private_key_pem, csr_pem = generate_key_and_csr(device_id)

    click.echo("Provisioning with AWS IoT Core...")
    provisioner = IoTProvisioner(region=region)
    result = provisioner.provision(thing_name, csr_pem)

    click.echo("Saving credentials...")
    save_credentials(
        private_key_pem, result["certificate_pem"], result["endpoint"], thing_name
    )

    click.echo(f"Endpoint: {result['endpoint']}")
    click.echo(f"Credentials saved to: {IOT_CERTS_DIR}")
    click.echo("Done!")


if __name__ == "__main__":
    main()

