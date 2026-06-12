# Storage and Data Hygiene

**Why it matters:** Dead weight rarely arrives as one big chunk. It arrives as sediment: Docker images under forgotten containers, package caches never emptied, browser caches, core dumps in the home directory, old installers in Downloads. On neglected systems this quickly sums to tens of gigabytes. Worse than the disk usage is what gets overlooked: a container in a restart loop burns CPU for months, and a core dump points to a real crash nobody noticed.

## Inspection (read-only)

### 1. Overview first, then drill down

```bash
df -h | grep -v tmpfs                 # how full is what?
du -xsh ~/* ~/.cache ~/.local 2>/dev/null | sort -rh | head -20
# -x stays on one filesystem and does not descend into foreign mounts.
# sort -rh puts the biggest items on top. Then drill into the largest entry:
du -xsh ~/.cache/* 2>/dev/null | sort -rh | head -10
```

### 2. Docker: the zombie farm (mandatory if Docker is installed)

```bash
docker ps -a
# The STATUS column is the inspection point. A container showing
# "Restarting (1) 30 seconds ago" with a creation date months ago is stuck
# in an endless loop: permanent CPU load and log spam.
docker system df          # images, containers, volumes: TOTAL vs RECLAIMABLE
```

### 3. The usual suspects

```bash
du -sh /var/cache/apt/archives        # multiple GB = apt clean never ran
journalctl --disk-usage
ls -la ~ | grep -E "^-.*core|debug\.log|\.deb$|\.AppImage$"
# Core dumps, debug logs and installers do not belong in the home root.
find ~/Downloads -type f -mtime +180 -size +50M -exec ls -lh {} \; 2>/dev/null
# Installers, ISOs and tarballs older than six months are re-downloadable, hence deletable.
du -sh ~/.local/share/Trash 2>/dev/null
```

### 4. Toolchain duplication

```bash
dpkg -l rustc cargo 2>/dev/null | grep ^ii
rustup toolchain list 2>/dev/null
du -sh ~/.rustup ~/.cargo ~/.npm-global ~/go 2>/dev/null
npm ls -g --depth=0 2>/dev/null
```

Typical findings: a language installed twice, once via apt and once via its own manager. Or the global npm tree still holds an old install of a tool that has long moved elsewhere. Duplicates cost gigabytes and blur which version actually runs.

### 5. Flatpak weight

```bash
flatpak list --app | wc -l
du -sh /var/lib/flatpak ~/.local/share/flatpak 2>/dev/null
# Many GB for a handful of apps points to orphaned or duplicated runtimes.
# Data of uninstalled apps:
ls ~/.var/app/ | while read a; do flatpak info "$a" >/dev/null 2>&1 || echo "orphaned: $a"; done
```

### 6. The btrfs snapshot trap

```bash
sudo timeshift --list 2>/dev/null | tail -8
```

With btrfs snapshots on the system disk, deleted files are not freed immediately. The snapshots of the last days still reference the data. `df` barely moves although you just deleted dozens of gigabytes. The space returns once the daily snapshots have rotated out. Not a bug: copy-on-write semantics. Admins who do not know this keep deleting in panic.

## Findings and fixes

**Docker zombies:**
```bash
docker inspect <container> --format '{{index .Config.Labels "com.docker.compose.project.working_dir"}}'
# Check which project the container belonged to. Then:
docker rm -f <container...>
docker rmi <image>            # targeted beats prune -a,
docker volume rm <volume>     # which also deletes images you will pull again next week
```

**Caches:** safe to delete immediately, they regenerate:
```bash
sudo apt clean
pip cache purge
npm cache clean --force
rm -rf ~/.cache/thumbnails
# Browser caches only under disk pressure: rebuilding them costs browsing speed.
```

**Core dump in $HOME:** read first, delete second. `file core.*` names the crashed program. Details in the systemd chapter.

**Installer sediment:** delete what is re-downloadable. Large media files belong on the data disk, not permanently in Downloads.

**Toolchain duplication:** pick one source per language. For Rust: keep rustup, purge the apt packages, drop redundant toolchains via `rustup toolchain uninstall`.

## Rules of thumb

1. `docker ps -a` belongs in every inspection. The STATUS column reveals zombies that `docker ps` hides.
2. Deleting caches is free. Deleting data is final. Look inside before `rm`.
3. A core dump is a message, not garbage.
4. On btrfs with snapshots, `df` lies for a few days. Deleted becomes free only after snapshot rotation.
5. One toolchain source per language.
