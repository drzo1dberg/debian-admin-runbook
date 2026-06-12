# Desktop-Altlasten

**Warum das wichtig ist:** Ein Wechsel der Desktop-Umgebung, etwa von KDE zu GNOME, hinterlässt zwei Arten von Resten. Auf der Laufzeitebene können alte Dienste, Portale oder ein zweiter Display-Manager weiterlaufen. In der Paketdatenbank und im Home-Verzeichnis sammeln sich hunderte Pakete und Konfigurationsdateien der alten Umgebung. Das System funktioniert trotzdem. Aber es schleppt hunderte Megabyte mit, Standard-Anwendungen zeigen auf Programme, die es nicht mehr gibt, und bei jeder Fehlersuche stört der Nebel aus toten Configs.

## Was du prüfst (die Inspektion)

### 1. Laufzeit-Check: Lebt die alte Umgebung noch irgendwo?

```bash
ps aux | grep -Ei 'akonadi|baloo|kwallet|kded|kioslave' | grep -v grep
# Beispiel für KDE-Reste. Leere Ausgabe ist das Ziel.

cat /etc/X11/default-display-manager
systemctl is-active gdm3 sddm lightdm 2>/dev/null
# Genau ein Display-Manager darf aktiv sein. Ist der alte noch installiert?

dpkg -l | grep xdg-desktop-portal
# Nur die Portale der aktuellen Umgebung sollten installiert sein.
# Ein altes Portal kann sich vordrängen und Dialoge der falschen Umgebung öffnen.

ls ~/.config/autostart /etc/xdg/autostart 2>/dev/null
# Startet hier noch etwas aus der alten Welt?
```

### 2. Paket-Anker finden: Woran hängt der Rattenschwanz?

Nach dem Wechsel bleiben oft dutzende Bibliothekspakete der alten Umgebung installiert. Sie hängen an wenigen Ankern, meist kleinen manuell installierten Werkzeugen.

```bash
dpkg -l | grep -Eic 'kde|plasma|kf6'      # Größenordnung des Problems
apt-mark showmanual | grep -Ei 'kde|plasma'
# Manuell markierte Pakete sind die Anker. autoremove rührt sie nie an.

apt-get -s remove <anker1> <anker2> --autoremove | grep -c ^Remv
# Die Simulation zeigt den kompletten Rattenschwanz, bevor irgendetwas passiert.
# An einer Handvoll Kleinpaketen können weit über hundert Pakete hängen.
```

### 3. Die wichtigste Vorsichtsmaßnahme: Wird das noch benutzt?

Vor dem Entfernen jedes vermeintlichen Altlasten-Pakets die Nutzungsspuren prüfen:

```bash
ls -la ~/.config/<zugehörige-datei>
# Die Änderungszeit verrät die Wahrheit. Eine Datei, die letzte Woche geändert wurde,
# gehört zu einem Programm, das letzte Woche benutzt wurde.
```

Ein klassisches Beispiel sind Barrierefreiheits-Werkzeuge der alten Umgebung. Sie sehen aus wie Müll und sind für den User unverzichtbar. Im Zweifel nachfragen oder behalten.

### 4. Config-Friedhof im Home

```bash
ls ~/.config | grep -Ei '^k|plasma|kde' | wc -l       # Beispiel für KDE
du -sh ~/.cache 2>/dev/null
ls ~/.local/share | grep -Ei '^k|plasma|kde'
```

### 5. Standard-Anwendungen und Theming

```bash
xdg-mime query default inode/directory
xdg-mime query default text/plain
grep "org.kde" ~/.config/mimeapps.list 2>/dev/null
# Zeigen Defaults auf .desktop-Dateien, die es nicht mehr gibt?
ls /usr/share/applications/ | grep <vermisste-app>

gsettings get org.gnome.desktop.interface icon-theme
gsettings get org.gnome.desktop.interface cursor-theme
# Typischer Befund nach Umbauten: ein Cursor-Theme ist als Icon-Theme eingetragen.
# Das System fällt dann still auf ein Fallback-Theme zurück.
```

## Typische Befunde und was du dagegen tust

**Pakete der alten Umgebung:** Erst simulieren, dann entfernen:
```bash
apt-get -s remove <anker...> --autoremove | less    # Remv-Liste durchlesen!
sudo apt purge <anker...> && sudo apt autoremove --purge
```

**Config-Reste im Home:** Die Altlasten-Methode, reversibel statt endgültig:
```bash
mkdir -p ~/altlasten-$(date +%F)/{config,local-share}
mv ~/.config/<alte-datei> ~/altlasten-$(date +%F)/config/
# Vorher pro Datei prüfen, ob die zugehörige App wirklich deinstalliert ist.
# Nach einer Woche ohne Probleme darf das Archiv weg.
```

Caches der alten Umgebung darf man dagegen sofort löschen. Sie regenerieren sich, falls doch noch etwas läuft.

**Tote Defaults in mimeapps.list:** Erst eine Kopie sichern, dann die Einträge auf existierende Anwendungen umbiegen:
```bash
xdg-mime default org.gnome.Nautilus.desktop inode/directory
xdg-mime default org.gnome.TextEditor.desktop text/plain
```

**Falsche Theme-Einträge:**
```bash
gsettings set org.gnome.desktop.interface icon-theme 'Adwaita'
```

**Reste in /etc:** Konfigurationsverzeichnisse deinstallierter Display-Manager und Dienste (`/etc/sddm.conf.d` und ähnliche) sind nach dem Purge der Pakete reine Kosmetik und können weg.

## Merksätze

1. Erst die Laufzeit prüfen, dann die Pakete, dann die Configs. In dieser Reihenfolge.
2. Manuell markierte Kleinpakete sind die Anker des Rattenschwanzes. `apt-mark showmanual` findet sie.
3. Die Änderungszeit einer Config schlägt jede Vermutung. Was kürzlich geändert wurde, wird benutzt.
4. Configs verschieben, Caches löschen. Reversibel schlägt endgültig.
5. Nach dem Aufräumen die Defaults prüfen. Tote .desktop-Einträge fallen erst auf, wenn der falsche Editor aufgeht.
