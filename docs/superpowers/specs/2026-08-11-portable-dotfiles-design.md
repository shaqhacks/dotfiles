# Portable Dotfiles Repository Design

## Purpose

Create a new public `shaqhacks/dotfiles` repository for setting up a command-line environment on macOS and Debian/Ubuntu Linux. The repository will retain the topic-oriented clarity of Holman's dotfiles while using explicit manifests for deterministic, reviewable installation.

The project will be a fresh implementation informed by the legacy command-line guide and the reusable portions of the existing `~/.dotfiles` checkout. It will not copy the old repository history, personal identity, private paths, credentials, employer tooling, or obsolete application topics.

## Goals

- Provide one safe-interactive `setup.sh` entry point.
- Support macOS and Debian/Ubuntu with shared configuration and small platform adapters.
- Manage repository-owned configuration through explicit symlinks.
- Back up conflicting files before changing them.
- Make repeat runs idempotent.
- Configure Zsh, Kitty, Git, JetBrains Mono Nerd Font, Powerlevel10k, fzf, autosuggestions, syntax highlighting, and file-type colors.
- Keep machine-specific and identity-specific settings outside the repository.
- Document installation, customization, recovery, and troubleshooting in the root README.
- Verify behavior on both supported operating-system families before publishing.

## Non-goals

- Migrating the legacy Atom, Ruby, Heroku, Xcode, Vim, or miscellaneous helper-script topics.
- Supporting employer-specific tools, internal completion scripts, or private network resources.
- Supporting Windows, unsupported Linux distributions, or shells other than Zsh in the first version.
- Installing secrets, SSH keys, API tokens, Git identity, or machine-specific paths.
- Acting as a general-purpose plugin manager.

## Architecture

The repository will use a Holman-inspired hybrid architecture:

1. Top-level topic directories group related configuration.
2. Zsh fragments follow naming conventions for human readability.
3. Explicit manifests define packages and source-to-destination links.
4. The setup program never discovers and executes arbitrary `install.sh` or `*.symlink` files.

Proposed layout:

```text
dotfiles/
├── README.md
├── LICENSE
├── setup.sh
├── manifest/
│   ├── links.conf
│   ├── packages.macos
│   ├── packages.debian
│   └── plugins.conf
├── script/
│   ├── common.sh
│   ├── macos.sh
│   ├── debian.sh
│   └── doctor.sh
├── zsh/
│   ├── zshrc.symlink
│   ├── path.zsh
│   ├── config.zsh
│   ├── keybindings.zsh
│   └── completion.zsh
├── system/
│   ├── aliases.zsh
│   └── colors.zsh
├── git/
│   ├── gitconfig.symlink
│   └── gitconfig.local.example
├── kitty/
│   └── kitty.conf
├── powerlevel10k/
│   └── p10k.zsh
├── fonts/
│   └── checksums
└── tests/
```

`setup.sh` is the only public entry point. Files under `script/` provide narrowly scoped internal functions. Manifest files are data, not shell programs: the setup program validates their grammar before using them.

## Configuration Loading

`zsh/zshrc.symlink` will locate the repository from its own resolved path instead of assuming a username or clone location. It will load configuration in deterministic phases:

1. Powerlevel10k instant-prompt cache, when present.
2. Topic path fragments.
3. shared shell options, history, aliases, functions, and key bindings.
4. completion initialization and fzf integration.
5. zsh-autosuggestions.
6. zsh-syntax-highlighting last, as required upstream.
7. optional `~/.zshrc.local` overrides.

Interactive settings remain in `.zshrc`; the repository will not add `.zshenv` without a concrete non-interactive requirement because `.zshenv` runs for every Zsh invocation.

## Setup Flow

The default invocation is safe-interactive:

1. Detect macOS or Debian/Ubuntu and reject unsupported platforms before changes.
2. Parse arguments and validate every manifest entry.
3. Check required commands, destinations, package-manager availability, and network requirements.
4. Print one complete execution plan and request confirmation.
5. Install missing platform packages.
6. Install or update pinned Zsh dependencies under `${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles/`.
7. Back up conflicting destinations into one timestamped directory under `${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/backups/`.
8. Create the declared symlinks.
9. Optionally change the login shell only when `--set-default-shell` is supplied.
10. Run the doctor checks and print a concise result and recovery path.

Supported flags:

- `--dry-run`: print the validated plan without mutation.
- `--skip-packages`: configure files without package installation.
- `--set-default-shell`: opt in to changing the login shell after installation.
- `--help`: document usage and supported platforms.

The script will not provide a default unattended mode. Automated verification can use isolated test helpers rather than weakening the user-facing confirmation contract.

## Package and Dependency Strategy

Core applications use platform package managers where practical:

- macOS: Homebrew formulae and casks.
- Debian/Ubuntu: `apt` packages.

If Homebrew is missing, the execution plan will explicitly disclose that setup will download the official installer into a temporary file and execute it. The single run confirmation covers that action. Remote content will not be piped directly into a shell.

Powerlevel10k, zsh-autosuggestions, and zsh-syntax-highlighting will be installed from their upstream Git repositories at revisions declared in `manifest/plugins.conf`. A mismatched existing repository origin causes a failure rather than an overwrite. Updates occur only when the manifest revision changes.

The design intentionally uses zsh-syntax-highlighting instead of fast-syntax-highlighting because its upstream installation guidance, maintenance story, Debian packaging, and required load ordering are clearer.

fzf will be installed through the platform package manager. Its shell integration fragment will detect the modern `fzf --zsh` interface and use documented distro integration files only when necessary for older packaged versions.

JetBrains Mono Nerd Font will be installed through the Homebrew cask on macOS. Debian/Ubuntu will receive a pinned Nerd Fonts release in the user's font directory with SHA-256 verification followed by a font-cache refresh.

Kitty will use the platform package manager when available. Its configuration target is `${XDG_CONFIG_HOME:-$HOME/.config}/kitty/kitty.conf`. The README will explain Kitty terminfo and shell-integration considerations for SSH.

GNU/Linux will generate `LS_COLORS` with `dircolors`. macOS will use GNU coreutils' `gdircolors` and GNU `ls` when installed, while retaining compatible native `LSCOLORS` behavior as a fallback.

## Git Configuration

The tracked Git configuration will contain only portable defaults, such as a `main` initial branch, color behavior, and conservative pull/push defaults. It will include `~/.gitconfig.local` for identity and machine-specific settings.

Setup may offer to copy `git/gitconfig.local.example` to `~/.gitconfig.local`, but it will not collect or commit a name or email. Complex shell-pipeline aliases will be excluded because quoting and environment dependencies make them brittle.

## Safety and Recovery

- A manifest preflight completes before package or link mutations begin.
- Correct existing symlinks are no-ops.
- Conflicting files, directories, and symlinks are moved, never deleted.
- Each run uses one backup root and preserves destination-relative paths.
- The link phase records completed operations and restores them if a later link fails.
- Package-manager changes are not rolled back; the final report distinguishes them from repository-managed changes.
- Unexpected plugin directories, invalid manifest paths, unsupported platforms, and checksum failures stop the run with actionable errors.
- Manifest sources must resolve inside the repository, and destinations must resolve inside the invoking user's home/configuration directories.
- No command will use an embedded username, employer path, credential, or internal network resource.

## README Design

The root README will lead with the outcome and include:

1. Supported platforms and installed features.
2. Prerequisites and a short clone/setup path.
3. A transparent summary of what setup changes.
4. Usage examples for dry runs, package skipping, and optional shell changes.
5. Topic and manifest organization.
6. Safe customization through local files.
7. Updating pinned dependencies.
8. Backup restoration and uninstall instructions.
9. Kitty SSH/terminfo and font troubleshooting.
10. Security notes and upstream acknowledgements.

All examples will use environment variables such as `$HOME` and `$USER` or neutral placeholders. The documentation will contain no personal name, internal URL, employer-specific command, or machine-specific absolute path.

## Verification

Static checks:

- `bash -n` for Bash entry points and helpers.
- `zsh -n` for Zsh configuration fragments.
- ShellCheck for shell correctness.
- `shfmt -d` formatting checks for shell files.
- repository-wide scans for personal identifiers, credentials, employer terms, internal domains, and absolute home paths.

Behavior checks will run against temporary home, config, data, and state directories. They will verify:

- unsupported operating systems fail before mutation;
- dry-run produces no filesystem changes;
- first run creates the expected links;
- second run is idempotent;
- conflicts are backed up with their contents preserved;
- a simulated link failure restores earlier link changes;
- invalid manifests and escaping paths are rejected;
- local override files are optional;
- Zsh fragments parse and load in the intended order;
- doctor reports both healthy and missing-component states accurately.

GitHub Actions will run the portable checks on current Ubuntu and macOS runners. Tests will mock privileged package-manager operations; CI will not modify the runner's login shell.

## Publishing

After implementation and verification:

1. Initialize this workspace as a new Git repository with `main` as the default branch.
2. Commit the design, implementation, documentation, and verification evidence in reviewable commits.
3. Create a new public GitHub repository at `shaqhacks/dotfiles`.
4. Push `main` and verify the remote default branch and README rendering.

Publishing requires an authenticated GitHub session with permission to create repositories in the `shaqhacks` account.

## Acceptance Criteria

- The repository is organized by topic and all mutations are controlled by explicit manifests.
- A new macOS or Debian/Ubuntu user can inspect the plan, confirm once, and complete the supported command-line setup.
- Repeat runs make no unnecessary changes.
- Existing configuration is recoverable from a timestamped backup.
- The repository contains no employer-specific content, personal identifiers, credentials, private paths, or stale legacy topics.
- README instructions match verified setup behavior.
- Static and behavior checks pass on macOS and Ubuntu.
- The new public repository is available as `shaqhacks/dotfiles` after GitHub authentication succeeds.
