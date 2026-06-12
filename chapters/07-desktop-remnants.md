# Desktop Remnants

**Why it matters:** Switching desktop environments, e.g. KDE to GNOME, leaves two kinds of residue. At runtime, old daemons, portals or a second display manager may keep running. In the package database and the home directory, hundreds of packages and config files of the old environment pile up. The system still works. But it drags along hundreds of megabytes, default applications point to programs that no longer exist, and every debugging session suffers from the fog of dead configs.

## Inspection (read-only)

### 1. Runtime check: is the old environment still alive somewhere?

```bash
ps aux | grep -Ei 'akonadi|baloo|kwallet|kded|kioslave' | grep -v grep
# Example patterns for KDE remnants. Empty output is the target.

cat /etc/X11/default-display-manager
systemctl is-active gdm3 sddm lightdm 2>/dev/null
# Exactly one display manager may be active. Is the old one still installed?

dpkg -l | grep xdg-desktop-portal
# Only the portals of the current environment should be installed. A stale
# portal can take precedence and open dialogs of the wrong environment.

ls ~/.config/autostart /etc/xdg/autostart 2>/dev/null
# Anything from the old world still autostarting?
```

### 2. Finding package anchors: what holds the dependency tail?

After a switch, dozens of library packages of the old environment usually remain. They hang on a few anchors, typically small manually installed tools.

```bash
dpkg -l | grep -Eic 'kde|plasma|kf6'      # order of magnitude
apt-mark showmanual | grep -Ei 'kde|plasma'
# Manually marked packages are the anchors. autoremove never touches them.

apt-get -s remove <anchor1> <anchor2> --autoremove | grep -c ^Remv
# The simulation shows the full tail before anything happens.
# A handful of small packages can anchor far more than a hundred others.
```

### 3. The crucial safeguard: is it still in use?

Before removing any suspected remnant, check usage traces:

```bash
ls -la ~/.config/<related-file>
# The mtime tells the truth. A file modified last week belongs to a
# program used last week.
```

A classic example is an accessibility tool of the old environment. It looks like junk and is indispensable to the user. When in doubt, ask or keep.

### 4. The config graveyard in $HOME

```bash
ls ~/.config | grep -Ei '^k|plasma|kde' | wc -l       # KDE example
du -sh ~/.cache 2>/dev/null
ls ~/.local/share | grep -Ei '^k|plasma|kde'
```

### 5. Default applications and theming

```bash
xdg-mime query default inode/directory
xdg-mime query default text/plain
grep "org.kde" ~/.config/mimeapps.list 2>/dev/null
# Do defaults point at .desktop files that no longer exist?
ls /usr/share/applications/ | grep <missing-app>

gsettings get org.gnome.desktop.interface icon-theme
gsettings get org.gnome.desktop.interface cursor-theme
# Typical post-rebuild finding: a cursor theme set as icon theme.
# The system silently falls back to a default theme.
```

## Findings and fixes

**Packages of the old environment:** simulate, then remove:
```bash
apt-get -s remove <anchors...> --autoremove | less    # read the Remv list!
sudo apt purge <anchors...> && sudo apt autoremove --purge
```

**Config residue in $HOME:** the attic method, reversible instead of final:
```bash
mkdir -p ~/attic-$(date +%F)/{config,local-share}
mv ~/.config/<old-file> ~/attic-$(date +%F)/config/
# Per file, first verify the owning app is really uninstalled.
# After a problem-free week the attic may go.
```

Caches of the old environment may be deleted immediately. They regenerate if something still runs.

**Dead defaults in mimeapps.list:** keep a copy, then repoint entries to existing applications:
```bash
xdg-mime default org.gnome.Nautilus.desktop inode/directory
xdg-mime default org.gnome.TextEditor.desktop text/plain
```

**Wrong theme entries:**
```bash
gsettings set org.gnome.desktop.interface icon-theme 'Adwaita'
```

**Residue in /etc:** config directories of uninstalled display managers and services (`/etc/sddm.conf.d` and the like) are pure cosmetics after the package purge and can go.

## Rules of thumb

1. Check runtime first, then packages, then configs. In that order.
2. Manually marked small packages are the anchors of the tail. `apt-mark showmanual` finds them.
3. A config's mtime beats any assumption. Recently modified means recently used.
4. Move configs, delete caches. Reversible beats final.
5. After cleanup, verify the defaults. Dead .desktop entries only surface when the wrong editor opens.
