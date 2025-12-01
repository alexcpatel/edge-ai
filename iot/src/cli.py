#!/usr/bin/env python3
"""CLI entry point for IoT provisioning tools."""

import click

from . import provision, cleanup


@click.group()
def cli():
    """Edge AI IoT provisioning tools."""
    pass


cli.add_command(provision.main, name="provision")
cli.add_command(cleanup.main, name="cleanup")


if __name__ == "__main__":
    cli()

