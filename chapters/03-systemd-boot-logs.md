# systemd, Boot and Logs

**Why it matters:** A system can feel healthy for years while units fail in the background, a program crashes regularly or a tool floods the journal with tens of thousands of error lines. None of that opens a window on screen. If you never read the journal, you never learn about it. Boot time is the second blind spot: old installs accumulate waits and orphaned units that add seconds to minutes on every start.

## Inspection (read-only)

### 1. Overall state

```bash
systemctl is-system-running
# "running" is the target. "degraded" = at least one unit has failed.

systemctl --failed --no-legend          # system units
systemctl --user --failed --no-legend   # user units of your session
# Both lists must be empty.
```

### 2. Reading journal errors

```bash
journalctl -b -p err --no-pager | tail -50
# -b = current boot only, -p err = priority err and above.
# A message repeating hundreds of times is your candidate.
journalctl -b -p err --no-pager | wc -l   # order of magnitude
```

Important: without membership in `systemd-journal` or `adm`, a regular user only sees their own user journal. System errors stay invisible. Check with `id`, fix with:

```bash
sudo usermod -aG systemd-journal <user>   # effective at next login
```

### 3. Dissecting boot time

```bash
systemd-analyze
# Total, split into firmware, loader, kernel, userspace.

systemd-analyze blame | head -15
# Slowest units. Classic desktop offenders:
# NetworkManager-wait-online (waits for network, usually pointless without net mounts)
# fwupd-refresh (firmware metadata, rarely blocks the boot target).

systemd-analyze critical-chain
# The actually blocking path. Only what appears here truly delays boot.
```

### 4. Timer inventory

```bash
systemctl list-timers --no-pager
```

Check both directions. First: are the maintenance timers present that should exist (`apt-daily`, `fstrim`, `logrotate`, `e2scrub`)? Second: are timers running for things that do not exist? A typical finding is RAID check timers on systems without RAID. Verify with `cat /proc/mdstat`.

### 5. Crashes and core dumps

```bash
coredumpctl list --no-pager 2>/dev/null | tail -10
ls -la ~ | grep "^-.*core"
cat /proc/sys/kernel/core_pattern
```

If `core_pattern` contains only `core`, crash dumps land unmanaged as large files in whatever the working directory was. That is where they get overlooked. A core dump in `$HOME` is a message: some program crashed. `file core.*` tells you which. With `systemd-coredump` installed, dumps are captured centrally, rotated, and listed by `coredumpctl` with date and backtrace.

### 6. Orphaned and duplicate starts

```bash
systemctl list-unit-files --state=enabled --no-pager | less
# Units with never-met start conditions silently never start and only confuse.

ls /etc/xdg/autostart ~/.config/autostart 2>/dev/null
# Duplicate start paths (XDG autostart plus a systemd user unit for the same
# program) produce the typical scope errors in the user journal at every login.
```

## Findings and fixes

**Failed unit:**
```bash
systemctl status <unit>
journalctl -u <unit> -b --no-pager | tail -30
# Understand the cause first. Then repair, or disable deliberately.
```

**Journal flood from a single tool:** repair, update or remove the tool. A program logging the same error every 30 seconds writes millions of lines a year and buries real problems. Repetition patterns in the journal are the only way to spot it.

**Core dump found:**
```bash
file core.*                         # which program crashed?
sudo apt install systemd-coredump   # capture future crashes centrally
# Then delete the old dump. It has been read and served its purpose.
```

**Slow boot via wait-online:** if fstab has no network mounts and no service strictly needs network at boot:
```bash
sudo systemctl disable NetworkManager-wait-online.service
```

**Orphaned timers and units:**
```bash
sudo systemctl disable --now <unit-or-timer>
sudo systemctl mask <unit>          # if it could return as a dependency
```

## Rules of thumb

1. `systemctl --failed` and `is-system-running` are the system's pulse. Both belong in every inspection.
2. Without the `systemd-journal` group you see half the truth.
3. Repetition is the signal. One error is noise. The same error a thousand times is a finding.
4. A core dump is mail from a crashed program. Read it, then delete it.
5. `blame` lists suspects. `critical-chain` names culprits.
