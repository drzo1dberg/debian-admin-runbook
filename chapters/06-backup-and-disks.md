# Backup and Disk Health

**Why it matters:** The most expensive inspection result is almost always the same: there is no real backup. Snapshots on the same disk feel like a backup but are only a rollback mechanism. If the disk dies, the snapshots die with it. The second half of the truth: without SMART monitoring there is no early warning before disk death. Combined, this means valuable data exists exactly once and nobody gets warned before it disappears.

## Inspection (read-only)

### 1. Stocktaking: what exists how many times?

Use the 3-2-1 rule as the yardstick: three copies, two different media, one off-site. Few private setups fully reach it. But every deviation should be a conscious decision, not an accident.

```bash
lsblk -f                          # which disks and filesystems exist?
df -h | grep -v tmpfs             # what is mounted where, how full?
# Then answer per data set: where is the second copy?
```

Backup archaeology helps. Old rsync logs reveal what was synced when, where to, and in which direction. A frequent finding: the last manual backup is months old, and entire data sets have no second copy at all. The critical subsets are personal photos and documents; unlike media collections they cannot be re-acquired.

### 2. Classifying snapshots honestly

```bash
sudo timeshift --list 2>/dev/null | tail -8
grep backup_device /etc/timeshift/timeshift.json 2>/dev/null
```

If the snapshot target is the system disk itself, Timeshift protects against broken updates and config accidents. It does not protect against disk failure, theft or ransomware. You want both: snapshots for fast rollback, plus a real backup on different media.

### 3. Does an automated backup exist, and did it run?

```bash
systemctl --user list-timers | grep -i backup
systemctl list-timers | grep -i backup
# A timer that exists but never fired is a finding.
# No timer at all is the more common finding.
```

### 4. SMART: how healthy are the disks?

```bash
sudo smartctl -H -A /dev/nvme0n1
sudo smartctl -H -A /dev/sda
```

Reading guide for the key values:

- **NVMe:** `Percentage Used` shows wear. `Available Spare` should be near 100 percent. `Media and Data Integrity Errors` must be 0.
- **HDD:** `Reallocated_Sector_Ct`, `Current_Pending_Sector` and `Offline_Uncorrectable` must be 0. Rising values are the precursor of failure. `UDMA_CRC_Error_Count` above 0 points to cabling problems.
- **SATA SSD:** `Wear_Leveling_Count` shows remaining life as a normalized value. `Total_LBAs_Written` times sector size gives written volume; compare it to the vendor's TBW rating.

```bash
systemctl is-active smartmontools 2>/dev/null
# inactive or not installed means: nobody is watching the disks.
```

## Findings and fixes

### No backup: set up Borg (the standard recipe)

Borg deduplicates, compresses and encrypts. Target is a different physical disk.

```bash
sudo apt install borgbackup
mkdir -p /path/to/other/disk/borg-home ~/.config/borg
( umask 077; tr -dc 'A-Za-z0-9' </dev/urandom | head -c 48 > ~/.config/borg/passphrase )
chmod 600 ~/.config/borg/passphrase
export BORG_PASSCOMMAND='cat ~/.config/borg/passphrase'
borg init --encryption=repokey-blake2 /path/to/other/disk/borg-home
borg key export /path/to/other/disk/borg-home ~/.config/borg/key-backup
```

The passphrase and the exported key belong in an additional external place: password manager or paper. Without them the repo is worthless in an emergency.

The backup script excludes everything re-acquirable: caches, game libraries, toolchains, trash, downloads. A home directory beyond 100 GB often shrinks to a fraction. Automate with a systemd user timer (`OnCalendar=daily`, `Persistent=true`). For the timer to run without an active session, enable lingering:

```bash
loginctl enable-linger $USER
systemctl --user enable --now backup-home.timer
```

### The restore test (without it, everything is hope)

```bash
borg list /path/to/repo                          # archives exist?
borg list /path/to/repo::<archive> | head        # content plausible?
cd /tmp && borg extract /path/to/repo::<archive> home/<user>/.bashrc
# Actually restore one real file and look at it. Only now it is a backup.
```

### No disk monitoring: set up smartd

```bash
sudo apt install smartmontools
# Extend the DEVICESCAN line in /etc/smartd.conf with self-tests:
# DEVICESCAN -a -n standby,q -s (S/../.././02|L/../../6/03) -W 4,45,55 -m root -M exec /usr/share/smartmontools/smartd-runner
# Meaning: daily short test at 02:00, long test Saturdays 03:00, temperature warnings.
sudo systemctl enable --now smartmontools
```

Notification caveat: `-m root` sends mail. Without an MTA the warning evaporates. Add a script under `/etc/smartmontools/run.d/` that uses a desktop notification or another channel instead.

### Single copies of valuable data

Until a second disk or an external solution exists, mitigate: mirror the irreplaceable subsets (photos, documents, own projects) to another internal disk. Not a full backup, but it defuses total loss.

## Rules of thumb

1. Snapshots on the same disk are a rollback, not a backup.
2. A backup without a restore test is hope with a timestamp.
3. Passphrase and key export belong somewhere outside the backup.
4. SMART values of 0 for reallocated and pending sectors are the target. Rising values are the early warning smartd exists for.
5. Back up the irreplaceable first. Movies can be re-acquired, photos cannot.
