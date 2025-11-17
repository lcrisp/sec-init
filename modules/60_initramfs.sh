#!/usr/bin/env bash
# Module: 60_initramfs.sh
# Purpose: Rebuild initramfs cleanly with HID/FIDO2 support after crypttab changes

set -euo pipefail
say(){ echo -e "\n[ $(date '+%F %T') ] $*"; }

say "[60] Updating initramfs with HID/FIDO2 support"

# Detect OS family
. /etc/os-release || true
ID_LIKE_LOWER="$(echo "${ID_LIKE:-$ID}" | tr '[:upper:]' '[:lower:]')"
ID_LOWER="$(echo "${ID:-}" | tr '[:upper:]' '[:lower:]')"

# ----------------------------------------------------------------------
# 1) Add necessary USB/HID drivers for early boot
#    Format is different for dracut vs initramfs-tools
# ----------------------------------------------------------------------

if command -v dracut >/dev/null 2>&1; then
    say "  dracut detected — installing HID rules"
    sudo mkdir -p /etc/dracut.conf.d

    # Correct formatting: NO spaces inside += quotes
    echo 'add_drivers+=" usbhid hid_generic xhci_pci xhci_hcd ehci_pci ehci_hcd "' \
        | sudo tee /etc/dracut.conf.d/99-hid.conf >/dev/null

else
    say "  initramfs-tools detected — installing HID rules"
    sudo mkdir -p /etc/initramfs-tools/conf.d

    cat <<'EOF' | sudo tee /etc/initramfs-tools/conf.d/hid-yubikey.conf >/dev/null
# Include HID + USB drivers in early userspace
MODULES=most
EOF

fi

# ----------------------------------------------------------------------
# 2) Actually rebuild the initramfs
# ----------------------------------------------------------------------
say "  Rebuilding initramfs now"

if command -v dracut >/dev/null 2>&1; then
    sudo dracut -f
else
    sudo update-initramfs -u
fi

say "[60] initramfs update complete"
