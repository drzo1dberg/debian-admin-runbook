#!/usr/bin/env bash
# dualboot-preflight.sh: read-only readiness check before adding a second
# distribution (e.g. CachyOS) alongside an existing one. Run it on the
# installed system. It changes nothing. Where root is required it prints a
# hint instead of running the command. See chapter 9.
set -u

WARNINGS=()

section() { printf '\n== %s ==\n' "$1"; }
warn()    { WARNINGS+=("$1"); printf 'WARNING: %s\n' "$1"; }
info()    { printf '%s\n' "$1"; }
has()     { command -v "$1" >/dev/null 2>&1; }

section "Firmware mode"
if [ -d /sys/firmware/efi ]; then
  info "UEFI firmware detected. Good basis for a GPT dual-boot."
else
  warn "Legacy BIOS boot. A UEFI plus GPT setup is strongly preferred."
fi

section "Secure Boot"
if has mokutil; then
  state=$(mokutil --sb-state 2>/dev/null)
  info "${state:-unknown}"
  echo "$state" | grep -qi "enabled" && warn "Secure Boot is enabled. CachyOS kernels are unsigned by default. Plan to disable it or sign with sbctl."
else
  info "mokutil not found. Check Secure Boot in firmware setup instead."
fi

section "EFI System Partition"
esp=""
for m in /boot/efi /efi /boot; do
  if findmnt -no FSTYPE "$m" 2>/dev/null | grep -qi vfat; then esp="$m"; break; fi
done
if [ -n "$esp" ]; then
  findmnt -no SOURCE,FSTYPE,SIZE,TARGET "$esp" 2>/dev/null
  free=$(df -m "$esp" 2>/dev/null | awk 'NR==2{print $4}')
  info "Free space on ESP: ${free:-?} MB"
  [ -n "${free:-}" ] && [ "$free" -lt 200 ] && warn "Less than 200 MB free on the ESP. Tight for two systems worth of kernels."
  info "Existing boot entries:"
  ls "$esp/EFI" 2>/dev/null | sed 's/^/  /'
else
  warn "No mounted vfat ESP found. A UEFI dual-boot needs one shared ESP."
fi

section "Disk layout"
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT 2>/dev/null | head -20
info "Partition table type and free gaps need root: sudo parted -l"
info "Confirm the table is GPT before installing a UEFI second system."

section "Current bootloader and boot order"
if has bootctl && bootctl status >/dev/null 2>&1; then
  bootctl status 2>/dev/null | grep -iE "product|systemd-boot|installed" | head -3
fi
[ -d /boot/grub ] && info "GRUB present (/boot/grub exists)."
if has efibootmgr; then
  efibootmgr 2>/dev/null | grep -E "BootOrder|Boot[0-9]" | head -12
  info "After the second install, keep exactly one bootloader first in BootOrder."
else
  info "efibootmgr not installed. Boot order needs it: sudo efibootmgr -v"
fi

section "Real time clock convention"
if has timedatectl; then
  rtc=$(timedatectl 2>/dev/null | grep -i "RTC in local")
  info "${rtc:-unknown}"
  echo "$rtc" | grep -qi "yes" && warn "RTC is in local time. Set both systems to UTC: sudo timedatectl set-local-rtc 0"
else
  warn "timedatectl not found. Cannot verify the clock convention."
fi

section "Backup gate"
warn "Repartitioning is destructive. Do not proceed without a current backup and a passed restore test (chapter 6)."

section "SUMMARY"
if [ "${#WARNINGS[@]}" -eq 0 ]; then
  info "No blockers found. Still verify the partition table is GPT and a backup exists."
else
  n=${#WARNINGS[@]}; [ "$n" -eq 1 ] && noun=item || noun=items
  printf '%d %s to resolve before install:\n' "$n" "$noun"
  for w in "${WARNINGS[@]}"; do printf ' - %s\n' "$w"; done
fi
