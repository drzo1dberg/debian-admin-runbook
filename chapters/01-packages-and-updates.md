# Packages and Updates

**Why it matters:** Pending security updates are the quietest kind of risk. Nothing is broken, everything runs, so nobody looks. The worst offenders are packages left over from a previous Debian release: they will never receive security fixes again and no normal update routine flags them.

## Inspection (read-only)

### 1. What is pending, and how urgent?

```bash
sudo apt update
apt list --upgradable 2>/dev/null
# Read the source behind each package.
# "-security" = security update, apply now. Anything else = soon, no rush.
```

### 2. How often does this box actually get patched?

```bash
grep "Start-Date" /var/log/apt/history.log | tail -10
zgrep "Start-Date" /var/log/apt/history.log.*.gz 2>/dev/null | tail -10
# The gaps between dates are your real patch frequency.
# Monthly gaps mean security fixes sit unapplied for weeks.
```

### 3. Does the system patch itself?

```bash
dpkg -l unattended-upgrades 2>/dev/null | grep ^ii   # no output = finding
cat /etc/apt/apt.conf.d/20auto-upgrades 2>/dev/null   # both values "1" = active
```

Caution: the `apt-daily` and `apt-daily-upgrade` timers run even without the `unattended-upgrades` package. They only download metadata then. Checking the timers alone gives false confidence.

### 4. Zombie packages: installed, but no repo serves them

```bash
apt list '?obsolete' 2>/dev/null
```

The output falls into three buckets:

1. **Deliberate manual installs** (local .deb files). Fine, but updates are now your job, not apt's.
2. **Leftovers from the last release upgrade.** Recognizable by the old version suffix, e.g. `deb12u1` on a Debian 13 box. These never get CVE fixes again. Old Java runtimes and multimedia libraries are classic cases, and the latter are classic attack surface.
3. **Orphaned libraries.** Check with:

```bash
apt-cache rdepends --installed <pkg>
# Empty list = nothing depends on it = removable.
# An entry with a pipe like "|firefox-esr" is an alternative dependency:
# the program can use this lib but does not need it if the newer one is installed.
```

### 5. Third-party repo hygiene

```bash
ls /etc/apt/sources.list.d/
grep -rH "signed-by\|Signed-By" /etc/apt/sources.list.d/ | cut -c1-100
ls /etc/apt/trusted.gpg.d/
```

Every source in that list can install packages as root. Two questions per source:

1. Still needed? A common finding is a private repo added for a single program, long abandoned. Repos built for a different release (e.g. unstable packages on a stable system) are extra risk.
2. Is the key scoped? A key in `/etc/apt/trusted.gpg.d/` is trusted for all sources. Correct is a key under `/etc/apt/keyrings/` referenced via `signed-by` in its own source file.

### 6. Kernels and dead weight

```bash
dpkg -l 'linux-image-*' | grep ^ii        # more than 2-3 kernels: autoremove is due
apt-get -s autoremove | grep ^Remv        # simulation: what would go?
du -sh /var/cache/apt/archives            # multiple GB = apt clean never ran
```

### 7. Do not forget Flatpak

```bash
flatpak remote-ls --updates 2>/dev/null   # driver extensions need updates too
flatpak list --columns=application,installation | sort | uniq -c | sort -rn | head
# Duplicate entries in system and user = double maintenance, double disk.
```

## Findings and fixes

**Pending security updates:**
```bash
sudo apt full-upgrade
sudo needrestart        # lists services still running on old libraries
```

**No unattended-upgrades:**
```bash
sudo apt install unattended-upgrades apt-listchanges
printf 'APT::Periodic::Update-Package-Lists "1";\nAPT::Periodic::Unattended-Upgrade "1";\n' \
  | sudo tee /etc/apt/apt.conf.d/20auto-upgrades
sudo systemctl enable --now unattended-upgrades
```

**Release leftovers without support:** check `rdepends`, then purge. Confirm the current variant of the library is installed first; then no alternative dependency holds the old one either.

**Unscoped repo keys:** move the key to `/etc/apt/keyrings/` and reference it:
```
deb [signed-by=/etc/apt/keyrings/example.gpg] https://repo.example/ stable main
```

**Old kernels and cache:**
```bash
sudo apt autoremove --purge && sudo apt clean
# autoremove always keeps the running and the newest kernel.
```

**Flatpak:**
```bash
sudo flatpak update -y && sudo flatpak uninstall --unused -y
flatpak update --user -y && flatpak uninstall --user --unused -y
```

## Rules of thumb

1. Read the source behind every update. `-security` means today, not end of month.
2. `apt list '?obsolete'` is the confession after every release upgrade. Old version suffixes never get fixed again.
3. Every third-party repo is root access. Scope it or drop it.
4. Manual .deb installs have no update subscription. You are the subscription.
5. Simulation is free. `apt-get -s` belongs before every remove and autoremove.
