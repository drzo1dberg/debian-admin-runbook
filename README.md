# Debian Admin-Runbook: die Jahresinspektion

Ein Runbook zum Selberlernen. Es beschreibt, wie man ein Debian-System einmal im Jahr oder nach jedem größeren Umbau gründlich inspiziert und wartet. Das Vorbild ist die Inspektion in der Autowerkstatt: erst die vollständige Bestandsaufnahme, dann der Kostenvoranschlag, dann die Reparatur.

## Die Philosophie

**1. Erst der Kostenvoranschlag, dann die Werkstatt.**
Die Inspektion ist strikt read-only. Man sammelt Befunde, sortiert sie nach Schweregrad und schätzt den Aufwand. Erst danach wird entschieden, was gemacht wird. Niemals sehen und sofort fixen. Was wie eine Leiche aussieht, kann in Benutzung sein. Ein Blick auf die Änderungszeit einer Datei verrät oft mehr als ihr Name.

**2. Reversibel vor endgültig.**
Configs und Daten werden zuerst in ein Archivverzeichnis verschoben, zum Beispiel `~/altlasten-<datum>/`. Nach einer Woche ohne Vermissen darf gelöscht werden. Nur Caches dürfen sofort weg, denn sie regenerieren sich. Vor jedem `git reset` oder `git pull` auf ein driftendes Repo gehört ein Backup-Branch angelegt.

**3. Verstehen vor abschalten.**
Vor jedem `apt purge` eines Dienstes steht der Blick in seine Konfiguration. Ein Webserver kann ein vergessenes Experiment sein oder der Reverse-Proxy vor einem Dienst, der gebraucht wird. Das weiß man erst, nachdem man nachgesehen hat.

**4. Simulieren vor ausführen.**
`apt-get -s remove <paket> --autoremove` zeigt den kompletten Rattenschwanz an Abhängigkeiten, bevor er real entfernt wird. An wenigen vergessenen Kleinpaketen können hunderte Pakete hängen.

**5. Härtetest oder es zählt nicht.**
"Müsste eigentlich gehen" ist kein Befund. Ein VPN-Killswitch gilt erst als vorhanden, wenn der Tunnel getrennt wurde und die Verbindung nachweislich blockiert war. Ein Backup gilt erst als Backup, wenn der Restore-Test gelaufen ist.

## Ablauf einer Inspektion

1. **Inspektion (read-only):** `scripts/inspektion.sh` laufen lassen. Danach pro Kapitel die Prüfbefehle durchgehen und Befunde notieren.
2. **Kostenvoranschlag:** Befunde nach Schweregrad (kritisch, hoch, mittel, niedrig) und Aufwand sortieren. Daraus Arbeitspakete schnüren.
3. **Werkstatt:** Die Pakete in sinnvoller Reihenfolge abarbeiten. Sicherheit zuerst. Backup nie ans Ende schieben. Kosmetik zuletzt.
4. **Abnahme:** `systemctl --failed` muss leer sein. `apt list --upgradable` muss leer sein. Härtetests müssen bestanden sein. Offene Ports müssen vollständig erklärbar sein.

## Kapitel

| # | Kapitel | Kernfrage |
|---|---|---|
| 1 | [Pakete und Updates](kapitel/01-pakete-und-updates.md) | Ist das System aktuell und patcht es sich selbst? |
| 2 | [Dienste und Ports](kapitel/02-dienste-und-ports.md) | Was lauscht da und wird es noch gebraucht? |
| 3 | [systemd, Boot und Logs](kapitel/03-systemd-boot-logs.md) | Läuft alles, was laufen soll, und nichts heimlich kaputt? |
| 4 | [Speicher und Hygiene](kapitel/04-speicher-und-hygiene.md) | Wo liegen die Gigabyte-Leichen? |
| 5 | [Sicherheit](kapitel/05-sicherheit.md) | Zeitsync, SSH, Datei-Rechte auf Geheimnissen, VPN-Leaks |
| 6 | [Backup und Platten](kapitel/06-backup-und-platten.md) | Überleben die Daten einen Plattentod? |
| 7 | [Desktop-Altlasten](kapitel/07-desktop-altlasten.md) | Aufräumen nach einem Desktop-Wechsel |
| 8 | [Dotfiles und Drift](kapitel/08-dotfiles-und-drift.md) | Eine Wahrheit für Configs auf allen Maschinen |

Dazu kommt [`scripts/inspektion.sh`](scripts/inspektion.sh) als read-only Schnellcheck für den Einstieg.

## Schnell-Checkliste (die 15-Minuten-Inspektion)

```bash
# System und Zeit
cat /etc/os-release | head -2; uname -r; uptime
timedatectl | grep -E "synchronized|NTP"          # muss "yes" und "active" zeigen

# Updates
sudo apt update -qq && apt list --upgradable 2>/dev/null | wc -l
dpkg -l unattended-upgrades 2>/dev/null | grep -c ^ii   # 1 bedeutet: Automatik vorhanden

# Dienste und Ports
systemctl --failed --no-legend                     # leer ist das Ziel
ss -tulnp 2>/dev/null | grep -v 127.0.0.1          # jeden Eintrag erklaeren koennen

# Docker-Zombies
docker ps -a 2>/dev/null | grep -i restarting

# Platz und Leichen
df -h / ; du -xsh ~/.cache /var/cache/apt 2>/dev/null
ls -la ~ | grep -E "core\.|debug\.log|\.deb$"      # nichts davon gehoert in die Home-Wurzel

# Backup-Realitaet
systemctl --user list-timers | grep -i backup      # existiert ein Timer und lief er?
sudo smartctl -H /dev/nvme0n1 /dev/sda 2>/dev/null | grep -i result
```

Leuchtet irgendwo Rot auf, hilft das passende Kapitel weiter.

## Typische Befunde aus der Praxis

Diese Muster tauchen auf vernachlässigten Systemen immer wieder auf. Alle sind leise. Nichts davon wirft Fehlermeldungen. Genau das macht sie gefährlich.

- **Keine Zeitsynchronisation installiert.** Die Uhr driftet unbemerkt. Irgendwann scheitern 2FA-Codes und TLS-Prüfungen. Der Fix ist eine Zeile, das Problem bleibt oft ein Jahr unentdeckt.
- **Schlüsseldateien mit Rechten 777.** Jeder Prozess des Users darf den Zweitfaktor der Passwortdatenbank lesen.
- **Container monatelang in einer Restart-Schleife.** Dauerlast und viele Gigabyte tote Images. Auffindbar nur über `docker ps -a`, das nie jemand aufruft.
- **Snapshots auf derselben Platte als "Backup" verstanden.** Das ist ein Rollback-Mechanismus. Gegen Plattenausfall hilft er nicht. Wertvolle Daten existieren dann genau einmal.
- **Torrent-Client lauscht trotz VPN auf allen Interfaces.** Ohne Interface-Bindung läuft der Traffic bei einem Tunnelabbruch über die echte IP weiter.
- **Ein Dutzend Netzwerkdienste für ein Netz, das es nicht mehr gibt.** Firewall-Regeln und Exporte zeigen auf alte Subnetze und verraten so die Drift.
- **Dotfiles als lose Kopien.** Lokale Configs und das Repo laufen still auseinander, bis nichts mehr zusammenpasst.

## Rhythmus

- **Wöchentlich automatisch:** unattended-upgrades, smartd und Backup-Timer richtet man einmal ein und darf sie dann vergessen.
- **Monatlich fünf Minuten:** die Schnell-Checkliste oben.
- **Jährlich oder nach jedem Umbau:** die volle Inspektion, Kapitel für Kapitel.
