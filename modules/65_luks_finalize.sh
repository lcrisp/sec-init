#!/usr/bin/env bash
# Module: 65_luks_finalize.sh
# Purpose: Verify FIDO2 enrollment, back up the LUKS2 header, and remove legacy unlock paths.

set -euo pipefail
say(){ echo -e "\n[ $(date '+%F %T') ] $*"; }
need(){ command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1"; exit 1; }; }

say "[65] Verifying FIDO2 tokens + backing up LUKS header"

need cryptsetup
need python3

read -rp "Enter the primary LUKS block device (e.g., /dev/sda3): " LUKS_DEV
[[ -b "$LUKS_DEV" ]] || { say "[65] ERROR: $LUKS_DEV is not a block device"; exit 1; }

LOG_ROOT="${LOG_DIR:-$HOME/.logs/secure-init}"
mkdir -p "$LOG_ROOT"
STAMP="$(date '+%F-%H%M%S')"
DUMP_LOG="$LOG_ROOT/$(basename "$LUKS_DEV")-luksDump-$STAMP.txt"

say "[65] Capturing cryptsetup luksDump output -> $DUMP_LOG"
sudo cryptsetup luksDump "$LUKS_DEV" | tee "$DUMP_LOG"

PARSE_OUTPUT="$(
python3 - "$DUMP_LOG" <<'PY'
import re, sys
path = sys.argv[1]
tokens = []
all_slots = []
current = None

with open(path, encoding='utf-8', errors='ignore') as fh:
    for raw in fh:
        line = raw.strip()
        if re.match(r'^Keyslot\s+\d+:', line):
            slot = int(re.findall(r'\d+', line.split(':', 1)[0])[0])
            if slot not in all_slots:
                all_slots.append(slot)
        if re.match(r'^Token\s+\d+:', line, flags=re.IGNORECASE):
            if current and current.get('type') and current.get('slot') is not None:
                tokens.append(current)
            current = {'slot': None, 'type': None}
            # Handle inline "Token N: TYPE" format
            parts = line.split(':', 1)
            if len(parts) == 2:
                maybe = parts[1].strip()
                if maybe:
                    current['type'] = maybe
            continue
        if current is None:
            continue
        if line.lower().startswith('keyslot:'):
            value = line.split(':', 1)[1].strip()
            if value.isdigit():
                current['slot'] = int(value)
        elif line.lower().startswith('type:'):
            current['type'] = line.split(':', 1)[1].strip()
        elif not line:
            if current.get('type') and current.get('slot') is not None:
                tokens.append(current)
            current = None

if current and current.get('type') and current.get('slot') is not None:
    tokens.append(current)

fido_slots = []
fido_count = 0
for token in tokens:
    token_type = str(token.get('type', '')).lower()
    if 'fido2' in token_type:
        fido_count += 1
        fido_slots.append(int(token['slot']))

if fido_count < 2:
    sys.stderr.write(f"[65] ERROR: Expected at least 2 FIDO2 tokens but found {fido_count}\n")
    sys.exit(1)

unique_slots = ','.join(str(s) for s in all_slots)
unique_fido = ','.join(str(s) for s in sorted(set(fido_slots)))

print(f"FIDO_COUNT={fido_count}")
print(f"FIDO_SLOTS={unique_fido}")
print(f"ALL_SLOTS={unique_slots}")
PY
)"

PARSE_STATUS=$?

if [[ -z "$PARSE_OUTPUT" ]]; then
    say "[65] ERROR: Failed to parse luksDump output; see $DUMP_LOG"
    exit 1
fi

if (( PARSE_STATUS != 0 )); then
    say "[65] Token verification failed; review $DUMP_LOG and ensure two FIDO2 tokens exist."
    exit 1
fi

FIDO_COUNT="$(grep -oE 'FIDO_COUNT=[0-9]+' <<<"$PARSE_OUTPUT" | head -n1 | cut -d'=' -f2)"
FIDO_SLOTS_STR="$(grep -oE 'FIDO_SLOTS=.*' <<<"$PARSE_OUTPUT" | head -n1 | cut -d'=' -f2-)"
ALL_SLOTS_STR="$(grep -oE 'ALL_SLOTS=.*' <<<"$PARSE_OUTPUT" | head -n1 | cut -d'=' -f2-)"

say "[65] Detected $FIDO_COUNT FIDO2 token definitions mapped to slots: ${FIDO_SLOTS_STR:-none}"

IFS=',' read -r -a FIDO_SLOTS <<<"${FIDO_SLOTS_STR:-}"
IFS=',' read -r -a ALL_SLOTS <<<"${ALL_SLOTS_STR:-}"

# --- Backup header ---
BACKUP_DIR="$HOME/luks_h_backup"
mkdir -p "$BACKUP_DIR"
BACKUP_FILE="$BACKUP_DIR/$(basename "$LUKS_DEV")-$STAMP.luksheader"

say "[65] Backing up LUKS header -> $BACKUP_FILE"
sudo cryptsetup luksHeaderBackup "$LUKS_DEV" --header-backup-file "$BACKUP_FILE"
sudo chown "$USER":"$USER" "$BACKUP_FILE" 2>/dev/null || true
say "[65] Header backup saved. Copy $BACKUP_FILE to offline/external storage immediately."

# --- Remove non-FIDO keyslots ---
declare -A KEEP_SLOTS=()
for slot in "${FIDO_SLOTS[@]}"; do
    [[ -n "$slot" ]] && KEEP_SLOTS["$slot"]=1
done

TO_WIPE=()
for slot in "${ALL_SLOTS[@]}"; do
    [[ -z "$slot" ]] && continue
    if [[ -z "${KEEP_SLOTS[$slot]:-}" ]]; then
        TO_WIPE+=("$slot")
    fi
done

if [[ "${#TO_WIPE[@]}" -eq 0 ]]; then
    say "[65] No legacy keyslots detected — nothing to remove."
else
    say "[65] Candidate legacy keyslots: ${TO_WIPE[*]}"
    read -rp "Remove these alternate unlock paths now? [y/N]: " wipe_ans
    case "${wipe_ans,,}" in
        y|yes)
            for slot in "${TO_WIPE[@]}"; do
                say "  → Wiping keyslot $slot"
                sudo cryptsetup luksKillSlot "$LUKS_DEV" "$slot"
            done
            say "[65] Legacy keyslots removed."
            ;;
        *)
            say "[65] Skipped keyslot removal per user request."
            ;;
    esac
fi

say "[65] LUKS verification + lockdown complete."
