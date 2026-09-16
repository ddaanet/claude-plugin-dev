# Item 1.1 slice 1 — GREEN report

Commit: `74c4733f0fd63aa2fde5978cae88ef8feee8346f` — "Item 1.1/1 — a marketplace
entry does not disqualify a first release" (subject prefixed `✨` by the repo's
gitmoji commit-msg hook; the `Item 1.1/1` marker is intact). Carries
`tests/release-test.sh`, `toolkit/release.sh`, and the slice's RED and
test-review reports.

## Implementation

Narrowest change, as scoped:

- `toolkit/release.sh:225` — the detection predicate
  `[ -z "$(git tag --list 'v*')" ] && [ "$marketplace_entry_exists" = 0 ]` drops
  its second conjunct: `[ -z "$(git tag --list 'v*')" ]` alone now decides
  `first_release`.
- Removed the comment at `:215-221` arguing both conjuncts were load-bearing (no
  longer true — the code it described is gone). `marketplace_entry_exists`
  itself is untouched: `bump_marketplace` still reads it at `:383` and `:455`.
- The bump refusal's hint (`:227-235`) now reads "set .version in
  `.claude-plugin/plugin.json` to it and commit that edit, then re-run with no
  bump argument" — added the commit instruction slice 1's test 3 requires, since
  `.claude-plugin/` is not exempt from the clean-tree check.

`bump_commit_tag`'s initial-release branch was not touched.

## Verification

- `bash tests/release-test.sh`: all scenarios pass, including the three slice-1
  scenarios (17 assertions, previously red) and the three protected scenarios
  named in the runbook (`:592`-equivalent "a first release publishes the
  manifest version verbatim", `:634`-equivalent "tags with no marketplace entry
  is not a first release", `:721`-equivalent "a non-v tag nearer than the
  release tag does not read as the latest release" — all green, byte-identical
  to HEAD per the test-review report).
- `just precommit`: green — shellcheck, `bash -n`, `_import-check`,
  `tests/hook-test.sh`, `tests/release-test.sh`,
  `tests/update-plugin-dev-test.sh`, `tests/dist-tree-test.sh`,
  `tests/docs-test.sh`, `tests/doc-sync-test.sh`, `format-docs` all ran clean
  (the pre-commit hook's `format-docs` pass reflowed one line in the RED report
  and re-staged it into the same commit; content unchanged).

## Scope

- Touched only `toolkit/release.sh` beyond the tests and reports already in the
  working tree at handoff. `tests/release-test.sh` was not modified further — no
  genuine implementation bug forced a change to it.
- Did not add `semver_tags`, `release_tags`, or route `latest_tag` through a
  filter; did not restate the header comment at `:11-14`. Those remain for
  slices 2 and 3.

## State on exit

`git status --porcelain=v1` is empty (ignoring the sandbox's phantom dotfiles,
none of which appeared) — clean tree.
