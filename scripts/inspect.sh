#!/usr/bin/env bash
# inspect.sh: read-only quick inspection of a Debian system.
# Runs as a regular user and changes nothing. Where root would be
# required, it prints a hint instead of running the command.
set -u

WARNINGS=()

section() { printf '\n== %s ==\n' "$1"; }
warn()    { WARNINGS+=("$1"); printf 'WARNING: %s\n' "$1"; }
info()    { printf '%s\n' "$1"; }
has()     { command -v "$1" >/dev/null 2>&1; }

section "System basics"
grep -E "^PRETTY_NAME" /etc/os-release | cut -d'"' -f2
printf 'Kernel: %s | Uptime:%s\n' "$(uname -r)" "$(uptime -p 2>/dev/null | sed 's/up//')"
[ -f /var/run/reboot-required ] && warn "Reboot pending (/var/run/reboot-required exists)"

section "Time synchronization"
if has timedatectl; then
  timedatectl | grep -E "synchronized|NTP service" | sed 's/^ *//'
  timedatectl | grep -q "synchronized: yes" || warn "System clock is NOT synchronized"
else
  warn "timedatectl not found"
fi

section "Updates"
cnt=$(apt list --upgradable 2>/dev/null | grep -c upgradable || true)
sec=$(apt list --upgradable 2>/dev/null | grep -c security || true)
info "Upgradable packages: $cnt (security: $sec)"
info "Note: numbers are only as fresh as the last 'apt update' run."
[ "$sec" -gt 0 ] && warn "$sec security updates pending"
if dpkg -l unattended-upgrades 2>/dev/null | grep -q ^ii; then
  info "unattended-upgrades: installed"
else
  warn "unattended-upgrades is not installed. Nothing patches itself."
fi

section "Zombie packages (no repo source)"
obs=$(apt list '?obsolete' 2>/dev/null | grep -cv "^Listing\|^Auflistung" || true)
info "Obsolete packages: $obs"
[ "$obs" -gt 10 ] && warn "$obs packages without a repo source. Check for release leftovers (chapter 1)."
apt list '?obsolete' 2>/dev/null | grep -v "^Listing\|^Auflistung" | cut -d/ -f1 | head -15

section "Third-party sources"
ls /etc/apt/sources.list.d/ 2>/dev/null
keys=$(ls /etc/apt/trusted.gpg.d/ 2>/dev/null | wc -l)
[ "$keys" -gt 0 ] && info "Note: $keys keys are globally trusted in trusted.gpg.d (prefer signed-by scoping)."

section "systemd state"
state=$(systemctl is-system-running 2>/dev/null || true)
info "is-system-running: $state"
[ "$state" = "running" ] || warn "System state is '$state' instead of 'running'"
failed=$(systemctl --failed --no-legend 2>/dev/null | wc -l)
ufailed=$(systemctl --user --failed --no-legend 2>/dev/null | wc -l)
info "Failed units: system=$failed user=$ufailed"
[ "$((failed+ufailed))" -gt 0 ] && warn "Failed units present (systemctl --failed)"

section "Journal errors (current boot)"
if journalctl -b -p err -q --no-pager >/dev/null 2>&1; then
  errs=$(journalctl -b -p err -q --no-pager 2>/dev/null | wc -l)
  info "Error messages since boot: $errs"
  [ "$errs" -gt 50 ] && warn "$errs journal errors since boot. Check for repetition patterns."
else
  info "System journal not readable. For full access join group systemd-journal (chapter 3)."
fi

section "Maintenance timers"
for t in apt-daily.timer apt-daily-upgrade.timer fstrim.timer logrotate.timer; do
  s=$(systemctl is-active "$t" 2>/dev/null || true)
  printf '%-26s %s\n' "$t" "$s"
  [ "$s" = "active" ] || warn "Timer $t is not active"
done

section "Open ports (excluding localhost)"
if has ss; then
  ss -tulnH 2>/dev/null | awk '{print $1, $5}' | grep -v "127.0.0.1\|\[::1\]" | sort -u | head -20
  info "Rule: every line must be explainable. Process names require 'sudo ss -tulnp'."
fi

section "Docker"
if has docker && docker info >/dev/null 2>&1; then
  docker ps -a --format '{{.Names}}\t{{.Status}}' | head -10
  if docker ps -a --format '{{.Status}}' | grep -qi restarting; then
    warn "Container stuck in a restart loop (docker ps -a)"
  fi
  docker system df 2>/dev/null
else
  info "Docker not installed or not reachable."
fi

section "Disk usage"
df -h 2>/dev/null | grep -vE "tmpfs|efivarfs" | head -8
full=$(df --output=pcent,target 2>/dev/null | grep -vE "tmpfs|Use|/boot/efi" | awk '$1+0 > 85 {print $2" ("$1")"}')
[ -n "$full" ] && warn "Above 85% full: $full"

section "Caches and corpses"
du -sh /var/cache/apt/archives 2>/dev/null | awk '{print "apt cache: "$1}'
du -xsh "$HOME/.cache" 2>/dev/null | awk '{print "~/.cache:  "$1}'
corpses=$(ls "$HOME" 2>/dev/null | grep -E "^core\.|^debug\.log$|\.deb$" || true)
if [ -n "$corpses" ]; then
  warn "Corpses found in the home root:"
  printf '  %s\n' $corpses
fi
old=$(find "$HOME/Downloads" -maxdepth 1 -type f -mtime +180 -size +50M 2>/dev/null | wc -l)
[ "$old" -gt 0 ] && info "Downloads: $old large files older than 6 months (deletion candidates)."

section "SSH"
if [ -d "$HOME/.ssh" ]; then
  mode=$(stat -c %a "$HOME/.ssh" 2>/dev/null)
  [ "$mode" = "700" ] || warn "~/.ssh has mode $mode instead of 700"
  ak=$(grep -c . "$HOME/.ssh/authorized_keys" 2>/dev/null || echo 0)
  info "authorized_keys entries: $ak (be able to explain every key)"
fi
if sudo -n sshd -T >/dev/null 2>&1; then
  sudo -n sshd -T | grep -i "^passwordauthentication"
else
  info "sshd config requires root: sudo sshd -T | grep -i passwordauth"
fi

section "File permissions on secrets"
hits=$(find "$HOME" -maxdepth 3 \( -iname "*key*" -o -iname "*secret*" -o -iname "*token*" \
  -o -iname "*.kdbx" -o -iname "*.keyx" \) -perm -o+r -not -path "*/.local/share/*" \
  -not -path "*/.cache/*" -type f 2>/dev/null | head -5)
if [ -n "$hits" ]; then
  warn "World-readable files with suspicious names:"
  printf '  %s\n' $hits
else
  info "No world-readable key candidates in the usual paths."
fi

section "Flatpak"
if has flatpak; then
  upd=$(flatpak remote-ls --updates 2>/dev/null | wc -l)
  info "Pending Flatpak updates: $upd"
  [ "$upd" -gt 10 ] && warn "$upd Flatpak updates pending"
fi

section "Backup reality"
timer=$(systemctl --user list-timers --no-legend 2>/dev/null | grep -i backup || true)
if [ -n "$timer" ]; then
  info "Backup timer found:"
  printf '  %s\n' "$timer"
else
  warn "No user backup timer found. Does an automated backup exist at all?"
fi
info "Disk health requires root: sudo smartctl -H -A /dev/<disk> (chapter 6)."

section "SUMMARY"
if [ "${#WARNINGS[@]}" -eq 0 ]; then
  info "No warnings. Still: this script is the quick check, not the inspection."
else
  printf '%d warnings:\n' "${#WARNINGS[@]}"
  for w in "${WARNINGS[@]}"; do printf ' - %s\n' "$w"; done
  info ""
  info "Next step: open the matching runbook chapter per warning."
fi
