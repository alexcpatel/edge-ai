#!/bin/bash
# Deploy all sandbox containers to device
#
# Usage: ./deploy-all-sandbox.sh <device>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { echo "ERROR: $*" >&2; exit 1; }

DEVICE="${1:-}"
[ -z "$DEVICE" ] && die "Usage: $0 <device-ip-or-hostname>"

# Deploy each app that has a deploy.sh script
for app_dir in "$SCRIPT_DIR"/*/; do
    app=$(basename "$app_dir")
    [ "$app" = "scripts" ] && continue

    if [ -x "$app_dir/deploy.sh" ]; then
        echo ""
        echo "=== Deploying $app ==="
        "$app_dir/deploy.sh" "$DEVICE"
    fi
done

echo ""
echo "All sandbox apps deployed to $DEVICE"
