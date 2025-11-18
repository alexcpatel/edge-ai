#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# List available build artifacts on EC2 instance

source "$(dirname "$0")/lib/common.sh"

ip=$(get_instance_ip_or_exit)

# Artifacts directory on EC2
ARTIFACTS_DIR="$YOCTO_DIR/build/tmp/deploy/images/$YOCTO_MACHINE"

if ! ssh_cmd "$ip" "test -d $ARTIFACTS_DIR" 2>/dev/null; then
    exit 1
fi

# List artifacts (one per line, just filenames)
ssh_cmd "$ip" "cd $ARTIFACTS_DIR && ls -1 *.wic *.img *.ext4 *.tar.gz *.dtb *.bin *.wic.bmap 2>/dev/null | sort" || echo ""

