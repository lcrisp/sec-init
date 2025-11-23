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
LOG_ROOT="${LOG_DIR:-$HOME/.logs/secure-init}"
mkdir -p "$LOG_ROOT"
PKG_LOG="$LOG_ROOT/packages-install.log"

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

say "[10] Logging apt output to $PKG_LOG"

detect_release() {
    if command -v lsb_release >/dev/null 2>&1; then
        DISTRO=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
        CODENAME=$(lsb_release -sc)
        RELEASE_DESC=$(lsb_release -sd || true)
    elif [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        DISTRO="${ID:-}"
        CODENAME="${VERSION_CODENAME:-}"
        RELEASE_DESC="${PRETTY_NAME:-$ID}"
    else
        say "[10] WARNING: Unable to detect distribution; leaving sources.list unchanged"
        return 1
    fi

    if [[ -z "${DISTRO:-}" || -z "${CODENAME:-}" ]]; then
        say "[10] WARNING: Missing distro/codename; leaving sources.list unchanged"
        return 1
    fi

    say "[10] Detected release: ${RELEASE_DESC:-$DISTRO} ($DISTRO/$CODENAME)"
    return 0
}

configure_sources_list() {
    if ! detect_release; then
        return 0
    fi

    case "$DISTRO" in
        ubuntu)
            MIRROR="http://mirror.linux.org.au/ubuntu"
            sudo tee /etc/apt/sources.list >/dev/null <<EOF
deb $MIRROR $CODENAME main restricted universe multiverse
deb $MIRROR $CODENAME-updates main restricted universe multiverse
deb $MIRROR $CODENAME-backports main restricted universe multiverse
deb $MIRROR $CODENAME-security main restricted universe multiverse
EOF
            ;;
        debian)
            sudo tee /etc/apt/sources.list >/dev/null <<'EOF'
deb [signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] http://mirror.linux.org.au/debian forky main contrib non-free non-free-firmware
deb [signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] http://mirror.linux.org.au/debian forky-updates main contrib non-free non-free-firmware
deb [signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] http://deb.debian.org/debian-security trixie-security main contrib non-free non-free-firmware
EOF
            ;;
        *)
            say "[10] WARNING: Unsupported distro '$DISTRO'; leaving sources.list unchanged"
            return 0
            ;;
    esac

    say "[10] /etc/apt/sources.list updated to mirror.linux.org.au"
}

configure_sources_list

say "[10] apt update"
sudo apt-get update -y 2>&1 | tee -a "$PKG_LOG"
UPDATE_STATUS=${PIPESTATUS[0]}
if [[ $UPDATE_STATUS -ne 0 ]]; then
    say "[10] WARNING: apt update reported failures (see $PKG_LOG)"
fi

say "[10] Installing package set"
sudo xargs -a "$TMP_PKG" apt-get install -y 2>&1 | tee -a "$PKG_LOG"
INSTALL_STATUS=${PIPESTATUS[0]}
if [[ $INSTALL_STATUS -ne 0 ]]; then
    say "[10] WARNING: Some packages failed to install (continuing — see $PKG_LOG)"
fi

# Ensure dracut exists (Debian sometimes omits it)
if ! command -v dracut >/dev/null 2>&1; then
    sudo apt-get install -y dracut 2>&1 | tee -a "$PKG_LOG" || true
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
