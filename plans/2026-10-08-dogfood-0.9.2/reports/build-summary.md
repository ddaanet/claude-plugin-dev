# Build summary — dogfood 0.9.2

Two fixes from the 0.9.1 dogfood in handoff
([report](../../2026-10-05-dogfood-drop-auto-sync/reports/dogfood-handoff.md),
"Surprises"). Outline: [outline.md](../outline.md). Nothing outside this repo
was touched; no release was cut.

## What changed

1. **`session-start` with no copy** (`toolkit/dogfood.sh` `session_start`).
   After the entry loop, when `<root>/dist/plugin` is not a directory (the
   shim's own `-d` test, so a file in its place counts as no copy):
   - `systemMessage`:
     `dogfood: no copy at <root>/dist/plugin, so this session does not load it; run just dogfood to create it, then relaunch`
   - `additionalContext`:
     `No copy exists at <root>/dist/plugin, so this session loads none; plugin behaviour observed in it does not come from that path.`
     It names no command and no sync or promotion (withheld per
     `craft:directive-writing`).
   - Copy present, session not loading it: text unchanged. `jq` missing:
     unchanged. An entry naming the copy stays silent, copy or not.
2. **Submodule ignores** (`toolkit/dogfood.sh` `sync_copy`, new
   `list_ignored <dir> <prefix>`). Per repo,
   `ls-files -z -o -i --exclude-standard --directory` and `ls-files -z -s` each
   go to their own scratch file under one `mktemp -d` (EXIT trap `rm -rf`), read
   with `read -r -d '' -u 3`; gitlinks (mode 160000) holding a `.git` recurse
   with the prefix extended. No pipe, no process substitution, no grep, no
   `git submodule foreach`. The pattern refusal runs on the prefixed entry and
   now exits the script directly; the header comments were rewritten (the
   pipeline/SIGPIPE/pipefail account removed, the errexit guarantee restated for
   the recursion).

## Tests

- `tests/dogfood-session-start-test.sh`: copy absent and copy replaced by a
  file, variable unset → `systemMessage` names `just dogfood` and not
  `launch claude through`; `additionalContext` contains `no copy exists` and
  none of `just dogfood`, `sync`, `promote`. Copy present, variable unset →
  exact pin of today's two strings.
- `tests/dogfood-sync-test.sh`: `sub/` (a real `submodule add` from a local
  path) and `sub/inner/` (a nested submodule), each ignoring its own `build/`
  and tracking `tool.md`; preconditions pin each submodule's ignore list and the
  superproject's empty one. Copy: `tool.md` present, `build/` and `.git` absent,
  at both levels. Fixture git runs with
  `GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1`, identity and
  `protocol.file.allow=always` by `-c`.
- `tests/dogfood-sync-refusal-test.sh` (added beyond the brief, to prove the
  errexit and refusal guarantees reach the recursion): a stub git failing
  `ls-files` only under `-C …/memory` → non-zero, the stub's line on stderr, no
  `dist/`; a submodule-ignored `memory/a*b.log` → exit 1, one `dogfood:` line
  naming `memory/a*b.log`, no `dist/`.

## Red evidence

- [red-session-start.txt](red-session-start.txt) — 8 failures against 0.9.1, all
  on the new assertions (4 per case). The copy-present pin passed, as a
  regression pin must.
- [red-sync.txt](red-sync.txt) — 2 failures: `sub/build` and `sub/inner/build`
  exist in the copy.
- [red-sync-refusal.txt](red-sync-refusal.txt) — 6 failures, run in a scratch
  tree holding HEAD's `dogfood.sh` (the suite copies the script from
  `toolkit/`).

## Docs

- `docs/references/dogfood.md`: the source set (submodule recursion, prefixed
  entries), the merged list-in-full sentence, the no-copy launch paragraph and
  the session check's channels. 399 → 400 lines after `just format-docs`, at the
  cap: the next addition to this node needs a split.
- `toolkit/README.md`: the `dogfood.sh` entry, the sync paragraph, and the
  Session check (three warnings, each explained).
- Hub unchanged (no conclusion flipped). CLAUDE.md Layout still true.
- `docs/changelog/2026-10-08-dogfood-no-copy-remedy-and-submodule-ignores.md`
  and its index bullet. No migration note.

## Precommit

Green (`just precommit`, rc 0, run on the full working tree before the
commits, and again by the pre-commit hook on each commit). Passed: whitespace,
format-docs (rumdl; only pre-existing MD013 warnings on unbreakable lines),
shellcheck over every toolkit script, `bash -n` over every suite,
`_import-check`, then version-guard, check-version, release, self-release,
update-plugin-dev, install (`install.sh scenarios passed`), dist-tree (11
files), docs (cap 400, pointers resolve), doc-sync (5 shared blocks, Layout
matches `toolkit/`), citation, dogfood sync, sync refusal, pre-tool,
session-start and launcher suites.

The first full run failed one assertion outside the brief's two suites:
`tests/install-test.sh` ran the wired `session-start` command in a fixture with
no copy and looked for `does not load <copy>`. It now looks for
`no copy at <copy>`, which still proves the written command reached the check.

## Commits

- `55cce9f` `🐛 dogfood session-start names just dogfood with no copy, sync
  honours submodule ignores` — script, the four test files, outline, red files.
  The gitlore pre-commit hook also staged the `memory` gitlink into it (the
  submodule had moved before this session; not staged by hand).
- The `docs:` commit carrying this report — `docs/references/dogfood.md`,
  `toolkit/README.md`, the changelog record and index bullet, this file.

## Left open

- `docs/references/dogfood.md` sits at exactly 400 lines.
- An entry in `CLAUDE_CODE_PLUGIN_DIRS` naming the copy path while no copy
  exists is still silent (unchanged, documented design); only the warning branch
  checks for the copy.
- Not dogfooded in handoff: that repo is out of scope for this session.
