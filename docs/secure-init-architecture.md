# secure-init System Architecture
## Technical Overview & Maintenance Guide

(Modified: sudo-hardening and finish logic combined into a single final module.)

## 0. Purpose
This repository implements a modular, reproducible bootstrap for Debian/Ubuntu systems using:
- YubiKey FIDO2
- PAM U2F authentication
- systemd-cryptenroll FIDO2 unlocking
- SSH resident FIDO2 keys
- GRUB password hardening
- udev, sudo, crypttab, initramfs, ufw tightening

The document explains how the system works so it can be safely maintained even if all chat history is lost.

## 1. Execution Model
`secure-init.sh`:
1. Logs all actions.
2. Discovers modules under `modules/`.
3. Executes them in ascending numeric order.
4. Executes the combined final module (`90_final.sh`) last.
5. Exports shared variables.
6. Stops immediately on any error.

## 2. Directory Structure
```
secure-init/
├── secure-init.sh
├── modules/
│     ├── 00_preflight.sh
│     ├── 10_packages.sh
│     ├── 20_udev.sh
│     ├── 30_enrol.sh
│     ├── 40_pam.sh
│     ├── 50_crypttab.sh
│     ├── 60_initramfs.sh
│     ├── 70_grub.sh
│     └── 90_final.sh   ← sudo-hardening + reboot handling
└── packages.list
```

Numbered modules run in order; `90_final.sh` is always the last step.

## 3. Why Modules Are `sourced`
Modules are sourced so they share:
- Logging
- Error handling
- Environment variables
- State between modules

If executed in a subshell, information like enrolled key paths would not propagate.

## 4. Privilege Model
`secure-init.sh` **runs unprivileged**.

Modules use:
```
sudo <cmd>
```
only when needed. This ensures:
- YubiKey enrollment does not create root-owned files.
- SSH resident keys remain under `$HOME`.
- PAM and udev resources install atomically and safely.

Running the whole script under sudo would break enrollment and risk account lockout.

## 5. Module Responsibilities

### 00_preflight.sh
Validates:
- sudo availability
- required binaries
- correct user (non-root)
Creates environment and log file.

### 10_packages.sh
Installs:
- ufw
- libpam-u2f
- systemd-cryptsetup
- openssh
- dracut (optional)

Idempotent.

### 20_udev.sh
Configures:
- YubiKey access rules
- plugdev group
- hidraw permissions

Ensures correct device ownership before enrollment.

### 15_services.sh
Consumes:
- `lists/serv-dsbl.list` → units to `systemctl disable --now`
- `lists/serv-mask.list` → units to `systemctl mask --now`

Blank/default files live under `lists/` so operators can opt-in by adding units line-by-line.

### 25_keyring.sh
Configures:
- user-level overrides for GNOME Keyring autostart
- masks `gnome-keyring-daemon` user units to suppress password prompts

Prevents desktop prompts that would otherwise appear when skipping UNIX passwords.

### 30_enrol.sh
Handles:
- pamu2fcfg for both YubiKeys
- ssh-keygen -K for resident keys
- authorized_keys population
- systemd-cryptenroll for both keys

Must run as the normal user.

### 40_pam.sh
Enforces:
```
auth sufficient pam_u2f.so authfile=/etc/Yubico/u2f_keys cue
auth required   pam_deny.so
```
Inserted at the very top of:
- /etc/pam.d/common-auth
- /etc/pam.d/other

`pam_deny.so` must immediately follow pam_u2f.so.

### 50_crypttab.sh
Writes:
```
cryptroot UUID=<uuid> none luks,fido2-device=auto
```

Must precede initramfs rebuild.

### 60_initramfs.sh
Handles:
- dracut or initramfs-tools hooks
- fido2 + hid + usbhid inclusion
- rebuilds initramfs safely

### 65_luks_finalize.sh
Handles:
- `cryptsetup luksDump` verification (requires two FIDO2 tokens)
- header backups to `~/luks_h_backup`
- optional removal of any legacy/non-FIDO keyslots

Only runs after enrollment + initramfs rebuild so the volume can be safely locked down.

### 70_grub.sh
- interactive password hashing
- writes 40_custom
- disables recovery entries
- updates GRUB safely

### 90_final.sh  (combined sudo hardening + reboot sequence)
Does two things:

#### 1. Installs sudo hardening:
```
Defaults timestamp_timeout=0
auth sufficient pam_u2f.so authfile=/etc/Yubico/u2f_keys cue
auth required   pam_deny.so
```
Installed via atomic sudoers.d file with visudo validation.

#### 2. Handles the final reboot
- Provides 10-second countdown
- User may cancel by pressing Enter
- Avoids sudo (timestamp likely expired)

This module **must always run last**.

## 6. Logging
All logs go to:
```
~/.logs/secure-init/secure-init.log
```
Never contains sensitive outputs.

## 7. Adding New Modules
Drop a file into `modules/`:
```
modules/25_firewall.sh
```
Rules:
- must be idempotent
- must not modify PAM, crypttab, GRUB unless explicitly intended
- must use `say` for logging
- must not require being run as root

## 8. Debugging
1. View logs:
```
cat ~/.logs/secure-init/secure-init.log
```
2. Re-run the entire script (safe—modules are idempotent).
3. Run a single module:
```
source modules/40_pam.sh
```

## 9. Full Rebuild Workflow
1. Install Debian/Ubuntu.
2. Clone repo.
3. Run:
```
./secure-init.sh
```
4. Reboot.
5. System now uses:
   - FIDO2 LUKS unlock
   - PAM U2F-only login
   - SSH resident FIDO2 keys

## 10. Why This Document Exists
Written intentionally as a transfer-of-knowledge document for:
- future you
- future ChatGPT instances
- anyone maintaining the repo in the absence of session history

It ensures no part of the design is lost to time.
