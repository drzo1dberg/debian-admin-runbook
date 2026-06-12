# Dienste und offene Ports

**Warum das wichtig ist:** Auf vernachlässigten Systemen sammeln sich lauschende Dienste wie Werkzeug in einer Garage. Webserver, Dateifreigaben, Monitoring-Suiten und Experimente von vor zwei Jahren laufen weiter, obwohl niemand sie mehr nutzt. Jeder lauschende Dienst ist Angriffsfläche, kostet RAM und Bootzeit. Häufig dienen solche Dienste sogar einem Netz, das es nach einem Umzug oder Router-Wechsel gar nicht mehr gibt.

## Was du prüfst (die Inspektion)

### 1. Wer lauscht? Die wichtigste Frage des Kapitels

```bash
sudo ss -tulnp
# So liest man die Ausgabe: Local Address:Port plus ganz rechts der Prozess.
#   127.0.0.1:631        lauscht nur lokal. Harmlos.
#   0.0.0.0:445          lauscht auf allen Interfaces. Wer soll da zugreifen?
#   10.x.x.x%wg0:46744   ist an ein einzelnes Interface gebunden. So sieht Absicht aus.
```

Die Regel: Zu jeder Zeile mit `0.0.0.0` oder `[::]` muss man in einem Satz sagen können, was der Dienst ist und wer ihn nutzt. Gelingt das nicht, ist es ein Befund.

Ohne root zeigt `ss` keine fremden Prozessnamen. Bei einem unbekannten Port hilft:
```bash
sudo ss -tlnp '( sport = :4330 )'
# In der Praxis entpuppen sich solche Ports oft als Teil vergessener Suiten,
# etwa als Logger eines nie genutzten Monitoring-Stacks.
```

### 2. Was ist alles enabled?

```bash
systemctl list-unit-files --state=enabled --no-pager
systemctl --user list-unit-files --state=enabled --no-pager
# Die Liste liest man wie einen Kontoauszug: jeden Posten erklären können.
# User-Units nicht vergessen. Streaming-Tools und Sync-Dienste leben oft dort.
```

### 3. Vor dem Abschalten: reinschauen (der wichtigste Abschnitt)

Niemals nach Dienstname purgen. Erst nachsehen, was der Dienst tatsächlich tut:

```bash
# Webserver: Hostet er etwas Echtes? Ist er Reverse-Proxy für etwas, das gebraucht wird?
ls /etc/apache2/sites-enabled/
grep -r "ProxyPass\|DocumentRoot" /etc/apache2/sites-enabled/
# Steht dort nur der Debian-Stock-VHost mit der Default-Startseite, kann der Server weg.
# Steht dort ein ProxyPass auf einen lokalen Port, ist der Webserver der Eingang
# zu einem anderen Dienst. Ein Purge würde diesen Dienst von außen abschalten.

cat /etc/exports                          # NFS: Was wird an wen exportiert?
testparm -s 2>/dev/null | grep -A3 '^\['  # Samba: Welche Freigaben?
grep ^media_dir /etc/minidlna.conf 2>/dev/null   # DLNA: Welche Verzeichnisse?
sudo mailq                                # Mailserver: Hängt echte Mail in der Queue?
```

Ein häufiges Muster: NFS, Samba und DLNA exportieren dieselben Verzeichnisse an ein altes Subnetz. Drei Dienste für denselben Zweck, den längst eine modernere Lösung erfüllt.

### 4. Firewall: Schutzschicht oder Museum?

```bash
sudo firewall-cmd --list-all              # alternativ: sudo nft list ruleset | less
```

Drei Fragen:

1. Ist die Firewall überhaupt aktiv?
2. Passt jede Freigabe zu einem Dienst, der behalten werden soll?
3. Referenzieren Regeln alte IPs oder Subnetze? Solche Regeln sind Fossilien vergangener Netze und der deutlichste Hinweis auf Config-Drift.

```bash
grep -n "192.168" /etc/hosts              # Drift versteckt sich auch hier
```

## Typische Befunde und was du dagegen tust

**Dienst wird nicht mehr gebraucht.** Zweistufig vorgehen, mit Bedenkzeit:

```bash
sudo systemctl disable --now apache2      # Stufe 1: aus. Eine Woche damit leben.
sudo apt purge --autoremove apache2       # Stufe 2: weg, samt Konfiguration.
```

`disable --now` ist in einer Sekunde reversibel. `purge` löscht auch die Configs unter `/etc/`. Bei Unsicherheit auf Stufe 1 bleiben.

**Dienst ist enabled, startet aber nie.** Das passiert bei Units mit nie erfüllten Start-Bedingungen und bei Timern für Hardware, die nicht existiert (etwa RAID-Checks ohne RAID):

```bash
sudo systemctl disable --now <unit>
sudo systemctl mask <unit>
# mask ist härter als disable: Die Unit kann auch nicht als Abhängigkeit mitgestartet werden.
```

**Dienst lauscht auf 0.0.0.0, wird aber nur lokal gebraucht.** In der Konfiguration des Dienstes an `127.0.0.1` oder ein konkretes Interface binden. Die Firewall davor ist Schicht zwei und nicht Schicht eins. Fällt sie weg oder setzt jemand kurz eine Freigabe, soll darunter nichts Ungewolltes warten.

**Alte Firewall-Regeln:**
```bash
sudo firewall-cmd --permanent --remove-rich-rule='<die alte Regel>'
sudo firewall-cmd --permanent --remove-port=<port>/tcp
sudo firewall-cmd --reload && sudo firewall-cmd --list-all
```

**Verwaiste User-Dienste:**
```bash
systemctl --user disable --now <unit>
```

## Merksätze

1. Jede `0.0.0.0`-Zeile in `ss -tulnp` braucht einen Satz Begründung. Kein Satz heißt Befund.
2. Erst reinschauen, dann abschalten. Configs lesen kostet zwei Minuten. Einen versteckten Reverse-Proxy purgen kostet einen Abend.
3. Disable heute, purge nächste Woche. Die Bedenkzeit ist der Rollback-Plan.
4. Config-Drift findet man in Firewall-Regeln und in /etc/hosts. Alte IPs sind Fossilien.
5. Die Firewall entschuldigt keine lauschenden Leichen. Binden oder beenden.
