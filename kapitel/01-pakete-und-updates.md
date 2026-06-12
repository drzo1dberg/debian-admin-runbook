# Pakete und Updates

**Warum das wichtig ist:** Ausstehende Security-Updates sind die leiseste Sorte Risiko. Nichts ist kaputt und alles läuft. Genau deshalb schaut niemand hin. Besonders tückisch sind Pakete aus einem früheren Debian-Release, die nach dem Upgrade liegen geblieben sind. Sie bekommen nie wieder Sicherheitsfixes und fallen in keiner normalen Update-Routine auf.

## Was du prüfst (die Inspektion)

### 1. Was steht aus und wie dringend ist es?

```bash
sudo apt update
apt list --upgradable 2>/dev/null
# Die Quelle hinter jedem Paket lesen.
# "-security" bedeutet Sicherheitsupdate. Das wird sofort eingespielt.
# Normale Release- oder Drittquellen bedeuten: zeitnah, aber ohne Eile.
```

### 2. Wie oft wird hier tatsächlich gepatcht?

```bash
grep "Start-Date" /var/log/apt/history.log | tail -10
zgrep "Start-Date" /var/log/apt/history.log.*.gz 2>/dev/null | tail -10
# Die Abstände zwischen den Daten sind die echte Update-Frequenz.
# Monatliche Abstände heißen: Security-Fixes liegen regelmäßig wochenlang ungepatcht herum.
```

### 3. Patcht sich das System selbst?

```bash
dpkg -l unattended-upgrades 2>/dev/null | grep ^ii   # keine Ausgabe ist ein Befund
cat /etc/apt/apt.conf.d/20auto-upgrades 2>/dev/null   # beide Werte "1" bedeuten aktiv
```

Achtung: Die Timer `apt-daily` und `apt-daily-upgrade` laufen auch ohne das Paket `unattended-upgrades`. Sie laden dann nur Paketlisten herunter und installieren nichts. Wer nur die Timer prüft, wiegt sich in falscher Sicherheit.

### 4. Zombie-Pakete: installiert, aber von keinem Repo mehr versorgt

```bash
apt list '?obsolete' 2>/dev/null
```

Die Ausgabe zerfällt in drei Kategorien:

1. **Bewusst manuell Installiertes** (eigene .deb-Dateien). Das ist in Ordnung. Aber Updates sind ab jetzt Aufgabe des Users, nicht von apt.
2. **Reste vom letzten Release-Upgrade.** Erkennbar am alten Versionssuffix, etwa `deb12u1` auf einem Debian-13-System. Diese Pakete bekommen nie wieder CVE-Fixes. Typische Kandidaten sind alte Java-Runtimes und Multimedia-Bibliotheken. Gerade Letztere sind klassische Einfallstore.
3. **Verwaiste Bibliotheken.** Prüfen mit:

```bash
apt-cache rdepends --installed <paket>
# Eine leere Liste bedeutet: nichts hängt mehr daran, das Paket kann weg.
# Ein Eintrag mit Pipe wie "|firefox-esr" ist eine Alternativ-Abhängigkeit.
# Das Programm kann diese Bibliothek nutzen, braucht sie aber nicht,
# wenn die neuere Variante installiert ist.
```

### 5. Drittquellen-Hygiene

```bash
ls /etc/apt/sources.list.d/
grep -rH "signed-by\|Signed-By" /etc/apt/sources.list.d/ | cut -c1-100
ls /etc/apt/trusted.gpg.d/
```

Jede Quelle in dieser Liste darf Pakete als root installieren. Zwei Fragen pro Quelle:

1. Wird sie noch gebraucht? Ein typischer Befund ist ein privates Repo, das nur für ein einziges Programm eingebunden wurde und längst verwaist ist. Besonders heikel sind Repos für ein anderes Release, etwa Unstable-Pakete auf einem Stable-System.
2. Ist der Schlüssel gescoped? Ein Key in `/etc/apt/trusted.gpg.d/` gilt global für alle Quellen. Richtig ist ein Key unter `/etc/apt/keyrings/`, der per `signed-by` nur für seine eigene Quelle gilt.

### 6. Kernel-Bestand und Ballast

```bash
dpkg -l 'linux-image-*' | grep ^ii        # mehr als zwei bis drei Kernel: autoremove fällig
apt-get -s autoremove | grep ^Remv        # Simulation: was würde fliegen?
du -sh /var/cache/apt/archives            # mehrere Gigabyte heißen: apt clean lief nie
```

### 7. Flatpak nicht vergessen

```bash
flatpak remote-ls --updates 2>/dev/null   # auch Treiber-Extensions brauchen Updates
flatpak list --columns=application,installation | sort | uniq -c | sort -rn | head
# Doppelte Einträge in system und user bedeuten doppelte Pflege und doppelten Platz.
```

## Typische Befunde und was du dagegen tust

**Ausstehende Security-Updates:**
```bash
sudo apt full-upgrade
sudo needrestart        # zeigt Dienste, die noch mit alten Bibliotheken laufen
```

**Kein unattended-upgrades:**
```bash
sudo apt install unattended-upgrades apt-listchanges
printf 'APT::Periodic::Update-Package-Lists "1";\nAPT::Periodic::Unattended-Upgrade "1";\n' \
  | sudo tee /etc/apt/apt.conf.d/20auto-upgrades
sudo systemctl enable --now unattended-upgrades
```

**Release-Reste ohne Support:** Erst `rdepends` prüfen, dann purgen. Vorher klären, ob die aktuelle Variante der Bibliothek installiert ist. Dann hängt auch keine Alternativ-Abhängigkeit mehr daran.

**Ungescopte Repo-Keys:** Key nach `/etc/apt/keyrings/` verschieben und in der Quelldatei referenzieren:
```
deb [signed-by=/etc/apt/keyrings/example.gpg] https://repo.example/ stable main
```

**Alte Kernel und Cache:**
```bash
sudo apt autoremove --purge && sudo apt clean
# autoremove behält den laufenden und den neuesten Kernel immer.
```

**Flatpak:**
```bash
sudo flatpak update -y && sudo flatpak uninstall --unused -y
flatpak update --user -y && flatpak uninstall --user --unused -y
```

## Merksätze

1. Die Quelle hinter dem Update lesen. `-security` heißt heute und nicht am Monatsende.
2. `apt list '?obsolete'` ist die Beichte nach jedem Release-Upgrade. Alles mit altem Versionssuffix bekommt nie wieder Fixes.
3. Jede Drittquelle ist root-Zugang. Scopen oder rauswerfen.
4. Manuell installierte .deb-Dateien haben kein Update-Abo. Der User ist das Update-Abo.
5. Simulieren ist gratis. `apt-get -s` gehört vor jedes remove und autoremove.
