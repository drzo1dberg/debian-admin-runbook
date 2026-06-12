# Dotfiles und Konfigurations-Drift

**Warum das wichtig ist:** Wer seine Dotfiles als lose Kopien zwischen Maschinen hin und her kopiert, hat nach wenigen Monaten zwei Wahrheiten. Die lokale Config und das Repo laufen still auseinander, bis niemand mehr weiß, welche Version die richtige ist. Dazu kommt das Identitätsproblem: Wer auf Arbeits- und Privatmaschinen mit Git arbeitet, committet mit der falschen E-Mail, sobald die Default-Identität auf der falschen Maschine landet.

## Was du prüfst (die Inspektion)

### 1. Gibt es überhaupt eine einzige Wahrheit?

```bash
ls -la ~/.bashrc ~/.bash_aliases ~/.tmux.conf ~/.gitconfig 2>/dev/null
# Symlinks in ein Repo-Verzeichnis bedeuten: eine Wahrheit. Gut.
# Echte Dateien bedeuten: lose Kopien. Drift ist nur eine Frage der Zeit.

find ~ -maxdepth 3 -name .git -type d 2>/dev/null | grep -v -e .cache -e .local
# Welche Repos gibt es lokal überhaupt?
```

### 2. Wie groß ist die Drift?

```bash
cd <dotfiles-repo> && git fetch
git log --oneline -3 ; git log --oneline -3 origin/main
diff ~/.bashrc <repo>/.bashrc | head -30
# Faustregel aus der Praxis: Unterscheiden sich lokale Datei und Repo-Stand
# um ein Mehrfaches der Zeilenzahl, ist die lokale Version meist ein
# eingefrorener Altstand von vor Monaten.
```

### 3. Lokale Schätze: Was ist nirgends versioniert?

```bash
ls ~/.config/alacritty ~/.config/tmux ~/.bash_functions 2>/dev/null
ls /usr/local/bin/
# Selbst geschriebene Funktionen, Terminal-Configs und Eigenbau-Skripte
# leben oft nur auf einer Maschine. Ein Plattentod löscht sie ersatzlos.
```

### 4. Tote Configs und kaputte Verweise

```bash
# Konfiguriert, aber nicht installiert? Beides prüfen:
ls ~/.config/<tool>/ 2>/dev/null && command -v <tool>
# Typische Befunde: ein Prompt-Tool mit gepflegter Config, das keine Shell lädt,
# oder eine Terminal-Config, die als Startbefehl einen nicht installierten
# Multiplexer aufruft und das Terminal damit unbenutzbar macht.

# Aliase, die Standardwerkzeuge verschatten:
type tr ls cat 2>/dev/null | grep -v "ist /"
# Ein Alias namens tr macht das coreutils-tr in jeder interaktiven Pipe kaputt.
```

### 5. Git-Identitäten

```bash
git config user.email                  # im Home: Welche Identität ist Default?
cd <beliebiges-repo> && git config user.email   # und hier?
grep -A2 includeIf ~/.gitconfig 2>/dev/null
```

Die Frage dahinter: Was passiert auf einer neuen Maschine nach dem Klonen der Dotfiles? Wenn die `.gitconfig` im Repo eine konkrete Identität als Default setzt, bekommt jede Maschine diese Identität. Commits auf der Privatmaschine laufen dann mit der Arbeits-Mail oder umgekehrt.

### 6. Force-Push-Lagen erkennen

```bash
git fetch
# Meldet die Ausgabe "forced update", wurde die Remote-History umgeschrieben.
# Ab hier gilt: nichts pullen und nichts resetten, bevor ein Backup-Branch existiert.
```

## Typische Befunde und was du dagegen tust

**Lose Kopien:** Auf das Symlink-Modell umstellen. Ein Install-Skript im Repo verlinkt die Dateien ins Home und sichert vorhandene Originale weg:

```bash
ln -sf "$repo/.bashrc" "$HOME/.bashrc"
# Datei editieren heißt ab jetzt Repo editieren. Danach nur noch committen und pushen.
```

**Identitäts-Risiko:** Die `.gitconfig` im Repo enthält keinen `[user]`-Block. Stattdessen includet sie eine maschinen-lokale Datei, die das Install-Skript passend zur Maschine anlegt:

```ini
[include]
    path = ~/.gitconfig.local
[includeIf "gitdir:~/github-repos/<privat-account>/"]
    path = ~/.gitconfig-privat
```

Fehlt die lokale Datei, verweigert Git den Commit mit einer Identitätsfehlermeldung. Lautes Scheitern ist hier gewollt und besser als die falsche Mail in der History.

**Maschinen-Unterschiede in einer Config:** Guards statt Kopien. Beispiele:

```bash
# WSL-spezifische Teile schalten sich auf nativen Systemen selbst ab:
[ -n "$WSL_DISTRO_NAME" ] && export BROWSER="$HOME/.local/bin/wsl-open"
```
```tmux
# tmux: Theme nur laden, wenn es auf dieser Maschine existiert:
if-shell '[ -f ~/.config/tmux/plugins/theme/theme.tmux ]' {
  run ~/.config/tmux/plugins/theme/theme.tmux
}
```

**Force-Push aufholen:** Immer in dieser Reihenfolge:

```bash
git branch backup-$(date +%F)          # 1. Backup-Branch auf den lokalen Stand
git fetch                              # 2. holen
git reset --hard origin/main           # 3. auf den neuen Stand setzen
git diff backup-$(date +%F) --stat     # 4. prüfen, was lokal anders war
# Nur-lokale Dateien gezielt aus dem Backup-Branch zurückholen und committen.
# Vorher prüfen, ob sie im neuen Stand unter anderem Namen weiterleben.
```

**Lokale Schätze:** Ins Repo aufnehmen. Auch Eigenbau-Skripte aus `/usr/local/bin` und Funktionsdateien gehören versioniert, sonst existieren sie genau einmal.

**Tote Configs:** Entscheiden statt horten. Entweder das Tool aktivieren oder Config samt Binary entfernen. Eine gepflegte Config ohne aktives Tool ist Drift in Reinform.

## Merksätze

1. Symlink statt Kopie. Eine Wahrheit pro Datei, auf allen Maschinen.
2. Die Identität gehört nie in die geteilte `.gitconfig`. Maschinen-lokale Include-Datei plus lautes Scheitern, wenn sie fehlt.
3. "forced update" beim Fetch heißt: Stopp. Erst Backup-Branch, dann weiterdenken.
4. Guards schlagen Maschinen-Forks. Eine Config mit Bedingungen statt zwei driftender Varianten.
5. Was nur auf einer Maschine existiert, existiert zur Hälfte.
