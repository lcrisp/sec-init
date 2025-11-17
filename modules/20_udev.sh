#!/usr/bin/env bash
# Module: 20_udev.sh
# Purpose: Create strict YubiKey udev rules + ensure plugdev membership
# This module is sourced by secure-init.sh

set -euo pipefail
say(){ echo -e "\n[ $(date '+%F %T') ] $*"; }

# --- Variables ---
RULE_FILE="/etc/udev/rules.d/99-yubikey.rules"
VENDOR="1050"      # YubiKey vendor ID\PRODUCT="0407"     # Challenge‑Response / FIDO2 capable key

say "[20] Applying YubiKey udev rules"

# Ensure user is in plugdev
groups "$USER" | grep -q '\bplugdev\b' || {
    say "Adding user $USER to plugdev group";
    sudo usermod -aG plugdev "$USER";
}

# Write strict rule (hidraw, correct vendor/product, and uaccess for desktop auth)
echo "KERNEL==\"hidraw*\", SUBSYSTEM==\"hidraw\", ATTRS{idVendor}==\"$VENDOR\", ATTRS{idProduct}==\"$PRODUCT\", MODE=\"0660\", GROUP=\"plugdev\", TAG+=\"uaccess\"" \
  | sudo tee "$RULE_FILE" >/dev/null

# Reload udev rules
sudo udevadm control --reload-rules
sudo udevadm trigger

say "[20] Udev rules loaded — remove and reinsert YubiKey then continue."
