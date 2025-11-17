#!/usr/bin/env bash
# Module: 10_packages.sh
# Purpose: Install baseline + user + extra packages for secure-init
# Imports three lists from ./lists/

set -euo pipefail
say(){ echo -e "\n[ $(date '+%F %T') ] $*"; }

# --- Absolute module + lists paths ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${LISTDIR:-}" ]]; then
    LISTDIR="$SCRIPT_DIR/../lists"
fi
if [[ ! -d "$LISTDIR" ]]; then
    ERR_MSG="Package lists directory not found: $LISTDIR"
    say "$ERR_MSG"
    exit 1
fi
LISTDIR="$(cd "$LISTDIR" && pwd)"

DEFAULT_LIST="$LISTDIR/packages-default.list"
USER_LIST="$LISTDIR/packages-user.list"
EXTRA_LIST="$LISTDIR/packages-extra.list"

say "[10] Installing packages from defaults + user-defined lists"

# ---- Validation -----------------------------------------------------------
for f in "$DEFAULT_LIST" "$USER_LIST" "$EXTRA_LIST"; do
    if [[ ! -f "$f" ]]; then
        say "WARNING: Package list missing: $f"
    fi
done

# ---- Build consolidated list ---------------------------------------------
TMP_PKG="$(mktemp)"
filter_manifest() {
    local list_file="$1"
    [[ -f "$list_file" ]] || return 0
    grep -Ev '^\s*$|^\s*#' "$list_file" || true
}

{
    filter_manifest "$DEFAULT_LIST"
    filter_manifest "$USER_LIST"
    filter_manifest "$EXTRA_LIST"
} | sort -u > "$TMP_PKG"

if [[ ! -s "$TMP_PKG" ]]; then
    say "[10] No packages to install — manifest is empty. Exiting."
    rm -f "$TMP_PKG"
    exit 0
fi

say "[10] Package manifest:"
sed 's/^/   - /' "$TMP_PKG"

say "[10] apt update"
sudo apt-get update -y

say "[10] Installing package set"
if ! sudo xargs -a "$TMP_PKG" apt-get install -y; then
    say "[10] WARNING: Some packages failed to install (continuing)"
fi

# Ensure dracut exists (Debian sometimes omits it)
if ! command -v dracut >/dev/null 2>&1; then
    sudo apt-get install -y dracut || true
fi

say "[10] Package installation complete"

# ---- Run addon installers -------------------------------------------------
if [[ -z "${ADDONS_DIR:-}" ]]; then
    ADDONS_DIR="$SCRIPT_DIR/../addons"
fi
if [[ -d "$ADDONS_DIR" ]]; then
    say "[10] Running addons from $ADDONS_DIR"
    while IFS= read -r -d '' addon; do
        say "[10] Executing addon: $(basename "$addon")"
        if bash "$addon"; then
            say "[10] Addon succeeded: $(basename "$addon")"
        else
            say "[10] WARNING: Addon failed: $(basename "$addon")"
        fi
    done < <(find "$ADDONS_DIR" -maxdepth 1 -type f -name '*.sh' -print0 | sort -z)
else
    say "[10] No addons directory found at $ADDONS_DIR — skipping."
fi

rm -f "$TMP_PKG"
