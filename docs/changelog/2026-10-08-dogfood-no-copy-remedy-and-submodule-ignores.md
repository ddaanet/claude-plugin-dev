# 2026-10-08 — The no-copy session warning names `just dogfood`, and the sync honours submodule ignores

The 0.9.1 dogfood in handoff
(`plans/2026-10-05-dogfood-drop-auto-sync/reports/dogfood-handoff.md`,
"Surprises") found two contradictions between `dogfood.sh` and its documented
behaviour. The outline for this pass is
`plans/2026-10-08-dogfood-0.9.2/outline.md`. It lands in 0.9.2, with no
migration note: a consumer picks both fixes up with the pull.

## `session-start` names `just dogfood` when there is no copy

With `<root>/dist/plugin` absent and `CLAUDE_CODE_PLUGIN_DIRS` unset, exactly
what the shim leaves after a launch with no copy, `session-start` told the human
to launch `claude` through `plugin-dev/bin/claude` from the repo root. The
session had been launched that way; the remedy is the promotion, as the shim's
own line and `toolkit/README.md` already said.

When no `<root>/dist/plugin` directory exists, the shim's own test, so a file in
its place counts as no copy, `systemMessage` now reads
`dogfood: no copy at <root>/dist/plugin, so this session does not load it; run just dogfood to create it, then relaunch`.
`additionalContext` states the fact, that no copy exists and the session loads
none, and names no command: promoting is the human's deliberate act, and a
sentence naming it would read to an agent as something to run. The check sits at
the warning, after the entry loop, so an entry naming the copy stays silent as
before. With the copy present, and with `jq` missing, the text is unchanged.

The red: the session-start suite failed eight assertions against 0.9.1, four per
case (copy absent, a file in its place):
`plans/2026-10-08-dogfood-0.9.2/reports/red-session-start.txt`. The suite also
pins the copy-present wording exactly, green by construction.
`tests/install-test.sh`, whose fixture has no copy, now looks for the no-copy
line when it runs the wired `session-start` command.

## The sync leaves out what a submodule ignores

The exclude list came from one root-level
`git ls-files -o -i --exclude-standard --directory`, which does not descend into
submodules; `--recurse-submodules` works only with `--cached`. In handoff,
`memory/.claude/`, ignored inside the `memory` submodule, reached the copy. A
submodule holding a `.venv` or build output would carry it too.

A recursive `list_ignored <dir> <prefix>` replaces the pipeline. It lists one
repo's ignored entries with the prefix prepended, then reads `ls-files -z -s`
for gitlinks, mode 160000, and recurses into each that holds a `.git`, file or
directory. `git submodule foreach` was not used: it runs its command under `sh`,
which has no `read -d ''`. Each git listing goes to its own scratch file and is
read from there on fd 3, never through a pipe, so a git failure anywhere ends
the script under errexit before the list is complete and before rsync runs. The
pattern-character refusal applies to the prefixed entry and now exits the script
directly rather than a pipeline subshell, so the header comment's account of
`pipefail` and SIGPIPE was removed with the pipeline.

The red: the sync suite failed on the two ignored `build/` directories, in a
submodule and in a submodule nested in it
(`plans/2026-10-08-dogfood-0.9.2/reports/red-sync.txt`); the refusal suite
failed six assertions on a git failure inside a submodule and a pattern
character inside one, run against 0.9.1's script in a scratch tree
(`plans/2026-10-08-dogfood-0.9.2/reports/red-sync-refusal.txt`). The submodule
fixture's git reads no global or system config.

## Docs

`docs/references/dogfood.md` describes the submodule listing and the no-copy
wording, by replacing words, and stays at 400 lines. `toolkit/README.md` lists
three session warnings and the submodule exclusion. No hub conclusion changed.
