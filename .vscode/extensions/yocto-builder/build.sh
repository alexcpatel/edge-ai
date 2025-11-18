#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTENSION_DIR="$SCRIPT_DIR"
CURSOR_EXTENSIONS_DIR="$HOME/.cursor/extensions"
EXTENSION_NAME="yocto-builder-0.1.0"

echo "Building Yocto Builder extension..."
cd "$EXTENSION_DIR"

# Compile TypeScript
echo "Compiling TypeScript..."
npm run compile

# Create symlink in Cursor extensions directory
echo "Installing extension to Cursor..."
mkdir -p "$CURSOR_EXTENSIONS_DIR"
ln -sfn "$EXTENSION_DIR" "$CURSOR_EXTENSIONS_DIR/$EXTENSION_NAME"

echo "✓ Extension built and installed successfully!"
echo "  Reload Cursor (Cmd+Shift+P -> 'Developer: Reload Window') to activate changes."

