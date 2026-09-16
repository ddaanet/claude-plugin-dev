# Recall artifact — first-release version selection

Selected at the `/runbook` implementation checkpoint. The memory index
(`memory/MEMORY.md`) is not injected in this session, so selection ran against
`rg --files memory/` as the degraded path prescribes.

## Entries an executor of this runbook should read

- `memory/ddaanet/git-hook-env-leak.md` — repo-local `GIT_*` leaking out of an
  enclosing `git commit` into a hook or a test process. Both suites run under
  this repo's own pre-commit hook, and the version-guard's new tag listing is
  exactly the kind of `git` call a leaked `GIT_DIR` redirects. Motivates the
  harness `unset $(git rev-parse --local-env-vars)` in `tests/hook-test.sh` and
  the guard's own clearing (Items 1.x fixtures, Item 2.1 slices 1 and 5).
- `memory/ddaanet/hook-output-channels.md` — which channel speaks to whom. The
  guard's message branch is `permissionDecisionReason` only; `systemMessage`
  does not branch (Item 2.1 slice 3). Wording rules are the
  `craft:directive-writing` skill it points at.
- `memory/ddaanet/no-stderr-suppression.md` — `2>/dev/null` is a finding to
  justify. The guard's tag listing carries one deliberately, and the runbook
  states the justification it must write inline.
- `memory/ddaanet/claude-plugin-dev.md` — what this toolkit is, where its manual
  lives, and that the changelog does not ship (Item 3.6).
- `memory/feedback_plugin_dev_no_backcompat.md` — no compat aliases, no internal
  back-compat; the two-part detection conjunct is removed outright rather than
  kept behind a flag.

## Post-explore gate

Exploration (`toolkit/release.sh`, `toolkit/version-guard.sh`,
`tests/release-test.sh`, `tests/hook-test.sh`) surfaced no domain the first pass
did not cover. No further entries selected.
