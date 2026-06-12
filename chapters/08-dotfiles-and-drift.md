# Dotfiles and Configuration Drift

**Why it matters:** Copying dotfiles between machines produces two truths within months. The local config and the repo silently diverge until nobody knows which version is correct. On top of that comes the identity problem: anyone using git on both work and private machines will commit with the wrong email as soon as the default identity lands on the wrong box.

## Inspection (read-only)

### 1. Is there a single source of truth at all?

```bash
ls -la ~/.bashrc ~/.bash_aliases ~/.tmux.conf ~/.gitconfig 2>/dev/null
# Symlinks into a repo directory: one truth. Good.
# Regular files: loose copies. Drift is only a matter of time.

find ~ -maxdepth 3 -name .git -type d 2>/dev/null | grep -v -e .cache -e .local
# Which repos exist locally in the first place?
```

### 2. How big is the drift?

```bash
cd <dotfiles-repo> && git fetch
git log --oneline -3 ; git log --oneline -3 origin/main
diff ~/.bashrc <repo>/.bashrc | head -30
# Field rule: if local file and repo differ by a multiple of their line count,
# the local version is usually a frozen state from months ago.
```

### 3. Local treasures: what is versioned nowhere?

```bash
ls ~/.config/alacritty ~/.config/tmux ~/.bash_functions 2>/dev/null
ls /usr/local/bin/
# Hand-written functions, terminal configs and self-built scripts often live
# on a single machine. A dead disk erases them without replacement.
```

### 4. Dead configs and broken references

```bash
# Configured but not installed? Check both sides:
ls ~/.config/<tool>/ 2>/dev/null && command -v <tool>
# Typical findings: a prompt tool with a polished config that no shell loads,
# or a terminal config whose startup command calls a multiplexer that is not
# installed, rendering the terminal unusable.

# Aliases shadowing core utilities:
type tr ls cat 2>/dev/null | grep -v "is /"
# An alias named tr breaks coreutils tr in every interactive pipe.
```

### 5. Git identities

```bash
git config user.email                  # in $HOME: which identity is the default?
cd <some-repo> && git config user.email   # and here?
grep -A2 includeIf ~/.gitconfig 2>/dev/null
```

The underlying question: what happens on a fresh machine after cloning the dotfiles? If the repo's `.gitconfig` hardcodes an identity as default, every machine inherits it. Commits on the private box then carry the work email, or vice versa.

### 6. Recognizing force-push situations

```bash
git fetch
# If the output says "forced update", the remote history was rewritten.
# From here on: no pull, no reset, until a backup branch exists.
```

## Findings and fixes

**Loose copies:** switch to the symlink model. An install script in the repo links files into `$HOME` and backs up existing originals:

```bash
ln -sf "$repo/.bashrc" "$HOME/.bashrc"
# Editing the file now means editing the repo. Commit and push, done.
```

**Identity risk:** the repo's `.gitconfig` carries no `[user]` block. It includes a machine-local file which the install script creates per machine:

```ini
[include]
    path = ~/.gitconfig.local
[includeIf "gitdir:~/github-repos/<private-account>/"]
    path = ~/.gitconfig-private
```

If the local file is missing, git refuses to commit with an identity error. Loud failure is intended and beats the wrong email in history.

**Machine differences inside one config:** guards instead of copies. Examples:

```bash
# WSL-specific parts disable themselves on native systems:
[ -n "$WSL_DISTRO_NAME" ] && export BROWSER="$HOME/.local/bin/wsl-open"
```
```tmux
# tmux: load a theme only if it exists on this machine:
if-shell '[ -f ~/.config/tmux/plugins/theme/theme.tmux ]' {
  run ~/.config/tmux/plugins/theme/theme.tmux
}
```

**Catching up after a force push:** always in this order:

```bash
git branch backup-$(date +%F)          # 1. backup branch on the local state
git fetch                              # 2. fetch
git reset --hard origin/main           # 3. move to the new state
git diff backup-$(date +%F) --stat     # 4. inspect what was different locally
# Restore local-only files selectively from the backup branch and commit them.
# First check whether they live on in the new state under a different name.
```

**Local treasures:** put them in the repo. Self-built scripts from `/usr/local/bin` and function files belong under version control, otherwise they exist exactly once.

**Dead configs:** decide instead of hoard. Either activate the tool or remove config and binary. A polished config without an active tool is drift in its purest form.

## Rules of thumb

1. Symlink over copy. One truth per file, on every machine.
2. Identity never goes into the shared `.gitconfig`. Machine-local include file plus loud failure when it is missing.
3. "forced update" on fetch means stop. Backup branch first, thinking second.
4. Guards beat machine forks. One config with conditions instead of two drifting variants.
5. Whatever exists on only one machine half exists.
