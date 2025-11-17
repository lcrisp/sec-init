#!/usr/bin/env bash
# Module: 50_crypttab.sh
# Purpose: Configure /etc/crypttab for FIDO2-backed LUKS unlock
# This module is sourced by secure-init.sh

set -euo pipefail
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
say(){ echo -e "\n[ $(date '+%F %T') ] $*"; }
need(){ command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1"; exit 1; }; }

say "[50] Updating /etc/crypttab for FIDO2 unlock"

need blkid
need tee

# Ask user for LUKS device path
read -rp "Enter LUKS device to configure (e.g., /dev/sda3): " LUKS_DEV

if [[ ! -b "$LUKS_DEV" ]]; then
    say "ERROR: $LUKS_DEV is not a valid block device"
    exit 1
fi

UUID=$(sudo blkid -s UUID -o value "$LUKS_DEV") || {
    say "ERROR: Could not get UUID for $LUKS_DEV"
    exit 1
}

NAME="cryptroot"
if [[ -f /etc/crypttab ]]; then
    EXISTING_NAME="$(awk -v uuid="$UUID" -v dev="$LUKS_DEV" '
        $0 ~ /^\s*#/ { next }
        $2 ~ uuid || $2 ~ dev { print $1; exit }
    ' /etc/crypttab || true)"
    if [[ -n "${EXISTING_NAME:-}" ]]; then
        NAME="$EXISTING_NAME"
        say "Detected existing crypttab entry name: $NAME"
    fi
fi

read -rp "Enter mapper name to use [${NAME}]: " NAME_INPUT
if [[ -n "${NAME_INPUT:-}" ]]; then
    NAME="$NAME_INPUT"
fi

LINE="$NAME UUID=$UUID none luks,fido2-device=auto"

# Ensure crypttab exists
sudo touch /etc/crypttab

# Replace existing entry for this UUID or append a new one
if grep -q "UUID=$UUID" /etc/crypttab 2>/dev/null; then
    say "Updating existing crypttab entry"
    sudo awk -v u="UUID=$UUID" -v rep="$LINE" '($0 ~ u){print rep;next}1' /etc/crypttab | sudo tee /etc/crypttab >/dev/null
else
    say "Appending new entry to crypttab"
    echo "$LINE" | sudo tee -a /etc/crypttab >/dev/null
fi

say "[50] crypttab configuration completed. Rebuild initramfs in later module."
