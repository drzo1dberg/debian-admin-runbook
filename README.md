# Debian Admin Runbook: The Annual Inspection

A hands-on runbook for inspecting and maintaining Debian systems. The model is a car service: full assessment first, then a cost estimate, then the repair. Built for admins who inherit or neglect systems and want a repeatable procedure instead of ad-hoc fixes.

## Principles

**1. Estimate first, repair second.**
The inspection is strictly read-only. Collect findings, rank them by severity, estimate effort. Decide what to fix only after the full picture exists. Never see-and-fix: what looks like dead weight may be in active use. A file's mtime tells you more than its name.

**2. Reversible beats permanent.**
Move configs and data to an archive directory (e.g. `~/attic-<date>/`) instead of deleting. Delete after a week of not missing anything. Only caches may be deleted immediately; they regenerate. Before any `git reset` or `git pull` on a drifted repo, create a backup branch.

**3. Understand before you disable.**
Before purging any service, read its config. A web server may be a forgotten experiment or the reverse proxy in front of something you need. You only know after you look.

**4. Simulate before you execute.**
`apt-get -s remove <pkg> --autoremove` shows the full dependency chain before anything happens. A handful of forgotten packages can anchor hundreds.

**5. No test, no claim.**
"Should be fine" is not a finding. A VPN kill switch exists once you have disconnected the tunnel and verified traffic is blocked. A backup exists once a restore test has passed.

## Inspection workflow

1. **Inspect (read-only):** run `scripts/inspect.sh`, then walk the per-chapter checks. Record findings.
2. **Estimate:** rank findings by severity (critical, high, medium, low) and effort. Bundle into work packages.
3. **Repair:** work the packages in order. Security first. Never postpone backup. Cosmetics last.
4. **Sign-off:** `systemctl --failed` empty. `apt list --upgradable` empty. Hardening tests passed. Every open port accounted for.

## Chapters

| # | Chapter | Core question |
|---|---|---|
| 1 | [Packages and updates](chapters/01-packages-and-updates.md) | Is the system current, and does it patch itself? |
| 2 | [Services and ports](chapters/02-services-and-ports.md) | What is listening, and is it still needed? |
| 3 | [systemd, boot, logs](chapters/03-systemd-boot-logs.md) | Is anything failing silently? |
| 4 | [Storage and hygiene](chapters/04-storage-and-hygiene.md) | Where are the gigabytes buried? |
| 5 | [Security](chapters/05-security.md) | Time sync, SSH, secret permissions, VPN leaks |
| 6 | [Backup and disks](chapters/06-backup-and-disks.md) | Do the data survive a dead disk? |
| 7 | [Desktop remnants](chapters/07-desktop-remnants.md) | Cleaning up after a desktop environment switch |
| 8 | [Dotfiles and drift](chapters/08-dotfiles-and-drift.md) | One source of truth for configs on every machine |

Plus [`scripts/inspect.sh`](scripts/inspect.sh): a read-only quick check to start with.

## The 15-minute checklist

```bash
# System and time
cat /etc/os-release | head -2; uname -r; uptime
timedatectl | grep -E "synchronized|NTP"          # must show "yes" and "active"

# Updates
sudo apt update -qq && apt list --upgradable 2>/dev/null | wc -l
dpkg -l unattended-upgrades 2>/dev/null | grep -c ^ii   # 1 = automation exists

# Services and ports
systemctl --failed --no-legend                     # empty is the target
ss -tulnp 2>/dev/null | grep -v 127.0.0.1          # account for every line

# Docker zombies
docker ps -a 2>/dev/null | grep -i restarting

# Disk and corpses
df -h / ; du -xsh ~/.cache /var/cache/apt 2>/dev/null
ls -la ~ | grep -E "core\.|debug\.log|\.deb$"      # none of this belongs in $HOME

# Backup reality
systemctl --user list-timers | grep -i backup      # does a timer exist, did it run?
sudo smartctl -H /dev/nvme0n1 /dev/sda 2>/dev/null | grep -i result
```

Anything red: open the matching chapter.

## Recurring findings in the wild

These patterns show up on neglected systems again and again. All of them are silent. None of them throw errors. That is what makes them dangerous.

- **No time sync installed.** The clock drifts unnoticed until 2FA codes and TLS validation start failing. One-line fix, often undetected for a year.
- **Key files with mode 777.** Every process of the user can read the second factor of the password database.
- **Containers stuck in a restart loop for months.** Constant CPU load plus gigabytes of dead images. Only visible via `docker ps -a`, which nobody runs.
- **Snapshots on the same disk mistaken for backup.** That is a rollback mechanism. It does not survive disk failure. Valuable data then exists exactly once.
- **Torrent client listening on all interfaces despite a VPN.** Without interface binding, traffic leaks over the real IP the moment the tunnel drops.
- **A dozen network services for a LAN that no longer exists.** Firewall rules and exports pointing at old subnets reveal the drift.
- **Dotfiles as loose copies.** Local configs and the repo silently diverge until nothing matches.

## Cadence

- **Weekly, automated:** unattended-upgrades, smartd, backup timers. Set up once, then allowed to be forgotten.
- **Monthly, five minutes:** the checklist above.
- **Yearly or after every major rebuild:** the full inspection, chapter by chapter.
