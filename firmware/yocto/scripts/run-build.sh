#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Build script that runs in tmux session
# Runs Yocto build

# Ensure PATH includes user's local bin (where pip installs --user scripts)
# This must be set early, before any commands that might need it
export PATH="$HOME/.local/bin:$PATH"

KAS_CONFIG="$1"
YOCTO_DIR="$2"
LOG_FILE="/tmp/yocto-build.log"

# Source config if available
if [ -f "$HOME/edge-ai/build/yocto/config/yocto-config.sh" ]; then
    source "$HOME/edge-ai/build/yocto/config/yocto-config.sh"
fi

YOCTO_DIR="${YOCTO_DIR:-$HOME/yocto-tegra}"

log_info() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >> "$LOG_FILE"; }
log_success() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }

# Verify kas is available before proceeding
if ! command -v kas >/dev/null 2>&1; then
    log_error "kas command not found. PATH: $PATH"
    log_error "Please ensure kas is installed: python3 -m pip install --user --break-system-packages kas"
    exit 1
fi

# Main execution
cd "$YOCTO_DIR"

# Run the build
kas build --update "$KAS_CONFIG" 2>&1 | tee "$LOG_FILE"
BUILD_EXIT="${PIPESTATUS[0]}"

exit "$BUILD_EXIT"

