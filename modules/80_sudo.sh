#!/usr/bin/env bash
# Module: 80_sudo.sh
# Purpose: Optional sudo hardening (timestamp_timeout=0)
# This module is sourced by secure-init.sh with the environment protected.

set -euo pipefail
say(){ echo -e "\n[ $(date '+%F %T') ] $*"; }

say "[80] Optional sudo hardening"

read -rp "Enforce sudo reprompt every time? (Defaults timestamp_timeout=0) [y/N]: " ans
if [[ "${ans,,}" != y* ]]; then
    say "[80] Skipping sudo reprompt hardening"
    if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
        return 0
    else
        exit 0
    fi
fi

TARGET="/etc/sudoers.d/90_timestamp_timeout"

# Create temp file for validation
TMPFILE="$(mktemp)"
echo "Defaults timestamp_timeout=0" > "$TMPFILE"

say "  Validating sudoers fragment with visudo -cf"
if ! sudo visudo -cf "$TMPFILE"; then
    say "ERROR: sudoers validation failed. Not applying change."
    rm -f "$TMPFILE"
    exit 1
fi

say "  Installing sudoers hardening rule"
sudo install -m 440 "$TMPFILE" "$TARGET"
rm -f "$TMPFILE"

say "[80] Sudo reprompt hardening applied successfully"
