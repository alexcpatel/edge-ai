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

# Start fresh log
echo "Build started at $(date)" > "$LOG_FILE"

YOCTO_DIR="${YOCTO_DIR:-$HOME/yocto-tegra}"
SOURCE_DIR="${YOCTO_DIR}/edge-ai"
CLAIM_CERTS_DIR="$SOURCE_DIR/firmware/yocto/meta-edge-secure/recipes-core/claim-certs/edge-claim-certs"

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

# Main execution
fetch_claim_certs || {
    log_error "Claim cert fetch failed - cannot build without credentials"
    exit 1
}

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

exit "$BUILD_EXIT"

