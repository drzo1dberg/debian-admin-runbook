# systemd, Boot und Logs

**Warum das wichtig ist:** Ein System kann sich jahrelang gesund anfühlen, während im Hintergrund Units fehlschlagen, ein Programm regelmäßig abstürzt oder ein Tool das Journal mit zehntausenden Fehlerzeilen flutet. Nichts davon erzeugt ein Fenster auf dem Bildschirm. Wer nie ins Journal schaut, erfährt es nicht. Dazu kommt der Boot: Auf alten Installationen sammeln sich Wartezeiten und verwaiste Units, die jeden Start um Sekunden bis Minuten verlängern.

## Was du prüfst (die Inspektion)

Alle Befehle in diesem Abschnitt sind read-only und ändern nichts.

### 1. Gesamtzustand: Läuft alles?

```bash
systemctl is-system-running
# "running" ist das Ziel. "degraded" bedeutet: mindestens eine Unit ist fehlgeschlagen.

systemctl --failed --no-legend          # System-Units
systemctl --user --failed --no-legend   # User-Units der eigenen Session
# Beide Listen müssen leer sein.
```

### 2. Fehler im Journal lesen

```bash
journalctl -b -p err --no-pager | tail -50
# -b zeigt nur den aktuellen Boot, -p err alles ab Priorität "err".
# Wiederholt sich eine Meldung hundertfach? Das ist der Kandidat.
journalctl -b -p err --no-pager | wc -l   # Größenordnung des Problems
```

Wichtig: Ohne Mitgliedschaft in der Gruppe `systemd-journal` oder `adm` sieht ein normaler User nur sein eigenes User-Journal. Die Systemfehler bleiben unsichtbar. Prüfen mit `id` und beheben mit:

```bash
sudo usermod -aG systemd-journal <user>   # gilt ab dem nächsten Login
```

### 3. Bootzeit zerlegen

```bash
systemd-analyze
# Gesamtzeit, aufgeteilt in firmware, loader, kernel und userspace.

systemd-analyze blame | head -15
# Die langsamsten Units. Klassische Bremser auf Desktops sind
# NetworkManager-wait-online (wartet auf Netz, ohne Netz-Mounts meist unnötig)
# und fwupd-refresh (Firmware-Metadaten, blockiert das Boot-Ziel selten wirklich).

systemd-analyze critical-chain
# Der tatsächlich blockierende Pfad. Nur was hier steht, verzögert wirklich.
```

### 4. Timer-Inventur

```bash
systemctl list-timers --no-pager
```

Zwei Richtungen prüfen. Erstens: Laufen die Wartungstimer, die da sein sollen (`apt-daily`, `fstrim`, `logrotate`, `e2scrub`)? Zweitens: Laufen Timer für Dinge, die es nicht gibt? Ein typischer Befund sind RAID-Check-Timer auf Systemen ohne RAID. Das prüft man mit `cat /proc/mdstat`.

### 5. Abstürze und Coredumps

```bash
coredumpctl list --no-pager 2>/dev/null | tail -10
ls -la ~ | grep "^-.*core"
cat /proc/sys/kernel/core_pattern
```

Steht in `core_pattern` nur `core`, landen Absturz-Dumps unverwaltet als große Dateien im jeweiligen Arbeitsverzeichnis. Dort übersieht man sie. Ein Coredump im Home ist eine Nachricht: Irgendein Programm ist abgestürzt. `file core.*` verrät welches. Mit installiertem `systemd-coredump` werden Dumps zentral erfasst, rotiert und sind per `coredumpctl` samt Datum und Backtrace abrufbar.

### 6. Verwaiste und doppelte Starts

```bash
systemctl list-unit-files --state=enabled --no-pager | less
# Units mit nie erfüllten Start-Bedingungen starten still nie und verwirren nur.

ls /etc/xdg/autostart ~/.config/autostart 2>/dev/null
# Doppelte Startmechanik (XDG-Autostart plus systemd-User-Unit für dasselbe Programm)
# erzeugt typische scope-Fehler im User-Journal bei jedem Login.
```

## Typische Befunde und was du dagegen tust

**Fehlgeschlagene Unit:**
```bash
systemctl status <unit>
journalctl -u <unit> -b --no-pager | tail -30
# Erst die Ursache verstehen. Dann reparieren oder bewusst deaktivieren.
```

**Journal-Flut durch ein einzelnes Tool:** Das Tool reparieren, aktualisieren oder entsorgen. Ein Programm, das alle 30 Sekunden denselben Fehler loggt, schreibt im Jahr Millionen Zeilen und versteckt damit echte Probleme. Solche Dauerläufer findet man nur über die Wiederholungsmuster im Journal.

**Coredump gefunden:**
```bash
file core.*                         # welches Programm war es?
sudo apt install systemd-coredump   # künftige Abstürze zentral erfassen
# Danach den alten Dump löschen. Er ist gesichtet und hat seinen Zweck erfüllt.
```

**Langsamer Boot durch wait-online:** Wenn die fstab keine Netz-Mounts enthält und kein Dienst beim Start zwingend Netz braucht:
```bash
sudo systemctl disable NetworkManager-wait-online.service
```

**Verwaiste Timer und Units:**
```bash
sudo systemctl disable --now <unit-oder-timer>
sudo systemctl mask <unit>          # wenn sie als Abhängigkeit wiederkommen könnte
```

## Merksätze

1. `systemctl --failed` und `is-system-running` sind der Puls des Systems. Beides gehört in jede Inspektion.
2. Ohne die Gruppe `systemd-journal` sieht man nur die halbe Wahrheit.
3. Wiederholung ist das Signal. Eine Fehlermeldung ist Rauschen. Dieselbe Meldung tausendfach ist ein Befund.
4. Ein Coredump ist Post vom abgestürzten Programm. Erst lesen, dann löschen.
5. `blame` zeigt Verdächtige. `critical-chain` zeigt Täter.
