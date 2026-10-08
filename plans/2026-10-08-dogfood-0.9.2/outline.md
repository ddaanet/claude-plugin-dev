# Dogfood 0.9.2 — outline

Two patches to toolkit 0.9.1, both found by the dogfood in handoff
([report](../2026-10-05-dogfood-drop-auto-sync/reports/dogfood-handoff.md),
"Surprises").

## 1. session-start names `just dogfood` when there is no copy

- Where: `toolkit/dogfood.sh` `session_start`, at the warning, after the entry
  loop. The silent match on an entry is unchanged.
- Condition: `[[ ! -d "$copy" ]]`, the shim's own test, so a file in place of
  the copy counts as no copy.
- `systemMessage`: one `dogfood:` line in the shim's tone, naming `just dogfood`
  and the relaunch.
- `additionalContext`: the fact only — no copy exists, so the session loads
  none. No command, nothing naming the sync.
- Copy present, session not loading it: today's text. `jq` missing: unchanged.
- Tests (`tests/dogfood-session-start-test.sh`): no copy + variable unset, and a
  file in place of the copy, each red against 0.9.1. Copy present + variable
  unset pins today's exact text (a regression pin, green by construction).

## 2. sync honours ignores inside submodules

- Where: `toolkit/dogfood.sh` `sync_copy`; a new recursive
  `list_ignored <dir> <prefix>` replaces the one root-level `ls-files` pipeline.
- Per repo: `ls-files -z -o -i --exclude-standard --directory` and
  `ls-files -z -s` each written to a scratch file (simple commands, so errexit
  catches a git failure), read NUL-delimited on fd 3; gitlinks (mode 160000)
  with a `.git` recurse with the prefix extended. No `git submodule foreach`
  (sh, no `read -d ''`), no grep filter (exit 1 on zero submodules).
- The pattern refusal runs on the prefixed entry and now exits the script
  directly; the header comment is rewritten to say so.
- Tests (`tests/dogfood-sync-test.sh`): a submodule whose own `.gitignore`
  ignores a directory holding a file, plus a nested submodule doing the same;
  ignored directories absent from the copy, tracked files present. Fixture git
  runs with `GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1`.

## Docs

- `docs/references/dogfood.md`: the source set and the session check, words
  replaced rather than lines added.
- `toolkit/README.md`: the sync's exclusions and the Session check warnings.
- Hub unchanged: no conclusion flips.
- `docs/changelog/2026-10-08-dogfood-no-copy-remedy-and-submodule-ignores.md`
  and its index bullet. No migration note.

## Process

Red runs saved under `reports/`, then fixes, docs, `just precommit`, commits
(`fix:` per surprise with its tests and red file, then `docs:`), build summary.
