# Phase 2 split: install.sh's scenarios into tests/install-test.sh

`tests/update-plugin-dev-test.sh` (472 lines) is split by script under test.
Each file carries its own copy of the harness and the fixture helpers it calls.
Both are mode 100644.

| Suite | Lines | Scenarios |
| --- | --- | --- |
| `tests/install-test.sh` (new) | 358 | install.sh vendors into a consumer that already mounts a memory submodule; install.sh refuses any ref outside the dist lineage; install.sh no ref resolves the newest dist tag; install.sh wires into an existing settings.json without replacing it; install.sh a malformed settings.json is reported with jq's diagnosis |
| `tests/update-plugin-dev-test.sh` | 282 | update-plugin-dev survives a consumer's unrelated memory submodule at the same path; update-plugin-dev refuses any ref outside the dist lineage; update-plugin-dev no ref resolves the newest dist tag; update-plugin-dev prints migration notes for the crossed range only |

`both call sites refuse any ref outside the dist lineage` was split: the install
half (source tag, manifest fixture) went to install-test.sh, the update half
(vendor, source tag, branch ref) stayed. Every assertion was kept. `vg_cmd`,
`pretool_cmd` and `session_cmd` moved with the install scenarios.

Helper choices: install-test.sh drops `assert_not_contains` (unused) and the
`cp update.sh` line in `make_toolkit_release` (install.sh never runs update.sh);
update-plugin-dev-test.sh keeps both. Headers rewritten for each file's content;
install-test.sh closes with `install.sh scenarios passed`. `justfile`
`precommit` lists `tests/install-test.sh` after update-plugin-dev-test.sh on the
`bash -n` line and as `bash tests/install-test.sh` after the update suite's run
line.

## Faithfulness

1. Sorted `echo "==="` headers, old vs new (both files): the diff is exactly the
   split, `both call sites refuse...` replaced by the two per-suite headers.
2. Assertion messages (`fail`/`assert_*` lines plus continuation-line label
   strings), sorted multiset, old (80) vs new (85): every scenario assertion is
   present once. The 5 additions are helper bodies copied into both files (the
   `fail` inside `assert_eq`, `assert_contains`, `assert_clean_vendor`, and the
   `assert_clean_vendor` status assertion) and one comment line that contains
   the word `assert_clean_vendor`.
3. Each suite passed alone from the repo root, ending
   `install.sh scenarios passed` and `update-plugin-dev scenarios passed`; both
   also passed from `/tmp` by absolute path.
4. `shellcheck` clean on both; `just format-docs` then `just precommit` exit 0,
   ending `ok`. runbook.md is 399 lines after format-docs.

## Grep for `update-plugin-dev-test`

| Path:line | Classification | Action |
| --- | --- | --- |
| `justfile:9,15` | accurate (names the update suite); `install-test.sh` added beside | edited |
| `tests/update-plugin-dev-test.sh:7` | accurate (own usage line) | none |
| `CLAUDE.md:105` | stale-owned-by-3.6 (Quality gate list lacks `install-test.sh`) | none; Item 3.6 |
| `plans/.../runbook.md:271` (Item 2.2) | was stale | now `tests/install-test.sh` |
| `plans/.../runbook.md` Item 3.6 | named no install suite | now also names `install-test.sh` |
| `plans/.../outline.md:243` | was stale | now `tests/install-test.sh` |
| `plans/2026-09-01-shell-audit-tests.md`, `plans/2026-09-18-*/cluster-b-test-suites.md`, `runbook-test-suites.md` | accurate-historical | none |
| `docs/changelog/2026-08-11-*`, `2026-08-13-*`, `2026-09-01-*` (two) | accurate-historical write-time records | none |
| `plans/*/reports/*` (about 47 files) | accurate-historical | none |
| `.claude/`, `memory/`, `README.md`, `toolkit/` | no hit | none |
