# Services and Ports

**Why it matters:** Neglected systems accumulate listening services like a garage accumulates tools. Web servers, file shares, monitoring suites and two-year-old experiments keep running long after anyone uses them. Every listener is attack surface, RAM and boot time. Often these services even serve a LAN that stopped existing after a move or a router swap.

## Inspection (read-only)

### 1. What is listening? The key question of this chapter

```bash
sudo ss -tulnp
# How to read it: Local Address:Port plus the process on the right.
#   127.0.0.1:631        local only. Harmless.
#   0.0.0.0:445          listening on ALL interfaces. Who is supposed to connect?
#   10.x.x.x%wg0:46744   bound to one interface (here: VPN). That is what intent looks like.
```

The rule: for every line with `0.0.0.0` or `[::]` you must be able to state in one sentence what the service is and who uses it. If you cannot, it is a finding.

Without root, `ss` hides other users' process names. For an unknown port:
```bash
sudo ss -tlnp '( sport = :4330 )'
# Such ports often turn out to be parts of forgotten suites,
# e.g. the logger of a monitoring stack nobody ever used.
```

### 2. What is enabled?

```bash
systemctl list-unit-files --state=enabled --no-pager
systemctl --user list-unit-files --state=enabled --no-pager
# Read it like a bank statement: explain every entry.
# Do not skip user units. Streaming and sync tools usually live there.
```

### 3. Before disabling: look inside (the most important section)

Never purge by service name. Check what the service actually does first:

```bash
# Web server: serving anything real? Reverse proxy for something you need?
ls /etc/apache2/sites-enabled/
grep -r "ProxyPass\|DocumentRoot" /etc/apache2/sites-enabled/
# Only the Debian stock vhost with the default index page: safe to remove.
# A ProxyPass to a local port: the web server is the entrance to another
# service, and purging it would cut that service off from the outside.

cat /etc/exports                          # NFS: what is exported to whom?
testparm -s 2>/dev/null | grep -A3 '^\['  # Samba: which shares?
grep ^media_dir /etc/minidlna.conf 2>/dev/null   # DLNA: which directories?
sudo mailq                                # MTA: real mail stuck in the queue?
```

A common pattern: NFS, Samba and DLNA all export the same directories to an old subnet. Three services for one purpose that a newer solution already covers.

### 4. Firewall: protection layer or museum?

```bash
sudo firewall-cmd --list-all              # or: sudo nft list ruleset | less
```

Three questions:

1. Is it active at all?
2. Does every allowance match a service you intend to keep?
3. Do any rules reference old IPs or subnets? Those are fossils of past networks and the clearest sign of config drift.

```bash
grep -n "192.168" /etc/hosts              # drift hides here too
```

## Findings and fixes

**Service no longer needed.** Two stages, with a cooling-off period:

```bash
sudo systemctl disable --now apache2      # stage 1: off. Live with it for a week.
sudo apt purge --autoremove apache2       # stage 2: gone, configs included.
```

`disable --now` reverses in one second. `purge` also deletes `/etc/` configs. When unsure, stay at stage 1.

**Enabled but never starts.** Happens with units whose start conditions are never met, and with timers for hardware that does not exist (RAID checks without RAID):

```bash
sudo systemctl disable --now <unit>
sudo systemctl mask <unit>
# mask is stronger than disable: the unit cannot be pulled in as a dependency either.
```

**Listening on 0.0.0.0 but only needed locally.** Bind it to `127.0.0.1` or a specific interface in the service config. The firewall in front is layer two, not layer one. If it drops or someone "quickly" opens a port, nothing unwanted should be waiting underneath.

**Stale firewall rules:**
```bash
sudo firewall-cmd --permanent --remove-rich-rule='<old rule>'
sudo firewall-cmd --permanent --remove-port=<port>/tcp
sudo firewall-cmd --reload && sudo firewall-cmd --list-all
```

**Orphaned user services:**
```bash
systemctl --user disable --now <unit>
```

## Rules of thumb

1. Every `0.0.0.0` line in `ss -tulnp` needs one sentence of justification. No sentence, no pass.
2. Look inside before you switch off. Reading configs costs two minutes; purging a hidden reverse proxy costs an evening.
3. Disable today, purge next week. The cooling-off period is the rollback plan.
4. Config drift lives in firewall rules and /etc/hosts. Old IPs are fossils.
5. A firewall does not excuse listening corpses. Bind them or end them.
