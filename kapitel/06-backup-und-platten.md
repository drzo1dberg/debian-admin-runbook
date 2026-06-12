# Backup und Plattengesundheit

**Warum das wichtig ist:** Das teuerste Inspektionsergebnis ist fast immer dasselbe: Es gibt kein echtes Backup. Snapshots auf derselben Platte fühlen sich wie ein Backup an, sind aber nur ein Rollback-Mechanismus. Stirbt die Platte, sterben die Snapshots mit. Dazu kommt die zweite Hälfte der Wahrheit: Ohne SMART-Überwachung gibt es keine Vorwarnung vor dem Plattentod. Die Kombination aus beidem bedeutet, dass wertvolle Daten genau einmal existieren und niemand gewarnt wird, bevor sie verschwinden.

## Was du prüfst (die Inspektion)

### 1. Die Bestandsaufnahme: Was existiert wie oft?

Die 3-2-1-Regel als Messlatte: drei Kopien, auf zwei verschiedenen Medien, davon eine außer Haus. Privat erreicht das kaum jemand vollständig. Aber jede Abweichung sollte eine bewusste Entscheidung sein und kein Versehen.

```bash
lsblk -f                          # Welche Platten und Dateisysteme gibt es?
df -h | grep -v tmpfs             # Was ist wo gemountet und wie voll?
# Dann pro Datenbestand die Frage beantworten: Wo liegt die zweite Kopie?
```

Backup-Archäologie hilft bei der Antwort. Alte Log-Dateien von rsync-Läufen verraten, was wann wohin gesichert wurde und in welche Richtung. Ein häufiger Befund: Das letzte manuelle Backup ist Monate alt, und für ganze Datenbestände existiert gar keine zweite Kopie. Besonders kritisch sind dabei persönliche Fotos und Dokumente, denn die sind im Gegensatz zu Mediensammlungen nicht wiederbeschaffbar.

### 2. Snapshots ehrlich einordnen

```bash
sudo timeshift --list 2>/dev/null | tail -8
grep backup_device /etc/timeshift/timeshift.json 2>/dev/null
```

Liegt das Snapshot-Ziel auf derselben Platte wie das System, schützt Timeshift gegen kaputte Updates und Konfigurationsunfälle. Gegen Plattenausfall, Diebstahl und Verschlüsselungstrojaner schützt es nicht. Beides braucht man: Snapshots für das schnelle Rollback und ein echtes Backup auf ein anderes Medium.

### 3. Existiert ein automatisches Backup und lief es?

```bash
systemctl --user list-timers | grep -i backup
systemctl list-timers | grep -i backup
# Ein Timer, der existiert, aber nie lief, ist ein Befund.
# Gar kein Timer ist der häufigere Befund.
```

### 4. SMART: Wie gesund sind die Platten?

```bash
sudo smartctl -H -A /dev/nvme0n1
sudo smartctl -H -A /dev/sda
```

Lesehilfe für die wichtigsten Werte:

- **NVMe:** `Percentage Used` zeigt den Verschleiß. `Available Spare` sollte nahe 100 Prozent liegen. `Media and Data Integrity Errors` muss 0 sein.
- **HDD:** `Reallocated_Sector_Ct`, `Current_Pending_Sector` und `Offline_Uncorrectable` müssen 0 sein. Steigende Werte sind ein Vorbote des Ausfalls. `UDMA_CRC_Error_Count` über 0 deutet auf Kabelprobleme.
- **SATA-SSD:** `Wear_Leveling_Count` zeigt die Restlebensdauer als normalisierten Wert. `Total_LBAs_Written` mal Sektorgröße ergibt die geschriebene Datenmenge, die man mit der TBW-Angabe des Herstellers vergleicht.

```bash
systemctl is-active smartmontools 2>/dev/null
# inactive oder nicht installiert heißt: niemand überwacht die Platten laufend.
```

## Typische Befunde und was du dagegen tust

### Kein Backup: Borg einrichten (das Standardrezept)

Borg dedupliziert, komprimiert und verschlüsselt. Ziel ist eine andere physische Platte.

```bash
sudo apt install borgbackup
mkdir -p /pfad/zur/anderen/platte/borg-home ~/.config/borg
( umask 077; tr -dc 'A-Za-z0-9' </dev/urandom | head -c 48 > ~/.config/borg/passphrase )
chmod 600 ~/.config/borg/passphrase
export BORG_PASSCOMMAND='cat ~/.config/borg/passphrase'
borg init --encryption=repokey-blake2 /pfad/zur/anderen/platte/borg-home
borg key export /pfad/zur/anderen/platte/borg-home ~/.config/borg/key-backup
```

Die Passphrase und der exportierte Schlüssel gehören zusätzlich an einen externen Ort, etwa in den Passwortmanager oder auf Papier. Ohne sie ist das Repo im Ernstfall wertlos.

Das Backup-Skript schließt aus, was re-beschaffbar ist: Caches, Spiele-Bibliotheken, Toolchains, Trash und Downloads. Ein Home-Verzeichnis von über 100 GB schrumpft damit oft auf einen Bruchteil. Automatisiert wird per systemd-User-Timer mit `OnCalendar=daily` und `Persistent=true`. Damit der Timer auch ohne eingeloggte Session läuft, muss Linger aktiv sein:

```bash
loginctl enable-linger $USER
systemctl --user enable --now backup-home.timer
```

### Der Restore-Test (ohne ihn ist alles nur Hoffnung)

```bash
borg list /pfad/zum/repo                          # Archive vorhanden?
borg list /pfad/zum/repo::<archivname> | head     # Inhalt plausibel?
cd /tmp && borg extract /pfad/zum/repo::<archivname> home/<user>/.bashrc
# Eine echte Datei wirklich zurückholen und ansehen. Erst jetzt ist es ein Backup.
```

### Keine Plattenüberwachung: smartd einrichten

```bash
sudo apt install smartmontools
# In /etc/smartd.conf die DEVICESCAN-Zeile um Selbsttests erweitern:
# DEVICESCAN -a -n standby,q -s (S/../.././02|L/../../6/03) -W 4,45,55 -m root -M exec /usr/share/smartmontools/smartd-runner
# Das bedeutet: täglich 2 Uhr Kurztest, samstags 3 Uhr Langtest, Temperaturwarnungen.
sudo systemctl enable --now smartmontools
```

Achtung bei der Benachrichtigung: `-m root` verschickt Mail. Ohne installierten Mailserver verpufft die Warnung. Dann braucht es ein Skript unter `/etc/smartmontools/run.d/`, das stattdessen eine Desktop-Benachrichtigung oder einen anderen Kanal nutzt.

### Einzelkopien wertvoller Daten

Bis eine zweite Platte oder eine externe Lösung da ist, hilft ein Zwischenschritt: die unwiederbringlichen Teilmengen (Fotos, Dokumente, eigene Projekte) auf eine andere interne Platte spiegeln. Das ist kein vollwertiges Backup, aber es entschärft den Totalverlust.

## Merksätze

1. Snapshots auf derselben Platte sind ein Rollback und kein Backup.
2. Ein Backup ohne Restore-Test ist Hoffnung mit Zeitstempel.
3. Passphrase und Schlüssel-Export gehören an einen Ort außerhalb des Backups.
4. SMART-Werte mit 0 bei Reallocated und Pending sind das Ziel. Steigende Werte sind die Vorwarnung, für die man smartd installiert.
5. Unwiederbringliches zuerst sichern. Filme kann man neu beschaffen, Fotos nicht.
