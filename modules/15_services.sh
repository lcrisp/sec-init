#!/usr/bin/env bash
# Module: 15_services.sh
# Purpose: Disable or mask unwanted systemd units declared in lists/serv-dsbl.list and lists/serv-mask.list

set -euo pipefail
say(){ echo -e "\n[ $(date '+%F %T') ] $*"; }
need(){ command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1"; exit 1; }; }

say "[15] Service disable/mask module starting"

need systemctl

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${BASE_DIR:-$(dirname "$SCRIPT_DIR")}"
LIST_ROOT="${LISTDIR:-$ROOT_DIR/lists}"

DSBL_FILE="$LIST_ROOT/serv-dsbl.list"
MASK_FILE="$LIST_ROOT/serv-mask.list"

trim_list(){
    local file="$1"
    [[ -f "$file" ]] || return 1
    awk '{
        sub(/^[ \t]+/, "", $0);
        sub(/[ \t]+$/, "", $0);
        if ($0 == "" || $0 ~ /^#/) next;
        print $0
    }' "$file"
}

process_units(){
    local mode="$1" file="$2"
    local label action units

    case "$mode" in
        disable) label="disable"; action="sudo systemctl disable --now" ;;
        mask) label="mask"; action="sudo systemctl mask --now" ;;
        *) say "[15] ERROR: Unsupported mode $mode"; return 1 ;;
    esac

    if [[ ! -f "$file" ]]; then
        say "[15] No $label list found ($file); skipping"
        return 0
    fi

    mapfile -t units < <(trim_list "$file") || units=()

    if [[ ${#units[@]} -eq 0 ]]; then
        say "[15] $file is empty; nothing to $label"
        return 0
    fi

    for unit in "${units[@]}"; do
        if $action "$unit"; then
            say "[15] ${label^}d $unit"
        else
            say "[15] WARNING: Failed to $label $unit (does it exist?)"
        fi
    done
}

process_units disable "$DSBL_FILE"
process_units mask "$MASK_FILE"

say "[15] Service disable/mask module complete"
