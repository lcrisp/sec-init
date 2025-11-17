#!/usr/bin/env bash
# Module: finish.sh   (always called last by secure-init.sh)
# Purpose: Apply mandatory sudo hardening + controlled reboot countdown.

set -euo pipefail
say(){ echo -e "\n[ $(date '+%F %T') ] $*"; }

say "[finish] Finalising system hardening"

###############################
# 1. MANDATORY SUDO HARDENING #
###############################
say "[finish] Enforcing sudo timestamp_timeout=0"

TARGET="/etc/sudoers.d/90_timestamp_timeout"
TMPFILE="$(mktemp)"

# Produce the rule
echo "Defaults timestamp_timeout=0" > "$TMPFILE"

# Validate safely before installing
say "  Validating sudoers fragment with visudo -cf"
if ! sudo visudo -cf "$TMPFILE"; then
    say "ERROR: sudoers syntax invalid! Aborting."
    rm -f "$TMPFILE"
    exit 1
fi

# Install atomically
say "  Installing sudoers hardening rule"
sudo install -m 440 "$TMPFILE" "$TARGET"
rm -f "$TMPFILE"

say "  Sudo will now reprompt every time."


#############################################
# 2. FINAL SUMMARY + REBOOT CONFIRMATION    #
#############################################
say "[finish] All modules executed successfully."

echo
echo "Press <Enter> to CANCEL the reboot countdown."
echo "Otherwise the system will automatically reboot in 10 seconds."
read -t 10 -r && {
    say "Reboot cancelled by user."
    exit 0
}

say "Rebooting now..."
sync
sudo systemctl reboot -f
