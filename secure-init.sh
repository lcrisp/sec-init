#!/usr/bin/env bash
# secure-init.sh — main orchestrator for modular YubiKey/FIDO2 hardening framework
# Run as your normal user; all privileged operations occur inside modules via sudo.
# --------------------------------------------------------------

set -euo pipefail

# --- Setup logging directory ---
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="$HOME/secure-init"
mkdir -p "$LOG_DIR"
LOGFILE="$LOG_DIR/secure-init.log"

exec > >(tee -a "$LOGFILE") 2>&1

say(){
    echo -e "\n[ $(date '+%F %T') ] $*"
}

ERR(){
    echo -e "\n[ERROR] $*"
    exit 1
}

say "Starting secure-init orchestrator"
say "Modules directory: $BASE_DIR/modules"


# --- Preflight sanity checks ---
[[ -d "$BASE_DIR/modules" ]] || ERR "modules/ directory missing."

command -v sudo >/dev/null || ERR "sudo is required."
sudo -v || ERR "User is not in sudoers or sudo not available."


# --- Discover modules ---
MODULES=()

# numeric modules first
while IFS= read -r -d '' f; do
    MODULES+=("$f")
done < <(find "$BASE_DIR/modules" -maxdepth 1 -type f -name '[0-9][0-9]_*.sh' -print0 | sort -z)

# finish.sh always runs last
if [[ -f "$BASE_DIR/modules/finish.sh" ]]; then
    MODULES+=("$BASE_DIR/modules/finish.sh")
fi

say "Modules discovered in execution order:"
for m in "${MODULES[@]}"; do
    echo "  → $(basename "$m")"
done


# --- Export safe environment for modules ---
export LOG_DIR LOGFILE BASE_DIR


# --- Execute modules in order ---
for module in "${MODULES[@]}"; do
    say "Running module: $(basename "$module")"
    # shellcheck disable=SC1090
    source "$module"
    say "Completed module: $(basename "$module")"
done

say "secure-init complete."
