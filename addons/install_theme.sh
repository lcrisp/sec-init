#!/usr/bin/env bash

set -e

THEME_NAME="Nordic"
THEME_URL="https://github.com/EliverLara/Nordic/archive/refs/heads/master.zip"
THEME_DIR="$HOME/.themes"

# Step 1: Ensure ~/.themes exists
mkdir -p "$THEME_DIR"

# Step 2: Install required engines (Debian/Ubuntu)
echo "[*] Installing theme engines..."
sudo apt update
sudo apt install -y gtk2-engines-murrine gtk2-engines-pixbuf unzip

# Step 3: Download theme zip
echo "[*] Downloading theme..."
cd /tmp
wget -O nordic.zip "$THEME_URL"

# Step 4: Extract to ~/.themes
echo "[*] Installing theme..."
unzip nordic.zip
rm -rf "$THEME_DIR/$THEME_NAME"
mv Nordic-master "$THEME_DIR/$THEME_NAME"

# Step 5: Cleanup
rm nordic.zip

echo "[+] Theme installed to $THEME_DIR/$THEME_NAME"
echo
echo "To apply:"
echo "  Settings → Appearance → Style → Nordic"
echo "  Settings → Window Manager → Style → Nordic"
