# Verification

This file records host-safe verification evidence for the public dotfiles repository. Commands are reproducible from the repository root and avoid machine-specific paths, credentials, tokens, or local identity.

## Local Verification

Platform: macOS shell environment with repository test fixtures for package-manager and platform-specific behavior.

| Command | Exit status | Result |
| --- | ---: | --- |
| `bash tests/run.sh` | 0 | TAP suite reported `98 passed, 0 failed`. |
| `shellcheck -x setup.sh script/*.sh tests/*.sh` | 0 | No ShellCheck diagnostics. |
| `shfmt -d setup.sh script tests` | 0 | No formatting diff. |
| `git diff --check` | 0 | No whitespace errors. |
| `bash tests/run.sh setup links platform` | 0 | Existing isolated setup/link/platform scenario suites reported `39 passed, 0 failed`. |
| `bash tests/run.sh hygiene` | 0 | Repository policy scan reported `4 passed, 0 failed`. |
| `bash -n setup.sh script/*.sh tests/*.sh` | 0 | Bash syntax check passed. |
| `./setup.sh --help` | 0 | Help output lists `--dry-run`, `--skip-packages`, `--set-default-shell`, and `--help`. |

## Scenario Coverage

The existing isolated test suites cover the public CLI setup scenarios without mutating the caller's real home directory:

- `setup_help_lists_supported_flags`
- `setup_dry_run_prints_validated_plan_without_prompt_or_mutation`
- `setup_requires_tty_for_confirmation_and_decline_aborts_cleanly`
- `setup_runs_one_confirmation_and_exact_phase_order`
- `setup_skip_packages_still_installs_plugins_fonts_and_links`
- `setup_rolls_back_links_and_prints_backup_path_when_links_changed`
- `links_plan_reports_first_installation_actions_without_mutation`
- `links_plan_reports_noop_for_already_correct_link`
- `links_apply_preserves_regular_file_conflict_under_relative_backup_path`
- `links_apply_preserves_directory_conflict_and_relinks_destination`
- `links_apply_reuses_one_backup_root_for_multiple_conflicts`
- `links_apply_rolls_back_earlier_mutations_after_injected_later_failure`
- `detect_platform_reports_macos_from_uname`
- `detect_platform_reports_debian_and_ubuntu_from_os_release`
- `macos_plan_packages_appends_only_missing_formulae_and_casks`
- `debian_plan_packages_appends_only_missing_packages`

## Acceptance Review

- Topic organization and explicit manifests are present in `manifest/links.conf`, `manifest/packages.debian`, `manifest/packages.macos`, and `manifest/plugins.conf`.
- The CLI prints an inspectable plan, asks once before mutation, and supports dry-run/package-skip/default-shell flags verified by the setup suite and `./setup.sh --help`.
- Repeat runs and already-correct links are verified as no-ops by the setup and link suites.
- Conflicting files, directories, and symlinks are backed up and rollback restores earlier link mutations in the link/setup suites.
- Hygiene checks reject absolute home paths, private domains, identity fields, common secret formats, unresolved placeholders, broken relative Markdown links, and non-HTTPS remote URLs.
- Every declared link source exists as a tracked repository file.
- README usage and public flags match the setup help output and verified command behavior.
- CI is declared for Ubuntu and macOS with the local test, Bash syntax, Zsh syntax, lint, formatting, and whitespace verification commands.

## Publication Gate

Publishing requires `gh auth status -h github.com` to report an authenticated GitHub session with repository creation permission. Publish only after the verified implementation branch has been merged to local `main`; create the public repository without pushing a feature branch, then push `main` and verify or set the remote default branch to `main`:

```bash
git switch main
git merge --ff-only feat/portable-dotfiles
test "$(git branch --show-current)" = main
gh repo create shaqhacks/dotfiles --public --source=. --remote=origin
git push -u origin main
gh repo edit shaqhacks/dotfiles --default-branch main
gh repo view shaqhacks/dotfiles --json nameWithOwner,visibility,defaultBranchRef,url
```
