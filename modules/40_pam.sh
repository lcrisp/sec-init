#!/usr/bin/env bash
# Module: 40_pam.sh
# Purpose: Apply PAM hardening for YubiKey U2F authentication
# Ensures pam_deny.so is immediately after pam_u2f.so, replacing any existing deny lines.

set -euo pipefail
say(){ echo -e "\n[ $(date '+%F %T') ] $*"; }

say "[40] Applying PAM hardening"

PAM_FILES=(
    /etc/pam.d/common-auth
    /etc/pam.d/other
)

U2F_LINE='auth sufficient pam_u2f.so authfile=/etc/Yubico/u2f_keys cue'
DENY_LINE='auth required pam_deny.so'

for f in "${PAM_FILES[@]}"; do
    if [[ ! -f "$f" ]]; then
        say "Skipping missing PAM file: $f"
        continue
    fi

    # Remove ALL existing pam_deny lines to avoid loopholes
    sudo sed -i "/pam_deny.so/d" "$f"

    # Ensure U2F is present (insert at top if missing)
    if ! grep -qF "$U2F_LINE" "$f"; then
        sudo sed -i "1i $U2F_LINE" "$f"
        say "  Added U2F line to $f"
    else
        say "  U2F already present in $f"
    fi

    # Insert deny line *immediately after* the U2F line
    sudo awk -v u2f="$U2F_LINE" -v deny="$DENY_LINE" '
        $0 == u2f { print; print deny; next }
        { print }
    ' "$f" | sudo tee "$f.tmp" >/dev/null

    sudo mv "$f.tmp" "$f"
    say "  Ensured pam_deny follows pam_u2f in $f"

done

say "[40] PAM hardening complete"
