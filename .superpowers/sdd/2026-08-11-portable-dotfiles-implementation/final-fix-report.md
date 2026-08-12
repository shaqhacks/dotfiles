# Final Review Fix Report

Date: 2026-08-11
Worktree: `portable-dotfiles`
Base: `43735c6d356ada1ffb8979c04f854e631656c28d`

## Scope

Fixed the final-review wave only:

- Link journaling now compensates immediately if journal append fails after `mv` backup or `ln -s`.
- Publication guidance now requires a verified local `main` merge before creating/pushing `shaqhacks/dotfiles`, pushes `main`, and verifies/sets default branch `main`.
- Homebrew planning now discloses the official installer URL and temporary-file execution strategy before confirmation; apply no longer mutates the plan.
- Setup-managed backups now live under `${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/backups/`.
- CI now installs `zsh` on Ubuntu and runs explicit Bash and Zsh syntax checks.

## RED Evidence

Command:

```bash
bash tests/run.sh links
```

Output summary:

```text
1..13
ok 1 - links_plan_reports_first_installation_actions_without_mutation
...
ok 11 - links_apply_rolls_back_earlier_mutations_after_injected_later_failure
not ok - expected command to fail: apply_links
not ok - expected .../.zshrc to contain: old zsh
not ok 12 - links_apply_restores_destination_when_backup_journal_fails_after_move
not ok - expected command to fail: apply_links
not ok - failed link journal left created symlink behind
not ok 13 - links_apply_removes_created_symlink_when_link_journal_fails_after_ln
# summary: 11 passed, 2 failed
```

Command:

```bash
bash tests/run.sh platform
```

Output summary:

```text
1..16
...
not ok - Homebrew apply must not append post-confirm plan rows: expected '', got 'packages install-homebrew ...'
not ok 10 - macos_ensure_homebrew_downloads_temp_installer_and_removes_it_after_confirmed_run
... macos_plan_homebrew: command not found
not ok 11 - macos_plan_homebrew_discloses_official_url_and_temp_file_execution_strategy
# summary: 14 passed, 2 failed
```

Command:

```bash
bash tests/run.sh setup
```

Output summary:

```text
1..15
...
not ok 12 - setup_uses_xdg_state_home_for_link_backups
not ok 13 - setup_macos_homebrew_plan_is_complete_before_confirmation
# summary: 13 passed, 2 failed
```

## GREEN Evidence

Focused command:

```bash
bash tests/run.sh links setup platform hygiene config
```

Output summary:

```text
1..52
ok 1 - links_plan_reports_first_installation_actions_without_mutation
...
ok 52 - links_manifest_plans_first_installation_for_application_topics
# summary: 52 passed, 0 failed
```

Full command:

```bash
bash tests/run.sh
```

Output summary:

```text
1..103
ok 1 - git_config_has_portable_defaults_and_local_include_without_identity
...
ok 103 - zsh_aliases_are_guarded_by_available_commands
# summary: 103 passed, 0 failed
```

Syntax/lint/format commands:

```bash
bash -n setup.sh script/*.sh tests/*.sh
zsh -n zsh/*.zsh zsh/zshrc.symlink system/*.zsh powerlevel10k/p10k.zsh
shellcheck -x setup.sh script/*.sh tests/*.sh
shfmt -d setup.sh script tests
git diff --check
```

Results:

```text
All five commands exited 0. Bash syntax, Zsh syntax, ShellCheck, shfmt, and whitespace checks produced no diagnostics.
```

## Manual Review

- README backup examples now use `${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/backups/...`, matching `setup_state_root` and `setup_backup_root`.
- README Homebrew text matches `macos_plan_homebrew` and `macos_ensure_homebrew`: official installer URL is disclosed before confirmation, downloaded to a temp file, and not piped to shell.
- `docs/verification.md` publication gate no longer uses `gh repo create --push`; it requires switching to local `main`, fast-forward merging `feat/portable-dotfiles`, creating the public repo without push, pushing `main`, setting default branch `main`, and viewing the repo metadata.
- CI now installs `zsh` on Ubuntu before running `zsh -n`; macOS remains valid because zsh is available on the runner.

## Self-Review

- Kept rollback schema unchanged: journal records remain `operation`, `destination`, `backup`; unjournaled mutations receive local compensation only.
- Did not journal intent before mutation.
- Did not change package-manager rollback promises.
- Did not introduce new dependencies.
- Changed files are limited to the findings: `script/links.sh`, `script/macos.sh`, `setup.sh`, targeted tests, README, verification docs, and CI.

## Concerns

- CI changes were verified locally by running the same commands, but GitHub Actions itself was not executed in this local wave.
- Publication commands remain intentionally credential-gated and were not executed.
