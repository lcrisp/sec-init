#!/usr/bin/env bash
# Module: 70_grub.sh
# Purpose: Harden GRUB with a superuser + password and disable recovery menu entries
# This module is sourced by secure-init.sh and runs as a normal user (uses sudo internally).

set -euo pipefail
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
say(){ echo -e "\n[ $(date '+%F %T') ] $*"; }
need(){ command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1"; exit 1; }; }

say "[70] GRUB hardening module starting"

need grub-mkpasswd-pbkdf2
need update-grub

say "This will:" 
say "  - Set a GRUB superuser to '$USER' with a password"
say "  - Disable recovery entries (GRUB_DISABLE_RECOVERY=\"true\")"
say "  - Require the GRUB password for advanced operations (edit, console, etc.)"

read -rp "Proceed with GRUB hardening? [y/N]: " ans
case "${ans,,}" in
  y|yes) : ;;  
  *) say "[70] Skipping GRUB hardening"; exit 0 ;;
esac

# --- Backup /etc/default/grub ---
if [[ -f /etc/default/grub ]]; then
  sudo cp -p /etc/default/grub /etc/default/grub.secure-init.bak
  say "[70] Backed up /etc/default/grub to /etc/default/grub.secure-init.bak"
fi

# --- Ensure GRUB_DISABLE_RECOVERY="true" ---
if grep -q '^GRUB_DISABLE_RECOVERY' /etc/default/grub 2>/dev/null; then
  sudo sed -i 's/^GRUB_DISABLE_RECOVERY.*/GRUB_DISABLE_RECOVERY="true"/' /etc/default/grub
else
  echo 'GRUB_DISABLE_RECOVERY="true"' | sudo tee -a /etc/default/grub >/dev/null
fi

# --- Generate GRUB PBKDF2 hash ---
TMP_HASH_FILE="/tmp/grub.password.$$"

say "[70] Running grub-mkpasswd-pbkdf2 (you will be asked for the GRUB password twice)"
# This runs as the invoking user; output goes to a temp file for parsing
grub-mkpasswd-pbkdf2 | tee "$TMP_HASH_FILE"

HASH=$(awk '/grub.pbkdf2/ {print $NF}' "$TMP_HASH_FILE" || true)
if command -v shred >/dev/null 2>&1; then
  shred -u "$TMP_HASH_FILE"
else
  rm -f "$TMP_HASH_FILE"
fi

if [[ -z "${HASH:-}" ]]; then
  say "[70] ERROR: Failed to parse grub.pbkdf2 hash. Aborting."
  exit 1
fi

say "[70] Got GRUB hash: $HASH"

# --- Write /etc/grub.d/40_custom correctly ---
# 40_custom is a shell script that prints GRUB commands; the first two lines
# are shell, the rest are GRUB config. The exec tail line prevents the shell
# from trying to execute GRUB commands like 'password_pbkdf2'.

sudo tee /etc/grub.d/40_custom >/dev/null <<EOF
#!/bin/sh
exec tail -n +3 \$0
set superusers="$USER"
password_pbkdf2 $USER $HASH
EOF

sudo chmod 755 /etc/grub.d/40_custom

# --- Regenerate GRUB config ---
say "[70] Running update-grub to apply changes"
sudo update-grub

say "[70] GRUB hardening complete. Remember this password — it cannot be recovered."
