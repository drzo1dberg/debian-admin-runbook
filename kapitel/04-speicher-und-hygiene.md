# Speicher und Datenhygiene

**Warum das wichtig ist:** Toter Ballast kommt selten als ein großer Brocken. Er kommt als Sediment: Docker-Images unter vergessenen Containern, Paket-Caches, die nie geleert wurden, Browser-Caches, Coredumps in der Home-Wurzel und alte Installer in Downloads. Auf vernachlässigten Systemen summiert sich das schnell auf zweistellige Gigabyte-Beträge. Gefährlicher als der Platzverbrauch ist das Übersehen: Ein Container in einer Restart-Schleife frisst monatelang CPU, und ein Coredump im Home weist auf einen echten Absturz hin, den niemand bemerkt hat.

## Was du prüfst (die Inspektion)

### 1. Überblick verschaffen, dann bohren

```bash
df -h | grep -v tmpfs                 # Wie voll ist was?
du -xsh ~/* ~/.cache ~/.local 2>/dev/null | sort -rh | head -20
# -x bleibt auf einem Dateisystem und springt nicht in fremde Mounts.
# sort -rh sortiert die größten Posten nach oben.
# Danach rekursiv in den dicksten Eintrag bohren:
du -xsh ~/.cache/* 2>/dev/null | sort -rh | head -10
```

### 2. Docker: die Zombie-Farm (Pflichtcheck bei installiertem Docker)

```bash
docker ps -a
# Die STATUS-Spalte ist der Inspektionspunkt. Ein Container mit
# "Restarting (1) 30 seconds ago" bei einem Erstellungsdatum von vor Monaten
# hängt in einer Endlosschleife. Das kostet dauerhaft CPU und spammt Logs.
docker system df          # Images, Container und Volumes: TOTAL gegen RECLAIMABLE
```

### 3. Die üblichen Verdächtigen

```bash
du -sh /var/cache/apt/archives        # mehrere Gigabyte heißen: apt clean lief nie
journalctl --disk-usage               # Journalgröße
ls -la ~ | grep -E "^-.*core|debug\.log|\.deb$|\.AppImage$"
# Coredumps, Debug-Logs und Installer gehören nicht in die Home-Wurzel.
find ~/Downloads -type f -mtime +180 -size +50M -exec ls -lh {} \; 2>/dev/null
# Installer, ISOs und Tarballs älter als sechs Monate sind re-downloadbar und löschbar.
du -sh ~/.local/share/Trash 2>/dev/null
```

### 4. Toolchain-Doppelungen

```bash
dpkg -l rustc cargo 2>/dev/null | grep ^ii
rustup toolchain list 2>/dev/null
du -sh ~/.rustup ~/.cargo ~/.npm-global ~/go 2>/dev/null
npm ls -g --depth=0 2>/dev/null
```

Typische Befunde: Eine Sprache ist doppelt installiert, einmal über apt und einmal über den Sprach-eigenen Manager. Oder im globalen npm-Verzeichnis liegt noch die alte Installation eines Tools, das längst auf anderem Weg installiert wurde. Solche Doppelungen kosten Gigabytes und stiften Verwirrung darüber, welche Version eigentlich läuft.

### 5. Flatpak-Gewicht

```bash
flatpak list --app | wc -l
du -sh /var/lib/flatpak ~/.local/share/flatpak 2>/dev/null
# Viele Gigabyte für eine Handvoll Apps deuten auf verwaiste oder doppelte Runtimes.
# Datenreste deinstallierter Apps findet man so:
ls ~/.var/app/ | while read a; do flatpak info "$a" >/dev/null 2>&1 || echo "verwaist: $a"; done
```

### 6. Die Snapshot-Falle bei btrfs

```bash
sudo timeshift --list 2>/dev/null | tail -8
```

Wenn Timeshift btrfs-Snapshots auf der Systemplatte anlegt, werden gelöschte Dateien nicht sofort frei. Die Snapshots der letzten Tage referenzieren die Daten weiter. `df` rührt sich kaum, obwohl gerade dutzende Gigabyte gelöscht wurden. Der Platz kommt erst zurück, wenn die täglichen Snapshots durchrotiert sind. Das ist kein Fehler, sondern die Funktionsweise von Copy-on-Write. Wer das nicht weiß, löscht in Panik weiter.

## Typische Befunde und was du dagegen tust

**Docker-Zombies:**
```bash
docker inspect <container> --format '{{index .Config.Labels "com.docker.compose.project.working_dir"}}'
# Erst nachsehen, zu welchem Projekt der Container gehörte. Dann:
docker rm -f <container...>
docker rmi <image>            # gezielt ist besser als prune -a,
docker volume rm <volume>     # das auch Images löscht, die man nächste Woche wieder zieht
```

**Caches:** Sie dürfen sofort weg und regenerieren sich:
```bash
sudo apt clean
pip cache purge
npm cache clean --force
rm -rf ~/.cache/thumbnails
# Browser-Caches nur bei Platznot löschen. Der Neuaufbau kostet Surfgeschwindigkeit.
```

**Coredump im Home:** Erst lesen, dann löschen. `file core.*` zeigt das abgestürzte Programm. Details dazu stehen im Kapitel zu systemd und Logs.

**Installer-Sediment:** Löschen, was re-downloadbar ist. Große Mediendateien gehören auf die Datenplatte und nicht dauerhaft in Downloads.

**Toolchain-Doppelungen:** Eine Quelle pro Sprache wählen. Bei Rust zum Beispiel rustup behalten, die apt-Pakete purgen und redundante Toolchains mit `rustup toolchain uninstall` entfernen.

## Merksätze

1. `docker ps -a` gehört in jede Inspektion. Die STATUS-Spalte verrät Zombies, die `docker ps` versteckt.
2. Caches löschen ist gratis. Daten löschen ist endgültig. Erst reinschauen, dann `rm`.
3. Ein Coredump ist eine Nachricht und kein Müll.
4. Auf btrfs mit Snapshots lügt `df` für ein paar Tage. Gelöscht ist erst frei, wenn die Snapshots rotiert sind.
5. Jede Sprache bekommt genau eine Toolchain-Quelle.
