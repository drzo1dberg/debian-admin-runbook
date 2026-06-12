# Security

**Why it matters:** The biggest security gaps on workstations are rarely spectacular. They are silent defaults nobody ever verified: a clock drifting without time sync, a key file readable by everyone, a torrent client listening on all interfaces despite a VPN. None of this announces itself. All of it is found in minutes once you know where to look.

## Inspection (read-only)

### 1. Time synchronization (30 seconds, huge leverage)

```bash
timedatectl
# "System clock synchronized: yes" and "NTP service: active" is the target state.
# Anything else is a finding.
```

Time services tend to get lost during system rebuilds. The clock then drifts unnoticed. The consequences surface in unexpected places: 2FA codes tolerate 30 to 90 seconds of skew, TLS validation and repository signature checks also depend on correct time.

### 2. SSH

```bash
sudo sshd -T | grep -Ei "passwordauthentication|permitrootlogin"
cat ~/.ssh/authorized_keys | awk '{print $1, $3}'
# Be able to explain every key in this list. Unknown keys are an alarm signal.
ls -la ~/.ssh
# Directory: 700. Private keys: 600. Anything else is wrong.
```

### 3. File permissions on secrets (the 777 check)

```bash
find ~ -maxdepth 3 \( -iname "*key*" -o -iname "*secret*" -o -iname "*token*" \
  -o -iname "*.kdbx" -o -iname "*.keyx" \) -perm -o+r -ls 2>/dev/null
# Every hit is a world-readable file in a place where secrets live.
# A key file with mode 777 is readable by every process of the user:
# every browser, every game, every package manager install hook.

grep -rEil "api[_-]?key|token|secret|password" ~/.bashrc ~/.bash_aliases 2>/dev/null
# A hit means: look at it. Secrets do not belong in dotfiles; dotfiles end up in git.
```

### 4. VPN leak check (when running VPN plus torrent)

```bash
ss -tlnp | grep <torrent-port>
# Broken looks like this:   0.0.0.0:46744
#   The client listens everywhere. When the tunnel drops, traffic continues
#   unprotected over the real IP.
# Correct looks like this:  10.x.x.x%wg0:46744
#   The client is bound to the VPN interface. No tunnel, no traffic.
```

Set the binding in the client itself, e.g. qBittorrent: Settings, Advanced, Network interface.

Then the hardening test, because "should hold" does not count:

```bash
# Example with Mullvad. Kill switch on, drop the tunnel, measure:
mullvad lockdown-mode set on
mullvad disconnect
curl -4 -s --max-time 8 ifconfig.co || echo "BLOCKED, as it should be"
mullvad connect && sleep 4 && curl -4 -s ifconfig.co   # reachable again, via VPN IP
```

### 5. sudo and group reality

```bash
groups
# docker in the list means de-facto passwordless root:
# a container with the root filesystem mounted is all it takes.
# Acceptable on a single-user machine, but know it:
# any code running as this user can become root.

ls /etc/sudoers.d/
# Clean up forgotten NOPASSWD files from old automation experiments.
```

Password hygiene: a password has no business on any command line, including as an argument to `sudo -S`. It ends up in shell history, session logs and process lists. If it happened anyway, rotate the password. Deleting the history line is not enough; logs do not forget.

### 6. Browsers and restart debt

```bash
apt list --upgradable 2>/dev/null | grep -Ei "firefox|chromium|brave"   # patch browsers immediately
ls /var/run/reboot-required 2>/dev/null && echo "reboot due"
sudo needrestart -b 2>/dev/null | tail -5
# needrestart lists services still running on pre-update libraries.
```

## Findings and fixes

**No time sync:**
```bash
sudo apt install systemd-timesyncd
sudo timedatectl set-ntp true
timedatectl   # verify: synchronized yes
```

**SSH allows passwords although keys are set up:** first verify your key is in `authorized_keys` and the key login works. Only then:

```bash
printf 'PasswordAuthentication no\n' | sudo tee /etc/ssh/sshd_config.d/50-keys-only.conf
sudo sshd -t                                  # syntax check BEFORE reload
sudo systemctl reload ssh
sudo sshd -T | grep -i passwordauth           # measure, do not assume
```

On a desktop with local login you cannot lock yourself out. On a remote server, keep a second SSH session open until key login is proven.

**World-readable secrets:**
```bash
chmod 600 <file> && chmod 700 <dir>
```
The deeper question: does the key file belong on the same disk as the database it protects? External media is the cleaner answer.

**Torrent without interface binding:** quit the client first (it rewrites its config on exit), pin the interface in the settings, run the hardening test.

## Rules of thumb

1. `timedatectl` is the cheapest security check in existence. Five seconds, and "no" is always a finding.
2. Permissions on secrets are verified with `find -perm -o+r`, not with trust.
3. A kill switch that was never tested does not exist.
4. The docker group is root. Understand it once, then live with it deliberately.
5. Passwords never belong on a command line. History and logs do not forget.
6. SSH hardening order: key in, key tested, password off. Never the other way around.
