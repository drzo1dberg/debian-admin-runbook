# Dual-Boot: CachyOS Alongside Debian

**Why it matters:** A dual-boot pairs two distributions with opposite jobs on one set of hardware. Debian is the stable daily driver for coding and browsing where surprises are unwelcome. CachyOS is an Arch based, rolling, performance tuned system for gaming, the latest toolchains, and hardware that wants a newer kernel. The pairing is useful but cheap to get wrong. Two failure modes cause most of the pain. The first is a bootloader fight where two systems both try to own the boot menu. The second is the real time clock conflict where each boot shifts the other system's clock by the timezone offset. Both are silent. Both are avoidable with a plan. The guiding idea: a dual-boot is two systems sharing one set of hardware, so whatever they share is a contract. The shared surface is the risk surface.

This chapter is a theoretical setup walkthrough. Treat the partitioning steps as destructive and gate them behind a tested backup (chapter 6).

## Inspection (read-only pre-flight)

Run this before touching any partition. It changes nothing and decides whether the machine is ready for a second system. `scripts/dualboot-preflight.sh` automates the whole list.

### 1. Firmware mode

```bash
[ -d /sys/firmware/efi ] && echo "UEFI" || echo "legacy BIOS"
```

Both systems must boot the same way. Modern UEFI with GPT is the target. A mixed setup where one side is legacy and the other is UEFI is a recurring source of unbootable installs.

### 2. Secure Boot state

```bash
mokutil --sb-state 2>/dev/null            # "SecureBoot enabled" or "disabled"
```

CachyOS kernels are not signed for Secure Boot out of the box. Two clean options exist. Disable Secure Boot in firmware, or sign the bootloader and kernels yourself with `sbctl`. Decide now, because a half configured Secure Boot setup boots one system and blocks the other.

### 3. ESP inventory

```bash
findmnt /boot/efi /efi /boot 2>/dev/null   # where is the EFI System Partition?
df -h /boot/efi 2>/dev/null                # how much free space?
ls /boot/efi/EFI 2>/dev/null               # which boot entries already live there?
```

The ESP is the single most shared object in a dual-boot. A 100 MB to 260 MB ESP is tight for two distributions worth of kernels and initramfs images. Aim for 512 MB or more. If the existing ESP is small and full, that is a finding to resolve before install, not after.

### 4. Disk layout and free space

```bash
lsblk -f                                   # disks, filesystems, mount points
sudo parted -l                             # partition table type and gaps (root needed)
```

The partition table must be GPT for a clean UEFI dual-boot. Locate the space CachyOS will use. Either unallocated space already exists, or an existing partition has to shrink. Note the exact device path of every disk so the installer cannot target the wrong one.

### 5. Current bootloader and boot order

```bash
bootctl status 2>/dev/null | head -20      # systemd-boot present?
ls /boot/grub 2>/dev/null                  # GRUB present?
efibootmgr -v 2>/dev/null                   # firmware boot entries and their order
```

Establish who owns the menu today. After the second install, exactly one owner should remain, fixed at the top of the firmware boot order.

### 6. Real time clock convention

```bash
timedatectl | grep -i "RTC in local"        # target: "RTC in local TZ: no"
```

The clock must be in UTC. This single value is the seed of the clock conflict fix in the next section.

### 7. Backup gate

A repartition is the most destructive step in this entire runbook. Confirm a current backup exists and that a restore test has passed (chapter 6). Without that, stop here.

## Findings and fixes (the build)

### A. Partition plan

GPT, UEFI, one shared ESP. A robust layout:

- **ESP** at `/boot/efi`, 512 MB to 1 GB, shared by both systems. Never let the second installer reformat it.
- **Debian root**, untouched.
- **CachyOS root**, its own partition. Btrfs is the CachyOS default and unlocks snapshots, so prefer it.
- **Optional shared data partition** for files both systems read, formatted ext4 or btrfs.

Do not share one `/home` between the two systems. Same user ID, two different sets of application versions, and config schemas from a newer GNOME or KDE on CachyOS will corrupt the state the older Debian versions expect. Two separate roots, each with its own `/home`. Share documents through a dedicated data partition or a synced repo, never through a shared dotfile tree. This is the dual-boot face of the drift problem in chapter 8.

Shrink a partition only from a context that does not have it mounted read write, for example a GParted live session, and only after the backup gate.

### B. Who owns the boot menu

This is the central decision. Two clean models exist. Pick one and commit to it.

**Model 1: one GRUB owns the menu.** Usually Debian's GRUB, because Debian stays stable and installed. After CachyOS is in place, on Debian:

```bash
sudo apt install os-prober
sudo sed -i 's/^#\?GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
sudo update-grub                            # detects CachyOS and adds an entry
```

**Model 2: a neutral menu via systemd-boot or Limine.** CachyOS can install systemd-boot, GRUB, or Limine. systemd-boot and Limine read loader entries from the ESP, so both systems drop their own entries and no `os-prober` scan is needed. This is simpler on a rolling system where kernels change often.

Whichever model you choose, set the owner first in the firmware boot order and leave it there:

```bash
sudo efibootmgr -o 0002,0001,0000           # owner entry first
```

The fight happens only when two bootloaders both insist on being default. One owner, one fixed order, no fight.

### C. The real time clock conflict

The symptom is a clock that jumps by the timezone offset on every OS switch. The fix is to put both systems on UTC. Run once on each side:

```bash
sudo timedatectl set-local-rtc 0            # store the hardware clock in UTC
```

With both on UTC, NTP keeps them consistent and the jump disappears. One line per system.

### D. Installing CachyOS

Verify before trust, the same ethos as the rest of this runbook:

```bash
sha256sum cachyos.iso                       # compare to the published checksum
# verify the GPG signature on the checksum file as well
```

Write the verified image to a USB stick and boot it. The Calamares installer offers an install alongside option, but manual partitioning is safer here. Target the prepared free space, mount the existing ESP without formatting it, and choose Btrfs for the root. In the bootloader step, match the decision from section B.

### E. CachyOS maintenance with the inspection mindset

The discipline from the Debian chapters carries over. Only the tools change. `scripts/cachyos-postinstall-check.sh` checks the items below from inside CachyOS.

| Concept | Debian | CachyOS (Arch) |
|---|---|---|
| Full upgrade | `apt update && apt upgrade` | `sudo pacman -Syu` |
| With AUR | not applicable | `paru -Syu` |
| List pending | `apt list --upgradable` | `checkupdates` (pacman-contrib) |
| Remove orphans | `apt autoremove` | `sudo pacman -Rns $(pacman -Qtdq)` |
| Clean cache | `apt clean` | `paccache -r` |
| List manual installs | `apt-mark showmanual` | `pacman -Qe` |
| Logs and units | journalctl, systemctl | identical |

The Arch cardinal rule: never partial upgrade. `pacman -Sy <pkg>` without a full `-Syu` mixes package versions and breaks the system. Always upgrade the whole system at once.

First boot tasks:

```bash
sudo cachyos-rate-mirrors                    # rank the optimized mirrors
/lib/ld-linux-x86-64.so.2 --help | grep supported   # confirm x86-64-v3 or v4 support
sudo pacman -Syu                             # full sync before anything else
```

Keep a fallback kernel. The CachyOS kernel with the BORE scheduler is the daily driver, but rolling kernels occasionally regress. Install `linux-lts` as a parachute so a bad kernel is one boot menu entry away from recovery.

Snapshots are not optional on a rolling system. CachyOS sets up Btrfs with snapper. Pair it with `limine-snapper-sync` or `grub-btrfs` so a pre upgrade snapshot is bootable from the menu. This is the Arch equivalent of Timeshift and the precondition for upgrading without fear.

After a long gap between updates, refresh the keyrings first, otherwise signature checks fail:

```bash
sudo pacman -Sy archlinux-keyring cachyos-keyring
sudo pacman -Su
```

### F. Keeping the two systems from fighting

The shared surface needs ongoing attention.

- **ESP space.** Kernels accumulate on both sides. Debian autoremoves old kernels. On CachyOS keep `linux-cachyos` plus `linux-lts` and prune the rest. Watch `df -h /boot/efi`.
- **Boot order.** A firmware update can reset the boot order. Re-check `efibootmgr -v` after any BIOS update and restore the owner to the top.
- **Update discipline differs by design.** Debian may patch itself with unattended-upgrades. A rolling system must not. CachyOS gets a human and a snapshot before every upgrade.
- **Dotfiles across both.** One repo, the symlink model, and guards keyed on the system. Detect the OS in shell startup and branch where needed (chapter 8):

```bash
. /etc/os-release
[ "$ID" = "cachyos" ] && export EDITOR=nvim   # example of an OS specific branch
```

### Recovery recipes

A dual-boot bootloader will break eventually. Boot a live USB, mount the affected root and the ESP, enter a chroot, and reinstall the owner's bootloader.

```bash
# Example for a GRUB owner. Adjust device paths.
sudo mount /dev/<root-partition> /mnt
sudo mount /dev/<esp-partition> /mnt/boot/efi
for d in dev proc sys run; do sudo mount --rbind /$d /mnt/$d; done
sudo chroot /mnt
grub-install --target=x86_64-efi --efi-directory=/boot/efi
update-grub
exit
```

If the ESP filled mid upgrade, prune old kernels from the live environment before retrying. If the firmware lost the boot entry, recreate it with `efibootmgr -c`.

## Rules of thumb

1. One ESP, one owner. Fix the firmware boot order and never let two bootloaders both claim default.
2. Both clocks in UTC. `set-local-rtc 0` on each side ends the time jump dance.
3. Separate roots, separate `/home`. Share data through a partition or a repo, never through one home directory.
4. Repartition only behind a tested backup. It is the most destructive step in the book.
5. Rolling never patches itself. CachyOS gets a human and a snapshot before every upgrade. Debian may automate.
6. Keep an LTS kernel as a parachute. The bleeding edge regresses and a known good kernel is the way back in.
7. Verify both boots before you call it done. No test, no claim.
