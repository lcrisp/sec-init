#!/usr/bin/env bash
set -euo pipefail

TB_DIR="$HOME/tor-browser"
APP_DIR="$HOME/.local/share/applications"
DESKTOP_FILE="$APP_DIR/tor-browser.desktop"
PAGE_URL="https://www.torproject.org/download/"
TB_DIR="$HOME/tor-browser"

echo "[*] Fetching Tor Browser download page…"
HTML="$(curl -fsSL "$PAGE_URL")"

echo "[*] Extracting Linux download link…"
REL_URL=$(echo "$HTML" \
    | grep -oP '/dist/torbrowser/[^"]+/tor-browser-linux-x86_64-[^"]+\.tar\.xz' \
    | head -n1)

if [[ -z "$REL_URL" ]]; then
    echo "[!] Failed to locate Linux Tor Browser URL."
    exit 1
fi

URL="https://www.torproject.org${REL_URL}"
SIG_URL="${URL}.asc"

echo "[*] Bundle:    $URL"
echo "[*] Signature: $SIG_URL"

mkdir -p "$TB_DIR"
cd "$TB_DIR"

echo "[*] Downloading Tor Browser bundle and signature…"
curl -fsSLO "$URL"
curl -fsSLO "$SIG_URL"

FILE=$(basename "$URL")
SIGFILE=$(basename "$SIG_URL")

echo "[*] Fetching Tor Browser Developers signing key via WKD…"
gpg --auto-key-locate nodefault,wkd --locate-keys torbrowser@torproject.org

echo "[*] Verifying signature…"
gpg --verify "$SIGFILE" "$FILE"

echo "[*] Extracting Tor Browser…"
tar -xf "$FILE" --strip-components=1

echo ""
echo "[✓] Tor Browser installed successfully!"
echo "Run with:"
echo "  $TB_DIR/Browser/start-tor-browser"
echo ""

### Cleanup ###

echo "[*] Cleaning up leftover archive files…"
rm -f "$TB_DIR"/*.tar.xz "$TB_DIR"/*.asc

echo "[*] Installing .desktop launcher into XFCE menu…"
mkdir -p "$APP_DIR"

cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=Tor Browser
Exec=$TB_DIR/Browser/start-tor-browser
Icon=$TB_DIR/Browser/browser/chrome/icons/default/default128.png
Terminal=false
Categories=Network;WebBrowser;Security;
StartupNotify=true
EOF

echo "[*] Making launcher executable…"
chmod +x "$DESKTOP_FILE"

echo "[*] Updating desktop database (optional)…"
update-desktop-database "$APP_DIR" 2>/dev/null || true

echo ""
echo "[✓] Cleanup complete."
echo "[✓] Tor Browser integrated into XFCE menu (Internet → Tor Browser)."
echo ""
echo "To run manually:"
echo "  $TB_DIR/Browser/start-tor-browser"
