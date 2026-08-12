# Dotfiles

## Overview

This repository installs the shared pieces of a portable command-line environment for macOS and Debian/Ubuntu Linux. The setup entry point validates a plan, shows exactly what it will change, asks for one confirmation, then installs declared packages, pinned shell plugins, fonts, and repository-owned symlinks.

The repository keeps identity and machine-specific settings out of version control. Local choices belong in `$HOME/.zshrc.local` and `$HOME/.gitconfig.local`.

## Features

- Zsh configuration files with path, history, aliases, completion, key bindings, fzf integration, Powerlevel10k, zsh-autosuggestions, and zsh-syntax-highlighting.
- Git defaults for `main`, color, pruning fetches, fast-forward-only pulls, and automatic upstream setup on push.
- Kitty configuration using JetBrains Mono Nerd Font, a dark terminal palette, scrollback, clipboard mappings, and font-size shortcuts.
- Pinned plugin installs under `${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles/plugins`.
- JetBrains Mono Nerd Font install on Debian/Ubuntu with SHA-256 archive verification. macOS uses the Homebrew cask.
- Explicit manifests for packages, plugins, and symlinks.
- Doctor checks after setup.

## Supported Platforms

- macOS with Homebrew available or installable.
- Debian or Ubuntu Linux with `apt`, `sudo`, and standard package tools.

Other operating systems and Linux distributions are rejected before setup mutates files.

## Prerequisites

- Bash, Git, and a POSIX-like shell environment.
- Internet access for package installation, plugin clones, and font download when those items are missing.
- Permission to use the platform package manager.
- On Debian/Ubuntu, `sudo` access for `apt-get`.

## Install

Clone the repository, inspect the plan, then run setup:

```bash
git clone https://github.com/shaqhacks/dotfiles.git "$HOME/.dotfiles"
cd "$HOME/.dotfiles"
bash setup.sh --dry-run
bash setup.sh
```

To skip package-manager changes and only apply repository-managed configuration:

```bash
bash setup.sh --skip-packages
```

To opt in to changing the login shell after setup validates the Zsh path:

```bash
bash setup.sh --set-default-shell
```

## What Setup Changes

`setup.sh` supports these public flags:

```text
--dry-run
--skip-packages
--set-default-shell
--help
```

The setup flow is:

1. Parse flags and detect the platform.
2. Validate every manifest entry.
3. Print the planned package, plugin, font, link, and shell actions.
4. Ask once: `Apply this dotfiles plan?`
5. Apply package changes unless `--skip-packages` was provided.
6. Clone or update pinned plugins.
7. Install the Nerd Font on Debian/Ubuntu when missing.
8. Back up conflicting link destinations and create symlinks for `.zshrc`, `.gitconfig`, `.config/kitty/kitty.conf`, and `.p10k.zsh`.
9. Change the login shell only with `--set-default-shell`.
10. Run doctor checks.

The rollback boundary is package installation. Package-manager changes are not rolled back by this repository. Link changes are journaled during the link phase and rolled back if a later link operation fails.

## Usage

Run a setup health check through the public entry point:

```bash
bash setup.sh --dry-run
```

Run the doctor script directly after installation:

```bash
bash script/doctor.sh
```

Run the local verification suite:

```bash
bash tests/run.sh
shellcheck -x setup.sh script/*.sh tests/*.sh
shfmt -d setup.sh script tests
git diff --check
```

## Repository Structure

- `setup.sh` is the supported installer entry point.
- `manifest/links.conf` declares repository files and their `$HOME` destinations.
- `manifest/packages.debian` and `manifest/packages.macos` declare platform packages.
- `manifest/plugins.conf` pins plugin repositories and commits.
- `script/` contains setup helpers.
- `zsh/`, `system/`, `git/`, `kitty/`, and `powerlevel10k/` contain tracked configuration.
- `tests/` contains the shell test harness and policy checks.

## Customization

Use local override files for values that should not be committed.

For Zsh, create `$HOME/.zshrc.local` for local aliases, exports, and prompt tweaks. It is sourced after zsh-autosuggestions and before zsh-syntax-highlighting.

For Git identity, start from the example file:

```bash
cp "$HOME/.dotfiles/git/gitconfig.local.example" "$HOME/.gitconfig.local"
```

Then edit `$HOME/.gitconfig.local` with local identity, signing, credential, and editor settings. The tracked `.gitconfig` includes this local file.

## Updates

Pull repository changes, inspect the new plan, then rerun setup:

```bash
cd "$HOME/.dotfiles"
git pull --ff-only
bash setup.sh --dry-run
bash setup.sh
```

Plugin updates happen only when `manifest/plugins.conf` changes to a new pinned commit. Package updates remain the responsibility of the platform package manager.

## Recovery/Uninstall

When setup needs to replace an existing destination, it prints a backup root like:

```text
backup root: $HOME/.local/share/dotfiles/backups/20260811123456.12345
```

The backup directory preserves home-relative paths. To restore one backed-up file, remove the repository symlink and move the backup into place:

```bash
backup_root="$HOME/.local/share/dotfiles/backups/20260811123456.12345"
rm "$HOME/.gitconfig"
mv "$backup_root/.gitconfig" "$HOME/.gitconfig"
```

Use the same pattern for nested files:

```bash
backup_root="$HOME/.local/share/dotfiles/backups/20260811123456.12345"
rm "$HOME/.config/kitty/kitty.conf"
mkdir -p "$HOME/.config/kitty"
mv "$backup_root/.config/kitty/kitty.conf" "$HOME/.config/kitty/kitty.conf"
```

To uninstall repository-managed links without restoring backups:

```bash
rm "$HOME/.gitconfig"
rm "$HOME/.zshrc"
rm "$HOME/.config/kitty/kitty.conf"
rm "$HOME/.p10k.zsh"
```

Optional cleanup for cloned plugins and local font files:

```bash
rm -rf "${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles/plugins"
rm -rf "${XDG_DATA_HOME:-$HOME/.local/share}/fonts/JetBrainsMonoNerdFont"
```

Remove `$HOME/.zshrc.local` and `$HOME/.gitconfig.local` only when those local files are no longer needed.

## Troubleshooting

- Run `bash setup.sh --dry-run` to see the validated plan without changing files.
- Run `bash script/doctor.sh` to check platform packages, pinned plugins, fonts, and symlink targets.
- If setup rejects a plugin checkout, inspect its origin, working tree, and commit under `${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles/plugins`.
- If Zsh history is disabled, check ownership and mode of `${XDG_STATE_HOME:-$HOME/.local/state}/zsh`; it must be owned by the current user and mode `700`.
- If Kitty displays remote prompts incorrectly over SSH, install Kitty terminfo on the remote host or use a terminal type available there. Kitty can transfer terminfo with its SSH kitten, and remote hosts that lack Kitty terminfo may need a fallback `TERM` value.
- If the prompt font is wrong, confirm that JetBrains Mono Nerd Font is installed and selected by Kitty.

## Security

- The setup script validates manifests before using them.
- Plugin and font URLs must use HTTPS.
- Plugins are pinned to exact 40-character Git commits.
- Debian/Ubuntu font downloads are verified with SHA-256 before extraction.
- Archive extraction rejects unsafe font member paths.
- Conflicting symlink destinations are moved to a backup directory, not deleted.
- The repository does not store SSH keys, API tokens, Git identity, private domains, or machine-specific absolute paths.

Review `bash setup.sh --dry-run` before applying changes. The printed plan is the source of truth for the current machine.

## Acknowledgements

This layout is inspired by topic-oriented dotfiles repositories and uses upstream projects directly: Zsh, Git, Kitty, Powerlevel10k, zsh-autosuggestions, zsh-syntax-highlighting, fzf, JetBrains Mono Nerd Font, ShellCheck, and shfmt.
