# Sicherheit

**Warum das wichtig ist:** Die größten Sicherheitslücken auf Privatsystemen sind selten spektakulär. Es sind stille Selbstverständlichkeiten, die nie jemand geprüft hat: eine Uhr, die ohne Zeitsynchronisation vor sich hin driftet, eine Schlüsseldatei mit Leserechten für jedermann oder ein Torrent-Client, der trotz VPN auf allen Interfaces lauscht. Nichts davon meldet sich von selbst. Alles davon ist in Minuten gefunden, wenn man weiß, wo man hinschaut.

## Was du prüfst (die Inspektion)

### 1. Zeitsynchronisation (30 Sekunden, großer Hebel)

```bash
timedatectl
# "System clock synchronized: yes" und "NTP service: active" ist der Sollzustand.
# Alles andere ist ein Befund.
```

Bei System-Umbauten geht der Zeitdienst gerne verloren. Die Uhr driftet dann unbemerkt. Die Folgen treffen einen später an unerwarteter Stelle: 2FA-Codes haben nur 30 bis 90 Sekunden Toleranz, TLS-Prüfungen und die Validierung von Paketquellen hängen ebenfalls an der korrekten Zeit.

### 2. SSH

```bash
sudo sshd -T | grep -Ei "passwordauthentication|permitrootlogin"
cat ~/.ssh/authorized_keys | awk '{print $1, $3}'
# Jeden Schlüssel in der Liste erklären können. Unbekannte Schlüssel sind ein Alarmsignal.
ls -la ~/.ssh
# Das Verzeichnis braucht 700. Private Schlüssel brauchen 600. Alles andere ist falsch.
```

### 3. Datei-Rechte auf Geheimnissen (der 777-Check)

```bash
find ~ -maxdepth 3 \( -iname "*key*" -o -iname "*secret*" -o -iname "*token*" \
  -o -iname "*.kdbx" -o -iname "*.keyx" \) -perm -o+r -ls 2>/dev/null
# Jeder Treffer ist eine weltlesbare Datei an einem Ort, wo Geheimnisse wohnen.
# Eine Schlüsseldatei mit Rechten 777 kann jeder Prozess des Users lesen:
# jeder Browser, jedes Spiel, jeder Installations-Hook eines Paketmanagers.

grep -rEil "api[_-]?key|token|secret|password" ~/.bashrc ~/.bash_aliases 2>/dev/null
# Treffer heißt anschauen. Geheimnisse gehören nicht in Dotfiles, denn die landen in Git.
```

### 4. VPN-Leak-Prüfung (bei VPN- und Torrent-Nutzung)

```bash
ss -tlnp | grep <torrent-port>
# So sieht kaputt aus:   0.0.0.0:46744
#   Der Client lauscht überall. Bei einem Tunnelabbruch läuft der Traffic
#   ungeschützt über die echte IP weiter.
# So sieht richtig aus:  10.x.x.x%wg0:46744
#   Der Client ist an das VPN-Interface gebunden. Ohne Tunnel gibt es keinen Traffic.
```

Die Bindung setzt man im Client. In qBittorrent zum Beispiel unter Einstellungen, Erweitert, Netzwerkschnittstelle.

Dann der Härtetest, denn "müsste halten" zählt nicht:

```bash
# Beispiel mit Mullvad. Killswitch an, Tunnel trennen, nachmessen:
mullvad lockdown-mode set on
mullvad disconnect
curl -4 -s --max-time 8 ifconfig.co || echo "BLOCKIERT, gut so"
mullvad connect && sleep 4 && curl -4 -s ifconfig.co   # wieder erreichbar, über die VPN-IP
```

### 5. Sudo- und Gruppen-Realität

```bash
groups
# Steht docker in der Liste, hat der User faktisch passwortloses root.
# Ein Container mit gemountetem Wurzelverzeichnis genügt dafür.
# Auf einer Einzelnutzer-Maschine kann man damit leben. Man muss es nur wissen:
# Jeder Code, der als dieser User läuft, kann root werden.

ls /etc/sudoers.d/
# Vergessene NOPASSWD-Dateien von alten Automatisierungs-Experimenten aufräumen.
```

Zur Passwort-Hygiene: Das Passwort hat in keiner Befehlszeile etwas verloren, auch nicht als Argument für `sudo -S`. Es landet sonst in der Shell-History, in Session-Logs und in Prozesslisten. Ist es doch passiert, hilft nur ein Passwortwechsel. Das Löschen der History-Zeile genügt nicht, denn Logs vergessen nicht.

### 6. Browser und Neustart-Schulden

```bash
apt list --upgradable 2>/dev/null | grep -Ei "firefox|chromium|brave"   # Browser sofort patchen
ls /var/run/reboot-required 2>/dev/null && echo "Reboot fällig"
sudo needrestart -b 2>/dev/null | tail -5
# needrestart zeigt Dienste, die nach Updates noch mit alten Bibliotheken im Speicher laufen.
```

## Typische Befunde und was du dagegen tust

**Keine Zeitsynchronisation:**
```bash
sudo apt install systemd-timesyncd
sudo timedatectl set-ntp true
timedatectl   # verifizieren: synchronized yes
```

**Passwort-Login bei SSH, obwohl Schlüssel eingerichtet sind:** Zuerst verifizieren, dass der eigene Schlüssel in `authorized_keys` steht und der Login damit funktioniert. Erst dann:

```bash
printf 'PasswordAuthentication no\n' | sudo tee /etc/ssh/sshd_config.d/50-keys-only.conf
sudo sshd -t                                  # Syntaxcheck vor dem Reload
sudo systemctl reload ssh
sudo sshd -T | grep -i passwordauth           # nachmessen
```

Auf einem Desktop mit lokalem Login kann man sich dabei nicht aussperren. Bei einem entfernten Server hält man eine zweite SSH-Session offen, bis der Schlüssel-Login nachweislich funktioniert.

**Weltlesbare Geheimnisse:**
```bash
chmod 600 <datei> && chmod 700 <verzeichnis>
```
Grundsätzlicher gefragt: Gehört die Schlüsseldatei überhaupt auf dieselbe Platte wie die Datenbank, die sie schützt? Ein externes Medium ist die sauberere Antwort.

**Torrent ohne Interface-Bindung:** Den Client zuerst beenden, sonst überschreibt er die Konfiguration beim nächsten Beenden wieder. Dann das Interface in den Einstellungen festnageln und den Härtetest fahren.

## Merksätze

1. `timedatectl` ist der billigste Sicherheitscheck der Welt. Fünf Sekunden, und "no" ist immer ein Befund.
2. Rechte auf Geheimnisse prüft man mit `find -perm -o+r` und nicht mit Vertrauen.
3. Ein Killswitch, der nie getestet wurde, existiert nicht.
4. Die docker-Gruppe ist root. Einmal verstehen und bewusst damit leben.
5. Passwörter gehören in keine Befehlszeile. History und Logs vergessen nie.
6. Reihenfolge bei der SSH-Härtung: Schlüssel rein, Schlüssel getestet, Passwort aus. Nie andersherum.
