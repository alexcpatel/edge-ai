#!/usr/bin/env python3
"""
Cleanup orphaned AWS IoT resources.

Finds and removes:
- Things without attached certificates
- Inactive certificates
- Certificates not attached to any thing
"""

import boto3
import click

THING_TYPE = "edge-ai-device"


class IoTCleaner:
    def __init__(self, region: str = None):
        self.iot = boto3.client("iot", region_name=region)

    def list_things(self) -> list[dict]:
        """List all things of our type."""
        things = []
        paginator = self.iot.get_paginator("list_things")
        for page in paginator.paginate(thingTypeName=THING_TYPE):
            things.extend(page.get("things", []))
        return things

    def list_certificates(self) -> list[dict]:
        """List all certificates."""
        certs = []
        paginator = self.iot.get_paginator("list_certificates")
        for page in paginator.paginate():
            certs.extend(page.get("certificates", []))
        return certs

    def get_thing_principals(self, thing_name: str) -> list[str]:
        """Get certificates attached to a thing."""
        try:
            response = self.iot.list_thing_principals(thingName=thing_name)
            return response.get("principals", [])
        except self.iot.exceptions.ResourceNotFoundException:
            return []

    def get_certificate_things(self, cert_arn: str) -> list[str]:
        """Get things attached to a certificate."""
        try:
            response = self.iot.list_principal_things(principal=cert_arn)
            return response.get("things", [])
        except Exception:
            return []

    def delete_certificate(self, cert_id: str, cert_arn: str):
        """Fully delete a certificate and its attachments."""
        things = self.get_certificate_things(cert_arn)
        for thing_name in things:
            self.iot.detach_thing_principal(
                thingName=thing_name, principal=cert_arn
            )

        policies = self.iot.list_attached_policies(target=cert_arn)
        for policy in policies.get("policies", []):
            self.iot.detach_policy(policyName=policy["policyName"], target=cert_arn)

        self.iot.update_certificate(certificateId=cert_id, newStatus="INACTIVE")
        self.iot.delete_certificate(certificateId=cert_id, forceDelete=True)

    def find_orphaned_things(self) -> list[str]:
        """Find things with no attached certificates."""
        orphaned = []
        for thing in self.list_things():
            principals = self.get_thing_principals(thing["thingName"])
            if not principals:
                orphaned.append(thing["thingName"])
        return orphaned

    def find_orphaned_certificates(self) -> list[dict]:
        """Find certificates not attached to any thing."""
        orphaned = []
        for cert in self.list_certificates():
            things = self.get_certificate_things(cert["certificateArn"])
            if not things:
                orphaned.append(cert)
        return orphaned

    def find_inactive_certificates(self) -> list[dict]:
        """Find inactive certificates."""
        return [c for c in self.list_certificates() if c["status"] == "INACTIVE"]

    def cleanup_thing(self, thing_name: str):
        """Delete a thing."""
        principals = self.get_thing_principals(thing_name)
        for principal in principals:
            self.iot.detach_thing_principal(thingName=thing_name, principal=principal)
        self.iot.delete_thing(thingName=thing_name)


@click.command()
@click.option("--region", default=None, help="AWS region")
@click.option("--dry-run", is_flag=True, help="Show what would be deleted")
@click.option("--force", is_flag=True, help="Delete without confirmation")
def main(region: str, dry_run: bool, force: bool):
    """Clean up orphaned AWS IoT resources."""
    cleaner = IoTCleaner(region=region)

    click.echo("Scanning for orphaned resources...")

    orphaned_things = cleaner.find_orphaned_things()
    orphaned_certs = cleaner.find_orphaned_certificates()
    inactive_certs = cleaner.find_inactive_certificates()

    if not any([orphaned_things, orphaned_certs, inactive_certs]):
        click.echo("No orphaned resources found.")
        return

    if orphaned_things:
        click.echo(f"\nOrphaned things ({len(orphaned_things)}):")
        for name in orphaned_things:
            click.echo(f"  - {name}")

    if orphaned_certs:
        click.echo(f"\nOrphaned certificates ({len(orphaned_certs)}):")
        for cert in orphaned_certs:
            click.echo(f"  - {cert['certificateId'][:12]}... ({cert['status']})")

    if inactive_certs:
        click.echo(f"\nInactive certificates ({len(inactive_certs)}):")
        for cert in inactive_certs:
            click.echo(f"  - {cert['certificateId'][:12]}...")

    if dry_run:
        click.echo("\nDry run - no changes made")
        return

    if not force:
        if not click.confirm("\nDelete these resources?"):
            click.echo("Aborted.")
            return

    click.echo("\nCleaning up...")

    for name in orphaned_things:
        click.echo(f"Deleting thing: {name}")
        cleaner.cleanup_thing(name)

    for cert in orphaned_certs + inactive_certs:
        cert_id = cert["certificateId"]
        if cert not in orphaned_certs or cert not in inactive_certs:
            click.echo(f"Deleting certificate: {cert_id[:12]}...")
            cleaner.delete_certificate(cert_id, cert["certificateArn"])

    click.echo("Done!")


if __name__ == "__main__":
    main()

