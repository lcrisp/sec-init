#!/usr/bin/env bash
# Module: 30_enroll.sh
# Purpose: Unified enrollment of YubiKeys for PAM U2F, SSH resident keys, and LUKS
# This module is sourced by secure-init.sh

set -euo pipefail
say(){ echo -e "\n[ $(date '+%F %T') ] $*"; }
need(){ command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1"; exit 1; }; }

say "[30] Unified YubiKey enrollment starting"

# --- Requirements ---
need pamu2fcfg
need ssh-keygen
need systemd-cryptenroll

# --- Ask user for LUKS device ---
read -rp "Enter LUKS device to enroll (e.g., /dev/sda3): " LUKS_DEV

# Validate device exists
[[ -b "$LUKS_DEV" ]] || { echo "Device not found: $LUKS_DEV"; exit 1; }

# Ensure config directories exist
mkdir -p "$HOME/.config/Yubico" "$HOME/.ssh"
chmod 700 "$HOME/.config/Yubico" "$HOME/.ssh"
AUTH_KEYS="$HOME/.ssh/authorized_keys"
touch "$AUTH_KEYS"
chmod 600 "$AUTH_KEYS"

# --- FIRST KEY ---
say "Insert FIRST YubiKey and press <Enter>."
read -r

# PAM enrollment
echo "Generating first pamu2fcfg entry..."
sg plugdev -c "pamu2fcfg > \"$HOME/.config/Yubico/u2f_keys\""
chmod 600 "$HOME/.config/Yubico/u2f_keys"

# SSH resident key pull
ssh-keygen -K || true
FIRST_PUB="$(ls -1t "$HOME/.ssh"/id_ed25519_sk.pub "$HOME/.ssh"/id_ecdsa_sk.pub 2>/dev/null | head -n1 || true)"
if [[ -n "${FIRST_PUB:-}" ]]; then
    base="${FIRST_PUB%.pub}"
    cp -p "$base" "$HOME/.ssh/id_yubi1_sk" 2>/dev/null || true
    cp -p "$FIRST_PUB" "$HOME/.ssh/id_yubi1_sk.pub" 2>/dev/null || true
    echo "Added FIRST resident key: $FIRST_PUB"
    cat "$FIRST_PUB" >> "$AUTH_KEYS"
    [[ -n "$base" ]] && rm -f "$base" "$FIRST_PUB"
else
    base=""
fi

# LUKS token enrollment
say "Enrolling FIRST YubiKey into LUKS..."
sudo systemd-cryptenroll "$LUKS_DEV" --fido2-device=auto

# --- SECOND KEY ---
say "Insert SECOND YubiKey and press <Enter>."
read -r

echo "Appending second pamu2fcfg entry..."
sg plugdev -c "pamu2fcfg >> \"$HOME/.config/Yubico/u2f_keys\""
chmod 600 "$HOME/.config/Yubico/u2f_keys"

ssh-keygen -K || true
SECOND_PUB="$(ls -1t "$HOME/.ssh"/id_ed25519_sk.pub "$HOME/.ssh"/id_ecdsa_sk.pub 2>/dev/null | head -n1 || true)"
if [[ -n "${SECOND_PUB:-}" ]]; then
    base2="${SECOND_PUB%.pub}"
    if [[ -z "$base" || "$base2" != "$base" ]]; then
        cp -p "$base2" "$HOME/.ssh/id_yubi2_sk" 2>/dev/null || true
        cp -p "$SECOND_PUB" "$HOME/.ssh/id_yubi2_sk.pub" 2>/dev/null || true
        echo "Added SECOND resident key: $SECOND_PUB"
        cat "$SECOND_PUB" >> "$AUTH_KEYS"
        rm -f "$base2" "$SECOND_PUB"
    fi
fi

# LUKS token enrollment for second key
say "Enrolling SECOND YubiKey into LUKS..."
sudo systemd-cryptenroll "$LUKS_DEV" --fido2-device=auto

# Copy PAM file into place
sudo install -D -o "$USER" -g plugdev -m 600 "$HOME/.config/Yubico/u2f_keys" /etc/Yubico/u2f_keys

say "[30] Enrollment complete."
