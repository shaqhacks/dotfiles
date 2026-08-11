# Portable Dotfiles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and publish a safe, portable, topic-oriented command-line dotfiles repository for macOS and Debian/Ubuntu.

**Architecture:** A single safe-interactive `setup.sh` orchestrates explicit package, plugin, and link manifests. Topic directories own configuration, while focused Bash helpers perform platform installation, transactional linking, dependency setup, and diagnostics without implicit script discovery.

**Tech Stack:** POSIX utilities, Bash 3.2-compatible scripts, Zsh, Homebrew, apt, Git, Kitty, Powerlevel10k, fzf, Nerd Fonts, ShellCheck, shfmt, and GitHub Actions.

## Global Constraints

- Support current macOS and Debian/Ubuntu only.
- Keep all runtime Bash compatible with macOS `/bin/bash` 3.2: no associative arrays, `mapfile`, `readarray`, `${name,,}`, or Bash 4-only features.
- Use one public `setup.sh` entry point; internal helpers remain under `script/`.
- Never discover and execute arbitrary files by extension or filename.
- Treat manifest files as untrusted data and validate their grammar and paths before mutation.
- Default to safe-interactive behavior; changing the login shell requires `--set-default-shell`.
- Never pipe downloaded content into a shell.
- Move conflicting files into a timestamped backup; never delete them.
- Keep package installation outside the rollback promise; make repository-managed links transactional.
- Store plugins under `${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles/` and backups under `${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/backups/`.
- Keep identity, credentials, private paths, and machine-specific values outside the repository.
- Use direct repo-owned symlinks rather than GNU Stow or copied snapshots.
- Do not depend on GNU-only `readlink -f` or `realpath`; canonicalize paths with primitives available on stock macOS and Debian/Ubuntu.
- Create temporary files with a `${TMPDIR:-/tmp}/dotfiles.XXXXXX` template that works on both supported platforms.
- Use test-first cycles, fresh verification output, and one reviewable commit per task.
- Under the repository's principal-engineer review directive, this plan specifies interfaces, tests, and acceptance criteria without supplying implementation bodies.

## Locked File Structure and Responsibilities

| Path | Responsibility |
| --- | --- |
| `setup.sh` | Parse public flags, orchestrate preflight/plan/apply/doctor phases, and own top-level exit behavior. |
| `manifest/links.conf` | Declare strict `repository-relative source|home-relative destination` link mappings. |
| `manifest/packages.macos` | Declare Homebrew `formula|name` and `cask|name` records. |
| `manifest/packages.debian` | Declare one apt package name per record. |
| `manifest/plugins.conf` | Declare `name|HTTPS repository|40-character commit|entrypoint` records. |
| `script/common.sh` | Logging, argument-independent validation, path containment, confirmation, command checks, and plan-file primitives. |
| `script/links.sh` | Link planning, backup journaling, link application, and rollback. |
| `script/plugins.sh` | Pinned clone/update/origin verification for Zsh dependencies. |
| `script/fonts.sh` | Linux font download, digest validation, extraction, and cache refresh. |
| `script/macos.sh` | Homebrew preflight/bootstrap and formula/cask installation. |
| `script/debian.sh` | Debian/Ubuntu detection and apt installation. |
| `script/doctor.sh` | Read-only post-install diagnostics and actionable result summary. |
| `zsh/zshrc.symlink` | Resolve repository location and load interactive configuration in fixed phases. |
| `zsh/path.zsh` | Deduplicated user paths only. |
| `zsh/config.zsh` | History and shell options. |
| `zsh/keybindings.zsh` | Portable editing and navigation bindings. |
| `zsh/completion.zsh` | `compinit`, fzf integration, autosuggestions, and syntax-highlighting load order. |
| `system/aliases.zsh` | Small cross-platform aliases with command-existence guards. |
| `system/colors.zsh` | GNU `dircolors`/`gdircolors`, GNU `ls`, and macOS fallback behavior. |
| `git/gitconfig.symlink` | Neutral Git defaults plus a local include. |
| `git/gitconfig.local.example` | Commented identity/configuration example with placeholders only. |
| `kitty/kitty.conf` | Neutral Kitty font, theme, tab/window, scrollback, bell, and clipboard behavior. |
| `powerlevel10k/p10k.zsh` | Compact neutral two-line prompt configuration using Git rather than employer-specific VCS segments. |
| `fonts/checksums` | Pinned Linux font asset URL/version/digest metadata. |
| `tests/run.sh` | Dependency-free test dispatcher and suite summary. |
| `tests/assert.sh` | Shared assertions, temporary-directory setup, and cleanup. |
| `tests/*_test.sh` | Focused behavior suites for manifests, linking, platforms, dependencies, setup, configuration, and doctor. |
| `.github/workflows/ci.yml` | Ubuntu/macOS syntax, lint, formatting, security scan, and behavior checks. |
| `README.md` | Installation contract, architecture, customization, recovery, troubleshooting, security, and acknowledgements. |
| `LICENSE` | MIT license for the new public repository. |

---

### Task 1: Repository policy and dependency-free test harness

**Files:**
- Create: `LICENSE`
- Create: `.editorconfig`
- Create: `tests/run.sh`
- Create: `tests/assert.sh`
- Create: `tests/harness_test.sh`
- Modify: `.gitignore`

**Interfaces:**
- `tests/run.sh [suite-name ...]` runs all `tests/*_test.sh` files or only named suites and returns nonzero when any assertion fails.
- `tests/assert.sh` provides `fail`, `assert_eq`, `assert_file`, `assert_dir`, `assert_symlink_target`, `assert_contains`, `assert_not_contains`, and `make_test_home`.
- `make_test_home` exports isolated `HOME`, `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, and `XDG_STATE_HOME`, then registers cleanup with `trap`.

- [ ] **Step 1: Define the harness acceptance cases**

  Record cases in `tests/harness_test.sh` for passing assertions, intentionally failing assertions captured in a child process, isolated XDG directories, whitespace-safe arguments, and cleanup after exit.

- [ ] **Step 2: Run the absent harness and confirm the expected failure**

  Run: `bash tests/run.sh harness`

  Expected: failure because `tests/run.sh` does not exist.

- [ ] **Step 3: Implement the smallest harness satisfying the interfaces**

  Keep output TAP-like and human-readable, avoid external test frameworks, quote every path, and ensure test helpers never operate outside the temporary test root.

- [ ] **Step 4: Verify the harness and repository whitespace**

  Run: `bash tests/run.sh harness`

  Expected: all harness cases pass.

  Run: `git diff --check`

  Expected: no output and exit zero.

- [ ] **Step 5: Commit the harness foundation**

  Run: `git add .editorconfig .gitignore LICENSE tests/assert.sh tests/harness_test.sh tests/run.sh && git commit -m "test: add portable shell test harness"`

---

### Task 2: Strict manifest grammar and preflight validation

**Files:**
- Create: `manifest/links.conf`
- Create: `manifest/packages.macos`
- Create: `manifest/packages.debian`
- Create: `manifest/plugins.conf`
- Create: `script/common.sh`
- Create: `tests/manifest_test.sh`

**Interfaces:**
- `manifest_each KIND FILE CALLBACK` validates each nonblank, non-comment record and invokes the callback with parsed fields.
- `validate_repo_source ROOT RELATIVE_PATH` accepts only existing regular files inside `ROOT`.
- `validate_home_destination RELATIVE_PATH` rejects absolute paths, empty segments, `.`/`..` segments, control characters, and destinations outside the test or real home.
- `plan_reset`, `plan_append PHASE ACTION DETAIL`, and `plan_print` store the plan in a private temporary file rather than Bash 4 arrays.
- Link records use exactly two fields; macOS package records use exactly two; Debian package records use exactly one; plugin records use exactly four.

**Locked manifest data:**
- `manifest/links.conf` contains grammar comments only in this task; Task 8 adds the locked `.zshrc`, `.gitconfig`, `.config/kitty/kitty.conf`, and `.p10k.zsh` mappings after every source exists.
- macOS formulae: `git`, `fzf`, `coreutils`, `shellcheck`, and `shfmt`; use the macOS-provided `/bin/zsh` rather than installing a competing login shell.
- macOS casks: `kitty` and `font-jetbrains-mono-nerd-font`.
- Debian/Ubuntu packages: `zsh`, `git`, `curl`, `fzf`, `kitty`, `fontconfig`, `unzip`, `coreutils`, `shellcheck`, and `shfmt`.
- Powerlevel10k: tag `v1.20.0`, commit `35833ea15f14b71dbcebc7e54c104d8d56ca5268`, entrypoint `powerlevel10k.zsh-theme`.
- zsh-autosuggestions: tag `v0.7.1`, commit `e52ee8ca55bcc56a17c828767a3f98f22a68d4eb`, entrypoint `zsh-autosuggestions.zsh`.
- zsh-syntax-highlighting: tag `0.8.0`, commit `db085e4661f6aafd24e5acb5b2e17e4dd5dddf3e`, entrypoint `zsh-syntax-highlighting.zsh`.

- [ ] **Step 1: Write manifest validation cases**

  Cover valid comments/blank lines, exact field counts, duplicate destinations/names, missing sources, absolute paths, traversal segments, newline/control characters, non-HTTPS plugin URLs, malformed commit IDs, and sources that resolve outside the repository through symlinks.

- [ ] **Step 2: Run the manifest suite and confirm failure**

  Run: `bash tests/run.sh manifest`

  Expected: failure because the manifests and validation functions are absent.

- [ ] **Step 3: Implement the manifest reader and preflight functions**

  Parse without `eval` or `source`, set `IFS` locally, restore shell state, reject ambiguous records before invoking callbacks, and produce errors containing the manifest path and line number.

- [ ] **Step 4: Verify manifest behavior and Bash compatibility**

  Run: `bash tests/run.sh manifest`

  Expected: all valid and hostile manifest cases pass.

  Run: `/bin/bash -n script/common.sh tests/manifest_test.sh`

  Expected: exit zero.

- [ ] **Step 5: Commit deterministic manifests**

  Run: `git add manifest script/common.sh tests/manifest_test.sh && git commit -m "feat: add validated setup manifests"`

---

### Task 3: Transactional backup and symlink engine

**Files:**
- Create: `script/links.sh`
- Create: `tests/links_test.sh`
- Modify: `script/common.sh`

**Interfaces:**
- `links_plan REPO_ROOT LINKS_MANIFEST` adds `noop`, `backup`, `mkdir`, and `link` actions without mutation.
- `links_apply REPO_ROOT LINKS_MANIFEST BACKUP_ROOT JOURNAL` applies links in manifest order.
- `links_rollback JOURNAL` removes links created by the current run and restores moved conflicts in reverse order.
- The journal stores one tab-separated record per mutation with operation, destination, and backup path; fields containing tabs or newlines are rejected during preflight.

- [ ] **Step 1: Write link-engine behavior cases**

  Cover first installation, an already-correct link, a link pointing elsewhere, regular-file conflict, directory conflict, spaces in paths, nested destination creation, one backup root per run, preserved relative destination paths, injected failure on a later record, and exact rollback of earlier records.

- [ ] **Step 2: Run the link suite and confirm failure**

  Run: `bash tests/run.sh links`

  Expected: failure because `script/links.sh` and its interfaces are absent.

- [ ] **Step 3: Implement planning, apply, journaling, and rollback**

  Use `mv` and `ln -s` only after complete preflight. Resolve repository sources to canonical absolute paths, refuse destinations outside the isolated/real home, and make rollback safe to repeat.

- [ ] **Step 4: Verify link behavior and failure recovery**

  Run: `bash tests/run.sh links`

  Expected: all cases pass, including content-preserving rollback.

  Run: `/bin/bash -n script/common.sh script/links.sh tests/links_test.sh`

  Expected: exit zero.

- [ ] **Step 5: Commit transactional linking**

  Run: `git add script/common.sh script/links.sh tests/links_test.sh && git commit -m "feat: add recoverable dotfile linking"`

---

### Task 4: macOS and Debian/Ubuntu package adapters

**Files:**
- Create: `script/macos.sh`
- Create: `script/debian.sh`
- Create: `tests/platform_test.sh`
- Create: `tests/fixtures/bin/`

**Interfaces:**
- `detect_platform` prints exactly `macos` or `debian`; unsupported systems return nonzero before mutation.
- `platform_zsh_path PLATFORM` prints `/bin/zsh` on macOS and the apt-installed Zsh path on Debian/Ubuntu; it fails if that path is not executable or is absent from `/etc/shells`.
- `macos_plan_packages MANIFEST` and `debian_plan_packages MANIFEST` append only missing packages to the plan.
- `macos_install_packages MANIFEST` and `debian_install_packages MANIFEST` install only planned packages.
- `macos_ensure_homebrew` downloads the official installer to a `mktemp` path, displays the source in the plan, executes only after the run confirmation, and removes the temporary file.
- Tests may set `DOTFILES_TEST_MODE=1` with `DOTFILES_TEST_PLATFORM`; production refuses the override when test mode is absent.

- [ ] **Step 1: Write platform adapter cases with command stubs**

  Cover Darwin, Debian, Ubuntu, unsupported Linux, missing `/etc/os-release`, installed/missing packages, formula/cask separation, apt update exactly once, sudo failure propagation, Homebrew absence, installer download failure, no remote-content pipe, platform Zsh selection, and a Zsh path absent from `/etc/shells`.

- [ ] **Step 2: Run the platform suite and confirm failure**

  Run: `bash tests/run.sh platform`

  Expected: failure because platform adapters are absent.

- [ ] **Step 3: Implement platform detection and package adapters**

  Keep platform-specific commands out of `setup.sh`, pass manifest records through the validated reader, use `brew list --formula`, `brew list --cask`, and `dpkg-query` for presence checks, and propagate exact command failures.

- [ ] **Step 4: Verify package planning without host mutation**

  Run: `bash tests/run.sh platform`

  Expected: all mock-backed cases pass and no real package manager runs.

  Run: `/bin/bash -n script/macos.sh script/debian.sh tests/platform_test.sh`

  Expected: exit zero.

- [ ] **Step 5: Commit platform support**

  Run: `git add script/macos.sh script/debian.sh tests/platform_test.sh tests/fixtures/bin && git commit -m "feat: add macos and debian package adapters"`

---

### Task 5: Pinned plugins and verified Linux font installation

**Files:**
- Create: `script/plugins.sh`
- Create: `script/fonts.sh`
- Create: `fonts/checksums`
- Create: `tests/dependencies_test.sh`
- Modify: `manifest/plugins.conf`

**Interfaces:**
- `plugins_plan MANIFEST DATA_ROOT` reports clone, update, or no-op for every plugin.
- `plugins_apply MANIFEST DATA_ROOT` requires the declared origin and checks out the declared commit in detached-head state.
- `font_plan PLATFORM` is a no-op on macOS because Homebrew owns the font; Linux checks the declared files and metadata.
- `font_install_linux METADATA_FILE` downloads over HTTPS to a temporary archive, validates SHA-256, extracts only font files into `${XDG_DATA_HOME:-$HOME/.local/share}/fonts/JetBrainsMonoNerdFont`, and runs `fc-cache`.

**Locked Linux font metadata:**
- Nerd Fonts version: `v3.5.0`.
- Asset: `JetBrainsMono.zip`.
- SHA-256: `9577de1ae84ec523df16fc69bac5338b89497a5b4fb91489e2dcb79dc06ac2b5`.
- Source: `https://github.com/ryanoasis/nerd-fonts/releases/download/v3.5.0/JetBrainsMono.zip`.

- [ ] **Step 1: Write dependency cases**

  Cover fresh plugin clone, exact-commit no-op, changed pinned revision, mismatched origin, dirty plugin checkout, interrupted clone, malformed entrypoint, font already present, digest mismatch, archive traversal, download failure, and cache-refresh failure.

- [ ] **Step 2: Run the dependency suite and confirm failure**

  Run: `bash tests/run.sh dependencies`

  Expected: failure because dependency installers are absent.

- [ ] **Step 3: Implement pinned plugin and font behavior**

  Clone into a temporary sibling directory before an atomic rename, fetch only the required commit when possible, never reset a dirty or mismatched checkout, list archive members before extraction, and remove temporary artifacts through traps.

- [ ] **Step 4: Verify dependency safety**

  Run: `bash tests/run.sh dependencies`

  Expected: all cases pass without network access because Git, curl, unzip, and `fc-cache` are stubbed.

  Run: `/bin/bash -n script/plugins.sh script/fonts.sh tests/dependencies_test.sh`

  Expected: exit zero.

- [ ] **Step 5: Commit pinned dependencies**

  Run: `git add manifest/plugins.conf fonts/checksums script/plugins.sh script/fonts.sh tests/dependencies_test.sh && git commit -m "feat: install pinned shell dependencies"`

---

### Task 6: Safe-interactive setup orchestration and doctor

**Files:**
- Create: `setup.sh`
- Create: `script/doctor.sh`
- Create: `tests/setup_test.sh`
- Create: `tests/doctor_test.sh`
- Modify: `tests/fixtures/bin/`

**Interfaces:**
- `setup.sh` accepts only `--dry-run`, `--skip-packages`, `--set-default-shell`, and `--help`; duplicate or unknown flags fail before mutation.
- Phase order is `parse → preflight → print plan → confirm → packages → plugins/font → links → optional chsh → doctor`.
- `--dry-run` exits after printing the fully validated plan and never prompts.
- Confirmation requires an interactive terminal and an affirmative `y`/`yes`; EOF and all other input abort cleanly.
- `--set-default-shell` passes only the validated `platform_zsh_path` to `chsh`; setup never edits `/etc/shells`.
- `doctor_main` performs read-only checks and returns zero only when required components and declared links are healthy.

- [ ] **Step 1: Write setup and doctor cases**

  Cover help, unknown/duplicate flags, unsupported OS, no TTY, declined confirmation, dry-run immutability, skip-packages behavior, exact phase order, package failure before links, plugin failure before links, link rollback, optional shell change, rejected shell paths, failed `chsh`, healthy doctor output, and missing font/plugin/link diagnostics.

- [ ] **Step 2: Run both suites and confirm failure**

  Run: `bash tests/run.sh setup doctor`

  Expected: failure because orchestration and diagnostics are absent.

- [ ] **Step 3: Implement orchestration and diagnostics**

  Resolve `DOTFILES_ROOT` from `setup.sh` rather than the caller's working directory, create private temporary files with cleanup traps, source only fixed internal helper paths, preserve the first failing exit status, and print the backup path whenever link changes occurred.

- [ ] **Step 4: Verify the public contract**

  Run: `bash tests/run.sh setup doctor`

  Expected: all orchestration and diagnostic cases pass.

  Run: `/bin/bash -n setup.sh script/*.sh tests/setup_test.sh tests/doctor_test.sh`

  Expected: exit zero.

- [ ] **Step 5: Commit the setup entry point**

  Run: `git add setup.sh script/doctor.sh tests/setup_test.sh tests/doctor_test.sh tests/fixtures/bin && git commit -m "feat: add safe interactive setup workflow"`

---

### Task 7: Deterministic Zsh configuration

**Files:**
- Create: `zsh/zshrc.symlink`
- Create: `zsh/path.zsh`
- Create: `zsh/config.zsh`
- Create: `zsh/keybindings.zsh`
- Create: `zsh/completion.zsh`
- Create: `system/aliases.zsh`
- Create: `system/colors.zsh`
- Create: `tests/zsh_test.sh`

**Interfaces:**
- `.zshrc` resolves the repository from its own canonical symlink target.
- Load order is instant prompt, path, config, aliases/colors, key bindings, completion/fzf, Powerlevel10k theme/config, autosuggestions, optional `~/.zshrc.local`, then syntax highlighting last.
- Missing optional commands or plugins do not make an interactive shell unusable; doctor reports them separately.
- History uses `${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history`, creates the parent securely, and enables append/share/deduplication behavior.

- [ ] **Step 1: Write Zsh behavior cases**

  Cover parsing every fragment, repository paths containing spaces, fixed load-order markers, missing optional plugins, local override last, duplicate-free path setup, history parent creation, completion cache location, fzf modern and distro fallbacks, guarded aliases, and syntax highlighting last.

- [ ] **Step 2: Run the Zsh suite and confirm failure**

  Run: `bash tests/run.sh zsh`

  Expected: failure because configuration fragments are absent.

- [ ] **Step 3: Implement the minimal portable shell configuration**

  Reuse only current, general behavior from the legacy checkout: history quality, completion matching, arrow-key history search, Delete/Home/End and word movement, small Git/system aliases, and guarded color behavior. Exclude obsolete editor, application, language-runtime, deployment, and employer-specific settings.

- [ ] **Step 4: Verify Zsh syntax and isolated loading**

  Run: `zsh -n zsh/*.zsh zsh/zshrc.symlink system/*.zsh`

  Expected: exit zero.

  Run: `bash tests/run.sh zsh`

  Expected: all cases pass with an isolated home.

- [ ] **Step 5: Commit shell configuration**

  Run: `git add zsh system tests/zsh_test.sh && git commit -m "feat: add portable zsh configuration"`

---

### Task 8: Git, Kitty, and Powerlevel10k topics

**Files:**
- Create: `git/gitconfig.symlink`
- Create: `git/gitconfig.local.example`
- Create: `kitty/kitty.conf`
- Create: `powerlevel10k/p10k.zsh`
- Create: `tests/config_test.sh`
- Modify: `manifest/links.conf`

**Interfaces:**
- Git defaults include `init.defaultBranch=main`, `color.ui=auto`, `fetch.prune=true`, `pull.ff=only`, `push.autoSetupRemote=true`, and `~/.gitconfig.local`; identity is absent.
- Kitty uses the `JetBrainsMono Nerd Font Mono` family, a neutral dark palette, platform-neutral shortcuts, visual bell behavior, and no absolute include paths or network references.
- Powerlevel10k uses a compact two-line prompt with directory, Git VCS, prompt character, status, command duration, background jobs, and time; no user/host segment appears locally unless the shell is remote.

- [ ] **Step 1: Write configuration contract cases**

  Cover `git config --file` parsing, required Git values, absent identity/credential fields, correct local include, Kitty font and neutral paths, absence of URLs/usernames, Powerlevel10k parseability, required prompt segments, and manifest destination mappings.

- [ ] **Step 2: Run the configuration suite and confirm failure**

  Run: `bash tests/run.sh config`

  Expected: failure because the topic files are absent.

- [ ] **Step 3: Implement neutral application configuration**

  Keep defaults short and documented, avoid complex shell-pipeline Git aliases, do not copy generated Powerlevel10k comments wholesale, and retain only prompt options required by the contract.

- [ ] **Step 4: Verify configuration parsing**

  Run: `git config --file git/gitconfig.symlink --list >/dev/null`

  Expected: exit zero.

  Run: `zsh -n powerlevel10k/p10k.zsh && bash tests/run.sh config`

  Expected: syntax success and all configuration cases pass.

- [ ] **Step 5: Commit application topics**

  Run: `git add git kitty powerlevel10k manifest/links.conf tests/config_test.sh && git commit -m "feat: add git kitty and prompt topics"`

---

### Task 9: README, CI, and repository hygiene

**Files:**
- Create: `README.md`
- Create: `.github/workflows/ci.yml`
- Create: `tests/hygiene_test.sh`
- Modify: `.gitignore`

**Interfaces:**
- README sections are Overview, Features, Supported Platforms, Prerequisites, Install, What Setup Changes, Usage, Repository Structure, Customization, Updates, Recovery/Uninstall, Troubleshooting, Security, and Acknowledgements.
- CI runs on `ubuntu-latest` and `macos-latest`, installs ShellCheck and shfmt through each runner's package manager, and executes the same local verification commands.
- Hygiene tests reject embedded absolute home paths, private-domain suffixes, identity fields, common secret formats, unresolved placeholders, broken relative Markdown links, and non-HTTPS remote URLs.

- [ ] **Step 1: Write documentation and hygiene contract cases**

  Verify every README command references a real file/flag, every documented feature maps to a manifest/config entry, internal Markdown links resolve, recovery instructions match backup behavior, and repository text is neutral.

- [ ] **Step 2: Run hygiene checks and confirm failure**

  Run: `bash tests/run.sh hygiene`

  Expected: failure because README, CI, and hygiene checks are absent.

- [ ] **Step 3: Write outcome-first documentation and CI**

  Use generic `$HOME`/`$USER` examples, explain the single confirmation and package-manager boundary, document `~/.zshrc.local` and `~/.gitconfig.local`, include exact restore commands based on the backup layout, and acknowledge upstream projects without reproducing their documentation.

- [ ] **Step 4: Run complete static verification**

  Run: `bash tests/run.sh`

  Expected: every suite passes.

  Run: `shellcheck -x setup.sh script/*.sh tests/*.sh`

  Expected: no findings.

  Run: `shfmt -d setup.sh script tests`

  Expected: no output.

  Run: `git diff --check`

  Expected: no output.

- [ ] **Step 5: Commit documentation and CI**

  Run: `git add README.md .github/workflows/ci.yml .gitignore tests/hygiene_test.sh && git commit -m "docs: add setup guide and continuous verification"`

---

### Task 10: Host-safe end-to-end verification and GitHub publication

**Files:**
- Create: `docs/verification.md`
- Modify only when a verified defect requires correction: files from Tasks 1–9 and their owning tests.

**Interfaces:**
- Verification evidence records command, platform, exit status, and concise result; it contains no host-specific paths, credentials, tokens, or personal identity.
- Publication target is a new public `shaqhacks/dotfiles` repository with `main` as the default branch.

- [ ] **Step 1: Run the complete local verification sequence from a clean tree**

  Run: `bash tests/run.sh && shellcheck -x setup.sh script/*.sh tests/*.sh && shfmt -d setup.sh script tests && git diff --check`

  Expected: every command exits zero.

- [ ] **Step 2: Exercise the public CLI without mutating the real home**

  Run setup under the isolated test environment for `--help`, both platform dry runs, declined confirmation, first link run, second idempotent run, conflict backup, and injected rollback.

  Expected: each scenario matches its test contract and the real `$HOME` remains unchanged.

- [ ] **Step 3: Record verification evidence and commit it**

  Write only reproducible commands and summarized outcomes to `docs/verification.md`.

  Run: `git add docs/verification.md && git commit -m "test: record cross-platform verification"`

- [ ] **Step 4: Perform an independent completion review**

  Compare every design acceptance criterion to a passing test, inspect `git diff HEAD~1` and the full tree for private data, confirm all declared sources exist, and confirm README behavior matches `setup.sh --help` and test evidence.

- [ ] **Step 5: Authenticate GitHub without exposing credentials**

  Run: `gh auth status -h github.com`

  Expected: active authenticated `shaqhacks` account with repository creation permission. If authentication is absent or invalid, run `gh auth login -h github.com` and complete the credential-gated device/browser flow before continuing.

- [ ] **Step 6: Create and push the new public repository**

  Run: `gh repo create shaqhacks/dotfiles --public --source=. --remote=origin --push`

  Expected: repository creation succeeds, `origin` points to `shaqhacks/dotfiles`, and `main` is pushed.

- [ ] **Step 7: Verify the published state**

  Run: `gh repo view shaqhacks/dotfiles --json nameWithOwner,visibility,defaultBranchRef,url`

  Expected: `nameWithOwner` is `shaqhacks/dotfiles`, visibility is public, and the default branch is `main`.

  Run: `git status --short --branch`

  Expected: `main` tracks `origin/main` and the working tree is clean.

## Upstream References for Implementation Review

- Zsh startup files: <https://zsh.sourceforge.io/Intro/intro_3.html>
- Kitty configuration paths: <https://sw.kovidgoyal.net/kitty/invocation/>
- Kitty shell integration and SSH: <https://sw.kovidgoyal.net/kitty/shell-integration/>
- Powerlevel10k: <https://github.com/romkatv/powerlevel10k>
- fzf: <https://github.com/junegunn/fzf>
- zsh-autosuggestions: <https://github.com/zsh-users/zsh-autosuggestions/blob/master/INSTALL.md>
- zsh-syntax-highlighting: <https://github.com/zsh-users/zsh-syntax-highlighting/blob/master/INSTALL.md>
- Nerd Fonts releases: <https://github.com/ryanoasis/nerd-fonts/releases>
- Git configuration: <https://git-scm.com/docs/git-config>
- GNU `dircolors`: <https://www.gnu.org/software/coreutils/manual/html_node/dircolors-invocation.html>
