#!/bin/bash
# EC2 Instance Connect wrapper - uses temporary SSH keys instead of permanent ones
# This allows GitHub Actions to SSH without sharing private keys

set -euo pipefail

# Source common functions (this file is always sourced after common.sh)
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Cache directory for temporary keys (reused across multiple SSH calls)
EC2_CONNECT_CACHE_DIR="${HOME}/.ssh/ec2-instance-connect-cache"

# Generate temporary SSH key pair with caching to avoid rate limits
# Keys are cached and reused for 50 seconds (EC2 Instance Connect keys are valid for 60 seconds)
setup_temp_ssh_key() {
    local instance_id="$1"
    local cache_file="${EC2_CONNECT_CACHE_DIR}/${instance_id}.key"
    local cache_time_file="${EC2_CONNECT_CACHE_DIR}/${instance_id}.time"
    local cache_age=0

    mkdir -p "$EC2_CONNECT_CACHE_DIR"
    chmod 700 "$EC2_CONNECT_CACHE_DIR"

    # Generate new temporary key pair
    local temp_private_key="$cache_file"
    local temp_public_key="${temp_private_key}.pub"

    # Check if we have a cached key that's still valid (< 50 seconds old)
    if [ -f "$cache_file" ] && [ -f "$cache_time_file" ]; then
        local cache_timestamp
        cache_timestamp=$(cat "$cache_time_file" 2>/dev/null || echo "0")
        local current_timestamp
        current_timestamp=$(date +%s)
        cache_age=$((current_timestamp - cache_timestamp))

        if [ $cache_age -lt 50 ] && [ -f "$cache_file" ]; then
            # Reuse cached key
            echo "$cache_file"
            return 0
        fi
        # Cache expired, clean it up (remove both private key, public key, and timestamp)
        rm -f "$temp_private_key" "$temp_public_key" "$cache_time_file"
    fi

    ssh-keygen -t rsa -b 4096 -f "$temp_private_key" -N "" -q
    chmod 600 "$temp_private_key"

    # Send public key to instance via EC2 Instance Connect API
    local aws_error
    aws_error=$(aws ec2-instance-connect send-ssh-public-key \
        --region "$AWS_REGION" \
        --instance-id "$instance_id" \
        --instance-os-user "$EC2_USER" \
        --ssh-public-key "file://${temp_public_key}" 2>&1)
    local aws_exit_code=$?

    if [ $aws_exit_code -ne 0 ]; then
        rm -f "$temp_private_key" "$temp_public_key"
        # Show the actual AWS error for debugging
        log_error "EC2 Instance Connect failed: $aws_error"
        return 1
    fi

    # Cache the key with timestamp
    echo "$(date +%s)" > "$cache_time_file"
    echo "$temp_private_key"
    return 0
}

# Cleanup temporary key (only if it's not cached)
cleanup_temp_ssh_key() {
    local key_path="$1"
    # Don't delete cached keys - they'll expire naturally and be reused
    # Only delete if it's in a process-specific directory (old behavior)
    if [ -n "$key_path" ] && [ -f "$key_path" ]; then
        if echo "$key_path" | grep -q "ec2-instance-connect-$$"; then
            # Old style temp directory, clean it up
            local key_dir
            key_dir=$(dirname "$key_path")
            rm -rf "$key_dir"
        fi
        # Cached keys are left for reuse
    fi
}

# SSH command using EC2 Instance Connect
ssh_cmd_ec2_connect() {
    local ip="$1"
    local instance_id="$2"
    shift 2

    # Setup temporary key
    local temp_key
    if ! temp_key=$(setup_temp_ssh_key "$instance_id") || [ -z "$temp_key" ]; then
        log_error "Failed to send SSH public key via EC2 Instance Connect"
        return 1
    fi

    # Trap to cleanup on exit (use function to avoid variable expansion issues)
    _cleanup_key() {
        cleanup_temp_ssh_key "$temp_key"
    }
    trap _cleanup_key EXIT

    # Use temporary key for SSH
    ssh -i "$temp_key" \
        -o StrictHostKeyChecking=no \
        -o ConnectTimeout=10 \
        -o ServerAliveInterval=5 \
        -o ServerAliveCountMax=2 \
        "${EC2_USER}@${ip}" "$@"

    local exit_code=$?
    cleanup_temp_ssh_key "$temp_key"
    trap - EXIT
    return $exit_code
}


