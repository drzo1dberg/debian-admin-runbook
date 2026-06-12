#!/usr/bin/env bash
# inspektion.sh: read-only Schnell-Inspektion eines Debian-Systems.
# Läuft als normaler User und verändert nichts. Wo Root nötig wäre,
# gibt das Skript einen Hinweis aus, statt den Befehl auszuführen.
set -u

WARNUNGEN=()

kopf()  { printf '\n== %s ==\n' "$1"; }
warn()  { WARNUNGEN+=("$1"); printf 'WARNUNG: %s\n' "$1"; }
info()  { printf '%s\n' "$1"; }
hat()   { command -v "$1" >/dev/null 2>&1; }

kopf "System-Basics"
grep -E "^PRETTY_NAME" /etc/os-release | cut -d'"' -f2
printf 'Kernel: %s | Uptime:%s\n' "$(uname -r)" "$(uptime -p 2>/dev/null | sed 's/up//')"
[ -f /var/run/reboot-required ] && warn "Reboot ausstehend (/var/run/reboot-required existiert)"

kopf "Zeitsynchronisation"
if hat timedatectl; then
  timedatectl | grep -E "synchronized|NTP service" | sed 's/^ *//'
  timedatectl | grep -q "synchronized: yes" || warn "Systemuhr ist NICHT synchronisiert"
else
  warn "timedatectl nicht gefunden"
fi

kopf "Updates"
anz=$(apt list --upgradable 2>/dev/null | grep -c upgradable || true)
sec=$(apt list --upgradable 2>/dev/null | grep -c security || true)
info "Aktualisierbare Pakete: $anz (davon Security: $sec)"
info "Hinweis: Zahlen sind nur so frisch wie der letzte 'apt update'-Lauf."
[ "$sec" -gt 0 ] && warn "$sec Security-Updates stehen aus"
if dpkg -l unattended-upgrades 2>/dev/null | grep -q ^ii; then
  info "unattended-upgrades: installiert"
else
  warn "unattended-upgrades ist nicht installiert. Es patcht sich nichts von selbst."
fi

kopf "Zombie-Pakete (ohne Repo-Quelle)"
obs=$(apt list '?obsolete' 2>/dev/null | grep -cv "^Auflistung\|^Listing" || true)
info "Obsolete Pakete: $obs"
[ "$obs" -gt 10 ] && warn "$obs Pakete ohne Repo-Quelle. Release-Reste pruefen (Kapitel 1)."
apt list '?obsolete' 2>/dev/null | grep -v "^Auflistung\|^Listing" | cut -d/ -f1 | head -15

kopf "Drittquellen"
ls /etc/apt/sources.list.d/ 2>/dev/null
keys=$(ls /etc/apt/trusted.gpg.d/ 2>/dev/null | wc -l)
[ "$keys" -gt 0 ] && info "Hinweis: $keys Keys liegen global in trusted.gpg.d (besser: signed-by-Scoping)."

kopf "systemd-Zustand"
zustand=$(systemctl is-system-running 2>/dev/null || true)
info "is-system-running: $zustand"
[ "$zustand" = "running" ] || warn "Systemzustand ist '$zustand' statt 'running'"
failed=$(systemctl --failed --no-legend 2>/dev/null | wc -l)
ufailed=$(systemctl --user --failed --no-legend 2>/dev/null | wc -l)
info "Fehlgeschlagene Units: System=$failed User=$ufailed"
[ "$((failed+ufailed))" -gt 0 ] && warn "Fehlgeschlagene Units vorhanden (systemctl --failed)"

kopf "Journal-Fehler (aktueller Boot)"
if journalctl -b -p err -q --no-pager >/dev/null 2>&1; then
  errs=$(journalctl -b -p err -q --no-pager 2>/dev/null | wc -l)
  info "Fehlermeldungen seit Boot: $errs"
  [ "$errs" -gt 50 ] && warn "$errs Journal-Fehler seit Boot. Auf Wiederholungsmuster pruefen."
else
  info "System-Journal nicht lesbar. Fuer vollen Einblick: Gruppe systemd-journal (Kapitel 3)."
fi

kopf "Wartungstimer"
for t in apt-daily.timer apt-daily-upgrade.timer fstrim.timer logrotate.timer; do
  s=$(systemctl is-active "$t" 2>/dev/null || true)
  printf '%-26s %s\n' "$t" "$s"
  [ "$s" = "active" ] || warn "Timer $t ist nicht aktiv"
done

kopf "Offene Ports (ohne localhost)"
if hat ss; then
  ss -tulnH 2>/dev/null | awk '{print $1, $5}' | grep -v "127.0.0.1\|\[::1\]" | sort -u | head -20
  info "Regel: Jede Zeile muss erklaerbar sein. Prozessnamen zeigt nur 'sudo ss -tulnp'."
fi

kopf "Docker"
if hat docker && docker info >/dev/null 2>&1; then
  docker ps -a --format '{{.Names}}\t{{.Status}}' | head -10
  if docker ps -a --format '{{.Status}}' | grep -qi restarting; then
    warn "Container in Restart-Schleife gefunden (docker ps -a)"
  fi
  docker system df 2>/dev/null
else
  info "Docker nicht installiert oder nicht erreichbar."
fi

kopf "Plattenplatz"
df -h 2>/dev/null | grep -vE "tmpfs|efivarfs" | head -8
voll=$(df --output=pcent,target 2>/dev/null | grep -vE "tmpfs|Use|/boot/efi" | awk '$1+0 > 85 {print $2" ("$1")"}')
[ -n "$voll" ] && warn "Ueber 85% voll: $voll"

kopf "Caches und Leichen"
du -sh /var/cache/apt/archives 2>/dev/null | awk '{print "apt-Cache: "$1}'
du -xsh "$HOME/.cache" 2>/dev/null | awk '{print "~/.cache:  "$1}'
leichen=$(ls "$HOME" 2>/dev/null | grep -E "^core\.|^debug\.log$|\.deb$" || true)
if [ -n "$leichen" ]; then
  warn "Leichen in der Home-Wurzel gefunden:"
  printf '  %s\n' $leichen
fi
alt=$(find "$HOME/Downloads" -maxdepth 1 -type f -mtime +180 -size +50M 2>/dev/null | wc -l)
[ "$alt" -gt 0 ] && info "Downloads: $alt grosse Dateien aelter als 6 Monate (Kandidaten fuers Loeschen)."

kopf "SSH"
if [ -d "$HOME/.ssh" ]; then
  rechte=$(stat -c %a "$HOME/.ssh" 2>/dev/null)
  [ "$rechte" = "700" ] || warn "~/.ssh hat Rechte $rechte statt 700"
  ak=$(grep -c . "$HOME/.ssh/authorized_keys" 2>/dev/null || echo 0)
  info "authorized_keys-Eintraege: $ak (jeden Schluessel erklaeren koennen)"
fi
if sudo -n sshd -T >/dev/null 2>&1; then
  sudo -n sshd -T | grep -i "^passwordauthentication"
else
  info "sshd-Config nur mit Root pruefbar: sudo sshd -T | grep -i passwordauth"
fi

kopf "Datei-Rechte auf Geheimnissen"
treffer=$(find "$HOME" -maxdepth 3 \( -iname "*key*" -o -iname "*secret*" -o -iname "*token*" \
  -o -iname "*.kdbx" -o -iname "*.keyx" \) -perm -o+r -not -path "*/.local/share/*" \
  -not -path "*/.cache/*" -type f 2>/dev/null | head -5)
if [ -n "$treffer" ]; then
  warn "Weltlesbare Dateien mit verdaechtigen Namen:"
  printf '  %s\n' $treffer
else
  info "Keine weltlesbaren Schluessel-Kandidaten in den ueblichen Pfaden."
fi

kopf "Flatpak"
if hat flatpak; then
  upd=$(flatpak remote-ls --updates 2>/dev/null | wc -l)
  info "Ausstehende Flatpak-Updates: $upd"
  [ "$upd" -gt 10 ] && warn "$upd Flatpak-Updates stehen aus"
fi

kopf "Backup-Realitaet"
timer=$(systemctl --user list-timers --no-legend 2>/dev/null | grep -i backup || true)
if [ -n "$timer" ]; then
  info "Backup-Timer gefunden:"
  printf '  %s\n' "$timer"
else
  warn "Kein User-Backup-Timer gefunden. Gibt es ueberhaupt ein automatisches Backup?"
fi
info "Plattengesundheit braucht Root: sudo smartctl -H -A /dev/<platte> (Kapitel 6)."

kopf "ZUSAMMENFASSUNG"
if [ "${#WARNUNGEN[@]}" -eq 0 ]; then
  info "Keine Warnungen. Trotzdem gilt: Dieses Skript ist der Schnellcheck, nicht die Inspektion."
else
  printf 'Es gibt %d Warnungen:\n' "${#WARNUNGEN[@]}"
  for w in "${WARNUNGEN[@]}"; do printf ' - %s\n' "$w"; done
  info ""
  info "Naechster Schritt: pro Warnung das passende Kapitel im Runbook aufschlagen."
fi
