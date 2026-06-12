#!/usr/bin/env bash
# cachyos-postinstall-check.sh: read-only health check for the CachyOS side of
# a dual-boot, run from inside CachyOS. It applies the inspection mindset of
# this runbook to an Arch based rolling system. It changes nothing. See
# chapter 9.
set -u

WARNINGS=()

section() { printf '\n== %s ==\n' "$1"; }
warn()    { WARNINGS+=("$1"); printf 'WARNING: %s\n' "$1"; }
info()    { printf '%s\n' "$1"; }
has()     { command -v "$1" >/dev/null 2>&1; }

if ! has pacman; then
  echo "pacman not found. This script is meant to run on CachyOS or another Arch based system."
  exit 0
fi

section "System basics"
grep -E "^PRETTY_NAME" /etc/os-release 2>/dev/null | cut -d'"' -f2
printf 'Kernel: %s | Uptime:%s\n' "$(uname -r)" "$(uptime -p 2>/dev/null | sed 's/up//')"

section "Pending updates"
if has checkupdates; then
  cnt=$(checkupdates 2>/dev/null | wc -l)
  info "Repo updates pending: $cnt"
else
  info "checkupdates not found. Install pacman-contrib for a non-destructive count."
fi
if has paru; then
  aur=$(paru -Qua 2>/dev/null | wc -l)
  info "AUR updates pending: $aur"
fi
info "Rule: never partial upgrade. Always 'sudo pacman -Syu', never 'pacman -Sy <pkg>'."

section "Keyrings"
info "After a long gap, refresh first: sudo pacman -Sy archlinux-keyring cachyos-keyring"

section "Orphan packages"
orph=$(pacman -Qtdq 2>/dev/null | wc -l)
info "Orphans (unused dependencies): $orph"
[ "$orph" -gt 0 ] && info "Remove with: sudo pacman -Rns \$(pacman -Qtdq)"

section "Kernels and fallback"
pacman -Q 2>/dev/null | grep -E '^linux( |-cachyos|-lts|-zen|-hardened)' | sed 's/^/  /'
if pacman -Q linux-lts >/dev/null 2>&1; then
  info "linux-lts present. Good parachute against a bad rolling kernel."
else
  warn "No linux-lts fallback kernel installed. Install one: sudo pacman -S linux-lts"
fi
ls /boot/vmlinuz-* 2>/dev/null | sed 's/^/  /'

section "Filesystem and snapshots"
rootfs=$(findmnt -no FSTYPE / 2>/dev/null)
info "Root filesystem: ${rootfs:-unknown}"
if [ "$rootfs" = "btrfs" ]; then
  if has snapper; then
    info "snapper present. Snapshot configs need root: sudo snapper list-configs"
  else
    warn "Root is btrfs but snapper is not installed. Set up snapshots before upgrading."
  fi
  for u in limine-snapper-sync grub-btrfs snapper-timeline.timer snapper-cleanup.timer; do
    s=$(systemctl is-active "$u" 2>/dev/null || true)
    [ "$s" = "active" ] && info "  $u: active"
  done
else
  warn "Root is not btrfs. Bootable snapshots are unavailable. Rolling upgrades carry more risk."
fi

section "ESP space"
for m in /boot/efi /efi /boot; do
  if findmnt -no FSTYPE "$m" 2>/dev/null | grep -qi vfat; then
    df -h "$m" 2>/dev/null | awk 'NR==2{print "  "$6": "$4" free of "$2}'
    free=$(df -m "$m" 2>/dev/null | awk 'NR==2{print $4}')
    [ -n "${free:-}" ] && [ "$free" -lt 100 ] && warn "ESP at $m below 100 MB free. Prune old kernels."
    break
  fi
done

section "Real time clock"
if has timedatectl; then
  rtc=$(timedatectl 2>/dev/null | grep -i "RTC in local")
  info "${rtc:-unknown}"
  echo "$rtc" | grep -qi "yes" && warn "RTC in local time. Set UTC on every dual-boot system: sudo timedatectl set-local-rtc 0"
fi

section "Mirrors"
info "Re-rank optimized mirrors after install or when sync is slow: sudo cachyos-rate-mirrors"

section "systemd state"
state=$(systemctl is-system-running 2>/dev/null || true)
info "is-system-running: $state"
[ "$state" = "running" ] || warn "System state is '$state' instead of 'running'"
failed=$(systemctl --failed --no-legend 2>/dev/null | wc -l)
ufailed=$(systemctl --user --failed --no-legend 2>/dev/null | wc -l)
info "Failed units: system=$failed user=$ufailed"
[ "$((failed+ufailed))" -gt 0 ] && warn "Failed units present (systemctl --failed)"

section "Package cache"
du -sh /var/cache/pacman/pkg 2>/dev/null | awk '{print "pacman cache: "$1}'
info "Trim with paccache -r (keeps the last 3 versions)."

section "SUMMARY"
if [ "${#WARNINGS[@]}" -eq 0 ]; then
  info "No warnings. Still verify both systems boot and share the UTC clock convention."
else
  n=${#WARNINGS[@]}; [ "$n" -eq 1 ] && noun=warning || noun=warnings
  printf '%d %s:\n' "$n" "$noun"
  for w in "${WARNINGS[@]}"; do printf ' - %s\n' "$w"; done
fi
