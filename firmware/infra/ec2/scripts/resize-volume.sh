#!/bin/bash
set -euo pipefail

# Resize root volume by creating a smaller copy
# Usage: ./resize-volume.sh [NEW_SIZE_GB]

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$SCRIPT_DIR/lib/common.sh"

NEW_SIZE="${1:-200}"

check_aws_creds

INSTANCE_ID=$(get_instance_or_exit)
STATE=$(get_instance_state "$INSTANCE_ID")

log_info "Instance: $INSTANCE_ID (state: $STATE)"
log_info "Target size: ${NEW_SIZE}GB"

# Get current volume info
ROOT_VOLUME=$(aws ec2 describe-instances --region "$AWS_REGION" --instance-ids "$INSTANCE_ID" \
    --query "Reservations[0].Instances[0].BlockDeviceMappings[?DeviceName=='/dev/sda1'].Ebs.VolumeId" --output text)
[ -z "$ROOT_VOLUME" ] && ROOT_VOLUME=$(aws ec2 describe-instances --region "$AWS_REGION" --instance-ids "$INSTANCE_ID" \
    --query "Reservations[0].Instances[0].BlockDeviceMappings[0].Ebs.VolumeId" --output text)

AZ=$(aws ec2 describe-instances --region "$AWS_REGION" --instance-ids "$INSTANCE_ID" \
    --query "Reservations[0].Instances[0].Placement.AvailabilityZone" --output text)

CURRENT_SIZE=$(aws ec2 describe-volumes --region "$AWS_REGION" --volume-ids "$ROOT_VOLUME" \
    --query "Volumes[0].Size" --output text)

log_info "Current root volume: $ROOT_VOLUME (${CURRENT_SIZE}GB) in $AZ"

if [ "$NEW_SIZE" -ge "$CURRENT_SIZE" ]; then
    log_error "New size must be smaller than current size ($CURRENT_SIZE GB)"
    exit 1
fi

# Ensure instance is running for the copy
if [ "$STATE" != "running" ]; then
    log_info "Starting instance for data copy..."
    aws ec2 start-instances --region "$AWS_REGION" --instance-ids "$INSTANCE_ID" >/dev/null
    aws ec2 wait instance-running --region "$AWS_REGION" --instance-ids "$INSTANCE_ID"
    sleep 30  # Wait for SSH
fi

IP=$(get_instance_ip "$INSTANCE_ID")
log_info "Instance IP: $IP"

# Create new smaller volume
log_info "Creating new ${NEW_SIZE}GB volume..."
NEW_VOLUME=$(aws ec2 create-volume --region "$AWS_REGION" \
    --availability-zone "$AZ" \
    --size "$NEW_SIZE" \
    --volume-type gp3 \
    --iops 3000 \
    --throughput 125 \
    --tag-specifications "ResourceType=volume,Tags=[{Key=Name,Value=yocto-builder-resized}]" \
    --query "VolumeId" --output text)

log_info "New volume: $NEW_VOLUME"
aws ec2 wait volume-available --region "$AWS_REGION" --volume-ids "$NEW_VOLUME"

# Attach new volume
log_info "Attaching new volume as /dev/xvdf..."
aws ec2 attach-volume --region "$AWS_REGION" \
    --volume-id "$NEW_VOLUME" \
    --instance-id "$INSTANCE_ID" \
    --device /dev/xvdf >/dev/null

sleep 10  # Wait for attachment

# Format and copy data on the instance
log_info "Formatting and copying data (this takes 10-20 minutes)..."
ssh_cmd "$IP" "sudo bash -s" << 'REMOTE_SCRIPT'
set -euo pipefail

# Wait for device
for i in {1..30}; do
    [ -b /dev/xvdf ] && break
    [ -b /dev/nvme1n1 ] && break
    sleep 2
done

# Detect the actual device name (could be xvdf or nvme1n1)
if [ -b /dev/nvme1n1 ]; then
    DEV=/dev/nvme1n1
elif [ -b /dev/xvdf ]; then
    DEV=/dev/xvdf
else
    echo "ERROR: New volume not found"
    exit 1
fi

echo "Using device: $DEV"

# Create partition and filesystem
echo "Creating partition..."
sudo parted -s "$DEV" mklabel gpt
sudo parted -s "$DEV" mkpart primary ext4 1MiB 100%

# Get partition device
if [[ "$DEV" == /dev/nvme* ]]; then
    PART="${DEV}p1"
else
    PART="${DEV}1"
fi

sleep 2
echo "Formatting $PART..."
sudo mkfs.ext4 -q "$PART"

# Mount and copy
echo "Mounting..."
sudo mkdir -p /mnt/newroot
sudo mount "$PART" /mnt/newroot

echo "Copying data (this will take a while)..."
sudo rsync -aHAXx --info=progress2 \
    --exclude=/dev --exclude=/proc --exclude=/sys \
    --exclude=/run --exclude=/mnt --exclude=/tmp \
    --exclude=/lost+found \
    / /mnt/newroot/

# Create excluded directories
sudo mkdir -p /mnt/newroot/{dev,proc,sys,run,mnt,tmp}
sudo chmod 1777 /mnt/newroot/tmp

# Install grub
echo "Installing bootloader..."
sudo mount --bind /dev /mnt/newroot/dev
sudo mount --bind /proc /mnt/newroot/proc
sudo mount --bind /sys /mnt/newroot/sys

# Update fstab to use labels/UUIDs
NEW_UUID=$(sudo blkid -s UUID -o value "$PART")
sudo sed -i "s|LABEL=cloudimg-rootfs|UUID=$NEW_UUID|g" /mnt/newroot/etc/fstab 2>/dev/null || true

sudo chroot /mnt/newroot grub-install "$DEV" 2>/dev/null || echo "Grub install skipped (EFI system)"
sudo chroot /mnt/newroot update-grub 2>/dev/null || true

# Cleanup
sudo umount /mnt/newroot/sys /mnt/newroot/proc /mnt/newroot/dev
sudo umount /mnt/newroot

echo "Copy complete!"
REMOTE_SCRIPT

log_info "Data copy complete"

# Stop instance
log_info "Stopping instance..."
aws ec2 stop-instances --region "$AWS_REGION" --instance-ids "$INSTANCE_ID" >/dev/null
aws ec2 wait instance-stopped --region "$AWS_REGION" --instance-ids "$INSTANCE_ID"

# Detach both volumes
log_info "Detaching volumes..."
aws ec2 detach-volume --region "$AWS_REGION" --volume-id "$ROOT_VOLUME" >/dev/null || true
aws ec2 detach-volume --region "$AWS_REGION" --volume-id "$NEW_VOLUME" >/dev/null || true

sleep 10

# Attach new volume as root
log_info "Attaching new volume as root..."
aws ec2 attach-volume --region "$AWS_REGION" \
    --volume-id "$NEW_VOLUME" \
    --instance-id "$INSTANCE_ID" \
    --device /dev/sda1 >/dev/null

sleep 5

log_success "Volume resize complete!"
log_info ""
log_info "Old volume $ROOT_VOLUME (${CURRENT_SIZE}GB) is now detached"
log_info "New volume $NEW_VOLUME (${NEW_SIZE}GB) is now the root volume"
log_info ""
log_info "Next steps:"
log_info "1. Start instance: make firmware-ec2-start"
log_info "2. Verify it works correctly"
log_info "3. Delete old volume: aws ec2 delete-volume --region $AWS_REGION --volume-id $ROOT_VOLUME"
log_info "4. Update ec2.tf: change volume_size from 500 to $NEW_SIZE"
