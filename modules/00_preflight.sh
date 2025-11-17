#!/usr/bin/env bash
# 00_preflight.sh — baseline checks before running secure-init modules
# This file is intentionally small, strict, and self-contained.
# It should be sourced or executed first.

set -euo pipefail

say(){ echo -e "[PRE] $*"; }

# --- Step 1: verify sudo works (non-destructive)
say "Verifying sudo access..."
if ! sudo -v; then
    say "ERROR: sudo not available or no passwordless cache unlock" >&2
    exit 1
fi

# --- Step 2: check basic utilities
say "Checking required commands..."
REQ=(lsblk awk sed tee udevadm)
for c in "${REQ[@]}"; do
    if ! command -v "$c" >/dev/null 2>&1; then
        say "Missing: $c — please install before continuing" >&2
        exit 1
    fi
    say "ok: $c"
done

# --- Step 3: check for YubiKey presence (hidraw)
say "Detecting hidraw devices..."
HIDS=(/dev/hidraw*)
if [[ ${#HIDS[@]} -eq 0 ]]; then
    say "ERROR: No /dev/hidraw* devices found. Insert YubiKey and retry." >&2
    exit 1
fi

# --- Step 4: check plugdev membership
groups | grep -qw plugdev && HAS_PLUGDEV=1 || HAS_PLUGDEV=0

say "plugdev membership: $HAS_PLUGDEV"

# --- Step 5: confirm logging directory
LOGROOT="$HOME/secure-init"
mkdir -p "$LOGROOT"
LOGFILE="$LOGROOT/preflight.log"
exec > >(tee "$LOGFILE") 2>&1

say "Preflight complete"
