#!/usr/bin/env bash
# Module: 25_keyring.sh
# Purpose: Disable GNOME Keyring autostart so password prompts do not block FIDO2-only logins.

set -euo pipefail
say(){ echo -e "\n[ $(date '+%F %T') ] $*"; }

say "[25] Disabling GNOME Keyring autostart prompts"

AUTOSTART_DIR="$HOME/.config/autostart"
mkdir -p "$AUTOSTART_DIR"

disable_entry(){
    local file="$1"
    local title="$2"
    local target="$AUTOSTART_DIR/$file"

    cat >"$target" <<EOF
[Desktop Entry]
Type=Application
Name=$title (disabled by secure-init)
Exec=true
Hidden=true
X-GNOME-Autostart-enabled=false
EOF
    say "  → Disabled $file via $target"
}

disable_entry "gnome-keyring-secrets.desktop" "GNOME Keyring secrets component"
disable_entry "gnome-keyring-pkcs11.desktop" "GNOME Keyring PKCS#11 component"

if command -v systemctl >/dev/null 2>&1; then
    systemctl --user mask gnome-keyring-daemon.service >/dev/null 2>&1 || true
    systemctl --user mask gnome-keyring-daemon.socket >/dev/null 2>&1 || true
    say "  → Masked gnome-keyring-daemon user units (service + socket)"
fi

say "[25] GNOME Keyring disabled — secrets/SSH agents will no longer prompt at login"
