# Additional Corrective Wave Report

Date: 2026-08-12

## Root Cause

`links_record_mkdir` created a missing destination parent directory before appending the `mkdir` journal record. If `links_journal mkdir ...` failed after the filesystem mutation, rollback had no record of the created directory and the directory could remain behind after `links_apply` failed.

## RED Evidence

Command:

```bash
bash tests/run.sh links
```

Output summary:

```text
1..14
ok 1 - links_plan_reports_first_installation_actions_without_mutation
...
ok 13 - links_apply_removes_created_symlink_when_link_journal_fails_after_ln
not ok - failed mkdir journal left created directory behind
not ok 14 - links_apply_removes_created_directory_when_mkdir_journal_fails
# summary: 13 passed, 1 failed
```

## Changed Files and Rationale

- `tests/links_test.sh`: added `links_apply_removes_created_directory_when_mkdir_journal_fails`, which runs the real `links_apply` path with `DOTFILES_LINKS_FAIL_JOURNAL_ON="mkdir"` and asserts the just-created directory is removed.
- `script/links.sh`: added immediate local compensation in `links_record_mkdir`; if journaling fails after `mkdir`, it calls `rmdir` on the just-created directory and returns failure.
- `docs/verification.md`: updated recorded local verification totals to `bash tests/run.sh` = `104 passed, 0 failed` and `bash tests/run.sh links` = `14 passed, 0 failed`.
- `.superpowers/sdd/2026-08-11-portable-dotfiles-implementation/final-fix-report.md`: removed one absolute local worktree path so repository hygiene checks can pass with the report tracked.

## GREEN Evidence

Focused link suite:

```bash
bash tests/run.sh links
```

Output summary:

```text
1..14
ok 1 - links_plan_reports_first_installation_actions_without_mutation
...
ok 14 - links_apply_removes_created_directory_when_mkdir_journal_fails
# summary: 14 passed, 0 failed
```

Full suite:

```bash
bash tests/run.sh
```

Output summary:

```text
1..104
ok 1 - git_config_has_portable_defaults_and_local_include_without_identity
...
ok 104 - zsh_aliases_are_guarded_by_available_commands
# summary: 104 passed, 0 failed
```

Static verification:

```bash
bash -n setup.sh script/*.sh tests/*.sh
zsh -n zsh/*.zsh zsh/zshrc.symlink system/*.zsh powerlevel10k/p10k.zsh
shellcheck -x setup.sh script/*.sh tests/*.sh
shfmt -d setup.sh script tests
git diff --check
```

Output summary:

```text
All five commands exited 0 with no diagnostics or formatting/whitespace diff.
```

## Commit

Implementation commit: `21493b5`

## Concerns

- Remote CI was not run.
- No publication, GitHub repository creation, branch merge, or authentication changes were performed.
