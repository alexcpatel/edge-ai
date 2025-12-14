#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Build script that runs in tmux session
# Fetches claim certs from SSM, then runs Yocto build

# Ensure PATH includes user's local bin (where pip installs --user scripts)
export PATH="$HOME/.local/bin:$PATH"

# AWS region for SSM calls (must match where parameters are stored)
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-2}"

KAS_CONFIG="$1"
YOCTO_DIR="$2"
LOG_FILE="/tmp/yocto-build.log"
BUILD_HISTORY_FILE="$HOME/.ec2-build-history.json"

# Start fresh log
echo "Build started at $(date)" > "$LOG_FILE"

# Record build start time
BUILD_START_TIME=$(date +%s)
echo "$BUILD_START_TIME" > /tmp/build-start-time

YOCTO_DIR="${YOCTO_DIR:-$HOME/yocto-tegra}"
SOURCE_DIR="${YOCTO_DIR}/edge-ai"
CLAIM_CERTS_DIR="$SOURCE_DIR/firmware/yocto/meta-edge-secure/recipes-core/claim-certs/edge-claim-certs"
CONTAINER_CONFIG_DIR="$SOURCE_DIR/firmware/yocto/meta-edge-secure/recipes-core/container-policy/edge-container-policy"

log_info() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "$LOG_FILE" >&2; }

# Verify kas is available
if ! command -v kas >/dev/null 2>&1; then
    log_error "kas command not found. PATH: $PATH"
    exit 1
fi

# Fetch claim certificates from SSM Parameter Store
fetch_claim_certs() {
    log_info "Fetching claim certificates from SSM..."

    mkdir -p "$CLAIM_CERTS_DIR"

    # Fetch certificate
    aws ssm get-parameter \
        --name "/edge-ai/fleet-provisioning/claim-cert" \
        --with-decryption \
        --query 'Parameter.Value' \
        --output text > "$CLAIM_CERTS_DIR/claim.crt" || {
        log_error "Failed to fetch claim certificate from SSM"
        return 1
    }

    # Fetch private key
    aws ssm get-parameter \
        --name "/edge-ai/fleet-provisioning/claim-key" \
        --with-decryption \
        --query 'Parameter.Value' \
        --output text > "$CLAIM_CERTS_DIR/claim.key" || {
        log_error "Failed to fetch claim key from SSM"
        return 1
    }
    chmod 600 "$CLAIM_CERTS_DIR/claim.key"

    # Fetch config
    aws ssm get-parameter \
        --name "/edge-ai/fleet-provisioning/config" \
        --query 'Parameter.Value' \
        --output text > "$CLAIM_CERTS_DIR/config.json" || {
        log_error "Failed to fetch claim config from SSM"
        return 1
    }

    # Fetch NordVPN token (required)
    local nordvpn_token
    nordvpn_token=$(aws ssm get-parameter \
        --name "/edge-ai/nordvpn-token" \
        --with-decryption \
        --query 'Parameter.Value' \
        --output text 2>/dev/null || echo "")

    if [ -z "$nordvpn_token" ] || [ "$nordvpn_token" = "PLACEHOLDER_SET_VIA_CONSOLE" ]; then
        log_error "NordVPN token not configured in SSM at /edge-ai/nordvpn-token"
        return 1
    fi

    echo "$nordvpn_token" > "$CLAIM_CERTS_DIR/nordvpn-token"
    chmod 600 "$CLAIM_CERTS_DIR/nordvpn-token"
    log_info "NordVPN token fetched"

    log_info "Claim certificates fetched successfully"
}

# Fetch container signing config from SSM
fetch_container_config() {
    log_info "Fetching container signing config from SSM..."

    mkdir -p "$CONTAINER_CONFIG_DIR"

    # Fetch container signing public key (optional - may not exist yet)
    if aws ssm get-parameter \
        --name "/edge-ai/pki/container-signing-public-key" \
        --query 'Parameter.Value' \
        --output text > "$CONTAINER_CONFIG_DIR/container-signing.pub" 2>/dev/null; then
        log_info "Container signing public key fetched"
    else
        log_info "Container signing public key not found in SSM (run terraform apply in backend/iot/terraform)"
        # Create placeholder so build doesn't fail
        echo "# Container signing not configured yet" > "$CONTAINER_CONFIG_DIR/container-signing.pub"
    fi

    # Fetch ECR repository URL (optional - may not exist yet)
    if aws ssm get-parameter \
        --name "/edge-ai/ecr/repository-url" \
        --query 'Parameter.Value' \
        --output text > "$CONTAINER_CONFIG_DIR/ecr-url.txt" 2>/dev/null; then
        log_info "ECR repository URL fetched"
    else
        log_info "ECR repository URL not found in SSM (run terraform apply in backend/iot/terraform)"
        echo "# ECR not configured yet" > "$CONTAINER_CONFIG_DIR/ecr-url.txt"
    fi
}

# Main execution
fetch_claim_certs || {
    log_error "Claim cert fetch failed - cannot build without credentials"
    exit 1
}

fetch_container_config

cd "$YOCTO_DIR"

# Create symlink so KAS can find the layer (KAS resolves paths relative to build directory)
ACTUAL_LAYER="$SOURCE_DIR/firmware/yocto/meta-edge-secure"
EXPECTED_LAYER="$YOCTO_DIR/../edge-ai/firmware/yocto/meta-edge-secure"

if [ ! -d "$ACTUAL_LAYER" ]; then
    log_error "Layer not found at: $ACTUAL_LAYER"
    log_error "SOURCE_DIR: $SOURCE_DIR"
    log_error "Listing firmware/yocto contents:"
    ls -la "$SOURCE_DIR/firmware/yocto/" 2>&1 | tee -a "$LOG_FILE" >&2 || true
    exit 1
fi

# Create parent directory and symlink
mkdir -p "$(dirname "$EXPECTED_LAYER")"
ln -sfn "$ACTUAL_LAYER" "$EXPECTED_LAYER" 2>/dev/null || true

# Run the build (tee to both log file and stdout so errors are visible)
kas build --update "$KAS_CONFIG" 2>&1 | tee -a "$LOG_FILE"
BUILD_EXIT="${PIPESTATUS[0]}"

# Write exit code for watch-build.sh to read
echo "$BUILD_EXIT" > /tmp/yocto-build-exit

exit "$BUILD_EXIT"

