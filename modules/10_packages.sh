#!/usr/bin/env bash
# Module: 10_packages.sh
# Purpose: Install core packages for YubiKey FIDO2 + SSH + LUKS bootstrap
# This module is sourced by secure-init.sh with the environment protected.

set -euo pipefail
say(){ echo -e "\n[ $(date '+%F %T') ] $*"; }
need(){ command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1"; exit 1; }; }

say "[10] Installing baseline packages"

# Required utilities
need sudo
need apt-get

# Update package lists
sudo apt-get update -y

# Core packages
sudo apt-get install -y \
    ufw \
    libpam-u2f \
    systemd-cryptsetup \
    openssh-client \
#    openssh-server \
    keepassxc || true

# Dracut is optional; Debian-based systems may not require it
#sudo apt-get install -y dracut || true

say "[10] Package installation complete"
#!/usr/bin/env bash
# 10_packages.sh — install packages from packages.list
# Called by secure-init.sh master script

set -euo pipefail
say(){ echo -e "[10_packages] $*"; }

MODULE_DIR="${MODULE_DIR:-$(pwd)}"
PKGLIST_FILE="$MODULE_DIR/packages.list"

say "Loading package list…"
if [[ ! -f "$PKGLIST_FILE" ]]; then
  say "ERROR: packages.list not found at $PKGLIST_FILE"
  exit 1
fi

say "Updating APT indices…"
sudo apt-get update -y

say "Installing packages…"
grep -E '^[^#]' "$PKGLIST_FILE" | sed '/^\s*$/d' | while read -r pkg; do
    say "Installing: $pkg"
    sudo apt-get install -y "$pkg" || true
done

say "10_packages module complete."
