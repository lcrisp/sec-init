#!/usr/bin/env bash
# Module: 15_integrity.sh
# Purpose: Post-package security automation (debsums baseline, fail2ban setup, clamav update + scan)

set -euo pipefail
say(){ echo -e "\n[ $(date '+%F %T') ] $*"; }

LOG_ROOT="${LOG_DIR:-$HOME/secure-init}"
mkdir -p "$LOG_ROOT"
DEBSUMS_LOG="$LOG_ROOT/debsums-baseline.log"
CLAMAV_LOG="$LOG_ROOT/clamav-scan.log"

say "[15] Running post-install security automations"

# ---- debsums baseline -----------------------------------------------------
if command -v debsums >/dev/null 2>&1; then
    say "[15] Running debsums baseline (output -> $DEBSUMS_LOG)"
    if sudo debsums -a >"$DEBSUMS_LOG" 2>&1; then
        say "[15] debsums completed — see $DEBSUMS_LOG for details"
    else
        say "[15] WARNING: debsums reported issues (see $DEBSUMS_LOG)"
    fi
else
    say "[15] debsums not installed; skipping baseline scan"
fi

# ---- fail2ban configuration -----------------------------------------------
if command -v fail2ban-client >/dev/null 2>&1; then
    F2B_JAIL="/etc/fail2ban/jail.d/secure-init-sshd.local"
    say "[15] Configuring fail2ban ($F2B_JAIL)"
    sudo mkdir -p /etc/fail2ban/jail.d
    sudo tee "$F2B_JAIL" >/dev/null <<'EOF'
[sshd]
enabled = true
maxretry = 5
bantime = 1h
findtime = 10m
EOF
    sudo systemctl enable --now fail2ban
    sudo fail2ban-client reload || sudo systemctl restart fail2ban
    say "[15] fail2ban enabled and sshd jail active"
else
    say "[15] fail2ban not installed; skipping configuration"
fi

# ---- clamav update + scan -------------------------------------------------
if command -v clamscan >/dev/null 2>&1; then
    say "[15] Updating ClamAV definitions"
    sudo systemctl enable --now clamav-freshclam >/dev/null 2>&1 || sudo freshclam || true

    say "[15] Running ClamAV scan of /home (log -> $CLAMAV_LOG)"
    if sudo clamscan -r --infected --log="$CLAMAV_LOG" /home; then
        say "[15] ClamAV scan finished with no infections (see $CLAMAV_LOG)"
    else
        say "[15] WARNING: ClamAV reported findings (see $CLAMAV_LOG)"
    fi
else
    say "[15] clamscan not installed; skipping AV scan"
fi

say "[15] Security automation module complete"
