# 2026-10-15 — The test suites are split under the 400-line cap, and a gate holds it

Nine suites were over 400 lines, `tests/release-test.sh` at 1738. The cap exists
so a reader takes a file in at one go, and a suite is read as often as a script.
Each is now several sibling suites split along its scenario groups, and a new
suite, `tests/line-cap-test.sh`, fails the gate when any tracked file passes the
cap.

## What changed

- Each oversized suite became siblings, named for the group they cover:
  `release-{core,resume-push,resume-hint,tree,first,lost-tag,push-route,tags, rollback,pipefail,hint-size}`,
  `release-dist-{publish,resume,refusal,optin}`,
  `dist-{build,refusal,warning,subcommands}` (`dist-tree-test.sh` already named
  the shipped-file list, so the tree-build group is `dist-build`),
  `dogfood-sync-{copy,nested,allowlist}`, `dogfood-pre-tool-{paths,jq}`,
  `dogfood-launcher-{exec,path}`, `install-{vendor,settings,legacy}`,
  `self-release-{publish,refusal}` and `version-guard-{decision,wording,git}`,
  each as `<name>-test.sh`.
- Scenarios moved verbatim. Every file carries its own copy of the assertion
  harness and its own fixture setup, with no shared sourced helper: the
  one-script-per-suite convention is unchanged. A file leaves out the fixture
  helpers none of its scenarios call, which is what keeps the larger groups
  under the cap.
- The count of `assert_` call sites in the scenario bodies is the same before
  and after for every original suite, and every `echo "==="` banner survives.
- `version-guard-test.sh`'s fixture-allocation comments were rewritten for the
  narrower fixtures each sibling allocates; no scenario text changed.
- `justfile`'s `precommit` lists and runs the new files, CLAUDE.md's Quality
  gate paragraph names them, and comments in other suites that pointed at
  `release-test.sh` point at the sibling that now holds the cited code.
- `tests/line-cap-test.sh` counts text lines of every tracked file
  (`git ls-files -z -s`, so a path with a space is one path) and reports
  `oversized-file: <path>: <n> lines > 400`. It skips what `docs-test.sh`
  already governs (markdown under `docs/` and `plans/`, which also counts
  untracked drafts and honours `cap-ok`), `docs/changelog/`, gitlinks such as
  `memory`, symlinks and binary files. It is a sibling suite and not a section
  of `docs-test.sh` because that suite is about prose, and the two differ in
  scope and exemption. It first runs the scan on a fixture repo, so the report
  format and each exclusion are pinned by an assertion, and then on this repo.
  Its `exempt` list is empty: a file takes an entry only with a stated reason.
