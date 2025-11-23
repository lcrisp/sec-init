#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="/var/log/displaylink-install.log"
MOK_DIR="/var/lib/shim-signed/mok"
MOK_KEY="${MOK_DIR}/displaylink_mok.key"
MOK_CRT="${MOK_DIR}/displaylink_mok.crt"
MOK_CN="DisplayLink-MOK"
EVDI_MODULE="evdi"
KVER="$(uname -r)"

log() {
    echo "[*] $*" | tee -a "$LOG_FILE"
}

err() {
    echo "[!] $*" | tee -a "$LOG_FILE" >&2
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        err "This script must be run as root. Try: sudo $0"
        exit 1
    fi
}

detect_distro() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        DISTRO_ID="${ID:-unknown}"
        DISTRO_LIKE="${ID_LIKE:-}"
    else
        DISTRO_ID="unknown"
        DISTRO_LIKE=""
    fi

    log "Detected distro: ID=${DISTRO_ID}, ID_LIKE=${DISTRO_LIKE}"
}

ensure_apt_based() {
    if ! command -v apt-get >/dev/null 2>&1; then
        err "This script only supports Debian/Ubuntu (apt-based) systems."
        exit 1
    fi
}

check_secure_boot_state() {
    if ! command -v mokutil >/dev/null 2>&1; then
        log "mokutil not found. Installing shim-signed + mokutil…"
        apt-get update >>"$LOG_FILE" 2>&1
        apt-get install -y mokutil shim-signed >>"$LOG_FILE" 2>&1 || {
            err "Failed to install mokutil / shim-signed."
            exit 1
        }
    fi

    if mokutil --sb-state 2>/dev/null | grep -qi "SecureBoot enabled"; then
        SECURE_BOOT_ENABLED=1
        log "Secure Boot appears to be ENABLED."
    else
        SECURE_BOOT_ENABLED=0
        log "Secure Boot appears to be DISABLED."
    fi
}

install_dependencies() {
    log "Installing general build dependencies and DKMS tooling…"
    apt-get update >>"$LOG_FILE" 2>&1
    apt-get install -y \
        build-essential \
        dkms \
        linux-headers-"${KVER}" \
        openssl \
        ca-certificates \
        wget \
        >>"$LOG_FILE" 2>&1 || {
            err "Failed to install required packages."
            exit 1
        }

    log "Dependencies installed."
}

prompt_displaylink_run() {
    echo
    log "You need the official DisplayLink .run installer (e.g. displaylink-driver-*.run)."
    log "Download it from: https://www.synaptics.com/products/displaylink-graphics/downloads"
    echo
    read -r -p "Full path to the DisplayLink .run file: " DISPLAYLINK_RUN

    if [[ ! -f "$DISPLAYLINK_RUN" ]]; then
        err "File not found: $DISPLAYLINK_RUN"
        exit 1
    fi

    chmod +x "$DISPLAYLINK_RUN"
    log "Using DisplayLink installer: $DISPLAYLINK_RUN"
}

install_displaylink() {
    log "Running DisplayLink installer…"
    # DisplayLink installer is interactive by default. We force silent mode if supported.
    # Many recent versions support: --silent
    if "$DISPLAYLINK_RUN" --help 2>&1 | grep -q -- "--silent"; then
        "$DISPLAYLINK_RUN" --silent >>"$LOG_FILE" 2>&1 || {
            err "DisplayLink installer failed in silent mode."
            exit 1
        }
    else
        log "Installer does not support --silent; running interactively in a subshell."
        bash "$DISPLAYLINK_RUN" | tee -a "$LOG_FILE"
    fi
    log "DisplayLink installer completed."
}

ensure_evdi_dkms_exists() {
    if dkms status | grep -q "^${EVDI_MODULE}/"; then
        log "EVDI DKMS module already registered:"
        dkms status | grep "^${EVDI_MODULE}/" | tee -a "$LOG_FILE"
    else
        log "EVDI DKMS module not found in dkms status."
        log "If DisplayLink did not install evdi as a DKMS module, this script will fail later."
        log "Continuing anyway; we will check again after DisplayLink installation."
    fi
}

find_evdi_dkms_version() {
    # After DisplayLink install, evdi should show up in dkms status
    local evdi_line
    evdi_line="$(dkms status | grep "^${EVDI_MODULE}/" || true)"

    if [[ -z "$evdi_line" ]]; then
        err "EVDI DKMS module not found in 'dkms status' after DisplayLink install."
        err "You may need to install EVDI manually (e.g., from https://github.com/DisplayLink/evdi)."
        exit 1
    fi

    # Format: evdi/<version>, <kernel>: <state>
    EVDI_VERSION="${evdi_line%%,*}"
    EVDI_VERSION="${EVDI_VERSION#${EVDI_MODULE}/}"

    log "Detected EVDI DKMS version: ${EVDI_VERSION}"
}

build_evdi_for_kernel() {
    log "Building EVDI DKMS module for kernel ${KVER}…"
    dkms build -m "${EVDI_MODULE}" -v "${EVDI_VERSION}" -k "${KVER}" >>"$LOG_FILE" 2>&1 || {
        err "dkms build failed for EVDI ${EVDI_VERSION} on ${KVER}"
        exit 1
    }
    dkms install -m "${EVDI_MODULE}" -v "${EVDI_VERSION}" -k "${KVER}" --force >>"$LOG_FILE" 2>&1 || {
        err "dkms install failed for EVDI ${EVDI_VERSION} on ${KVER}"
        exit 1
    }
    log "EVDI DKMS module built and installed for ${KVER}."
}

ensure_mok_dir() {
    if [[ ! -d "$MOK_DIR" ]]; then
        mkdir -p "$MOK_DIR"
        chmod 700 "$MOK_DIR"
    fi
}

generate_mok_key_if_needed() {
    ensure_mok_dir

    if [[ -f "$MOK_KEY" && -f "$MOK_CRT" ]]; then
        log "Existing MOK key and cert found:"
        log "  KEY: $MOK_KEY"
        log "  CRT: $MOK_CRT"
        return
    fi

    log "Generating new Secure Boot MOK keypair for DisplayLink/EVDI signing…"
    openssl req -new -x509 -newkey rsa:2048 -keyout "$MOK_KEY" -out "$MOK_CRT" \
        -nodes -days 3650 -subj "/CN=${MOK_CN}/" >>"$LOG_FILE" 2>&1 || {
            err "Failed to generate MOK keypair."
            exit 1
        }

    chmod 600 "$MOK_KEY" "$MOK_CRT"
    log "MOK keypair generated:"
    log "  KEY: $MOK_KEY"
    log "  CRT: $MOK_CRT"
}

sign_evdi_module() {
    local modpath
    modpath="$(modinfo -n "${EVDI_MODULE}" 2>/dev/null || true)"

    if [[ -z "$modpath" || ! -f "$modpath" ]]; then
        err "Could not locate ${EVDI_MODULE}.ko on disk (modinfo returned: '$modpath')."
        exit 1
    fi

    log "Found EVDI module at: $modpath"

    if ! command -v kmodsign >/dev/null 2>&1; then
        log "kmodsign not found; installing linux-signing-tools if available…"
        apt-get install -y linux-signing-tools-"${KVER%%-*}" >>"$LOG_FILE" 2>&1 || true
        # fallback: some distros package kmodsign differently; check again
        if ! command -v kmodsign >/dev/null 2>&1; then
            err "kmodsign not found and could not be installed. Cannot sign kernel modules."
            exit 1
        fi
    fi

    log "Signing EVDI module with MOK key…"
    kmodsign sha256 "$MOK_KEY" "$MOK_CRT" "$modpath" >>"$LOG_FILE" 2>&1 || {
        err "Failed to sign EVDI module."
        exit 1
    }

    log "EVDI module signed successfully."
}

enroll_mok_key() {
    if [[ "$SECURE_BOOT_ENABLED" -ne 1 ]]; then
        log "Secure Boot is DISABLED; MOK enrollment is technically not required."
        log "You can still enroll the key now if you plan to re-enable Secure Boot later."
    fi

    log "Enrolling MOK key with shim/MOK via mokutil…"
    log "You will be prompted to set a password, then you MUST reboot and complete enrollment in the blue MOK manager screen."

    mokutil --import "$MOK_CRT" || {
        err "mokutil --import failed."
        exit 1
    }

    log "MOK import requested. A reboot is required to complete key enrollment."
}

reload_evdi_module() {
    log "Reloading EVDI module…"
    if lsmod | grep -q "^${EVDI_MODULE}"; then
        rmmod "${EVDI_MODULE}" || true
    fi
    modprobe "${EVDI_MODULE}" || {
        err "Failed to load EVDI module."
        exit 1
    }
    log "EVDI module loaded successfully."
}

main() {
    require_root
    detect_distro
    ensure_apt_based
    check_secure_boot_state
    install_dependencies
    ensure_evdi_dkms_exists
    prompt_displaylink_run
    install_displaylink
    find_evdi_dkms_version
    build_evdi_for_kernel
    generate_mok_key_if_needed
    sign_evdi_module
    enroll_mok_key
    reload_evdi_module

    echo
    log "====================================================================="
    log "DisplayLink + EVDI installation and Secure Boot signing completed."
    log
    log "NEXT STEPS:"
    log "  1) Reboot this machine."
    log "  2) In the blue MOK Manager screen, choose 'Enroll MOK',"
    log "     select the new key, and enter the password you set."
    log "  3) After boot, verify with:"
    log "       mokutil --list-enrolled | grep '${MOK_CN}'"
    log "       modinfo ${EVDI_MODULE}"
    log "====================================================================="
}

main "$@"
