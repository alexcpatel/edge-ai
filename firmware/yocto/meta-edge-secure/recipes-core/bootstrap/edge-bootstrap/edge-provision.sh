#!/bin/bash
# AWS IoT Fleet Provisioning for Edge AI devices
# Wrapper script that calls Python implementation

set -euo pipefail

exec /usr/bin/edge-provision.py "$@"

