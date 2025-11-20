#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Build script that runs in tmux session
# Runs Yocto build and optionally post-build steps

KAS_CONFIG="$1"
YOCTO_DIR="$2"
LOG_FILE="/tmp/yocto-build.log"

# Source config if available
if [ -f "$HOME/edge-ai/build/yocto/config/yocto-config.sh" ]; then
    source "$HOME/edge-ai/build/yocto/config/yocto-config.sh"
fi

YOCTO_DIR="${YOCTO_DIR:-$HOME/yocto-tegra}"
YOCTO_MACHINE="${YOCTO_MACHINE:-jetson-orin-nano-devkit}"

log_info() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >> "$LOG_FILE"; }
log_success() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }

# Check if post-build should run
should_run_post_build() {
    return 0

    [ "$1" -eq 0 ] && \
    grep -q 'Tasks Summary:.*all succeeded' "$LOG_FILE" 2>/dev/null && \
    grep -q 'Running task' "$LOG_FILE" 2>/dev/null
}

# Find tegraflash archive
find_tegraflash_archive() {
    local artifacts_dir="$1"
    local archive

    archive=$(find "$artifacts_dir" -maxdepth 1 -name "*.tegraflash.tar.gz" -type f 2>/dev/null | head -1 || echo "")

    if [ -z "$archive" ]; then
        log_info "Trying alternative search method..."
        archive=$(ls -1 "$artifacts_dir"/*.tegraflash.tar.gz 2>/dev/null | head -1 || echo "")
    fi

    echo "$archive"
}

# Install device-tree-compiler if needed
install_device_tree_compiler() {
    if command -v dtc >/dev/null 2>&1; then
        log_info "device-tree-compiler already installed"
        return 0
    fi

    log_info "Installing device-tree-compiler package..."
    if sudo apt-get update -y && sudo apt-get install -y device-tree-compiler; then
        log_info "device-tree-compiler installed successfully"
        return 0
    else
        log_error "Failed to install device-tree-compiler"
        return 1
    fi
}

# Create SD card image from extracted archive
create_sdcard_image() {
    local tmpdir="$1"
    local sdcard_dir="$2"

    cd "$tmpdir"

    if [ ! -f "./dosdcard.sh" ]; then
        log_error "dosdcard.sh not found in tegraflash archive"
        return 1
    fi

    if ! install_device_tree_compiler; then
        return 1
    fi

    log_info "Creating SD card image..."
    chmod +x ./*.sh 2>/dev/null || true
    ./dosdcard.sh >> "$LOG_FILE" 2>&1

    local img
    img=$(find . -maxdepth 1 -name "*.sdcard" -type f | head -1)

    if [ -z "$img" ]; then
        log_error "SD card image (.sdcard) not found after running dosdcard.sh"
        return 1
    fi

    local img_name
    img_name=$(basename "$img")
    log_success "SD card image created: $img_name"

    log_info "Moving SD card image to artifacts directory..."
    mkdir -p "$sdcard_dir"
    mv "$img" "$sdcard_dir/"

    log_info "Compressing SD card image..."
    cd "$sdcard_dir"
    gzip -f "$img_name"

    local compressed_img="${img_name}.gz"
    log_success "SD card image compressed: $compressed_img"
    log_info "SD card image available at: $sdcard_dir/$compressed_img"

    return 0
}

# Run post-build steps
run_post_build() {
    local artifacts_dir="$YOCTO_DIR/build/tmp/deploy/images/$YOCTO_MACHINE"
    local artifacts_base_dir="$HOME/edge-ai-artifacts"
    local sdcard_dir="$artifacts_base_dir/sdcard"
    local extract_dir="$artifacts_base_dir/tegraflash-extract"

    log_info "Creating SD card image from tegraflash archive..."

    local tegraflash_tar
    tegraflash_tar=$(find_tegraflash_archive "$artifacts_dir")

    if [ -z "$tegraflash_tar" ]; then
        log_error "No tegraflash archive found. Build may have failed or used different image type."
        log_info "Files in $artifacts_dir:"
        ls -la "$artifacts_dir"/*.tar.gz 2>/dev/null || echo "No .tar.gz files found" >> "$LOG_FILE"
        return 1
    fi

    local archive_name
    archive_name=$(basename "$tegraflash_tar")
    log_info "Found tegraflash archive: $archive_name"

    log_info "Extracting tegraflash archive to $extract_dir..."
    mkdir -p "$extract_dir"

    # Clean up any previous extraction
    if [ -n "$extract_dir" ] && [ -d "$extract_dir" ]; then
        find "$extract_dir" -mindepth 1 -delete 2>/dev/null || true
    fi

    log_info "Extracting tegraflash archive..."
    tar -xzf "$tegraflash_tar" -C "$extract_dir"

    create_sdcard_image "$extract_dir" "$sdcard_dir"
}

# Main execution
export PATH="$HOME/.local/bin:$PATH"
cd "$YOCTO_DIR"

# Run the build
kas build --update "$KAS_CONFIG" 2>&1 | tee "$LOG_FILE"
BUILD_EXIT="${PIPESTATUS[0]}"

# Run post-build if conditions are met
if should_run_post_build "$BUILD_EXIT"; then
    echo '' >> "$LOG_FILE"
    echo '=== Starting post-build: Creating SD card image ===' >> "$LOG_FILE"
    run_post_build
else
    echo '' >> "$LOG_FILE"
    echo '=== Skipping post-build: No tasks were executed ===' >> "$LOG_FILE"
fi

exit "$BUILD_EXIT"

