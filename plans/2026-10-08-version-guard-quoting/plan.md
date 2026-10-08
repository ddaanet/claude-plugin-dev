# Quote the version-guard hook command — plan

Promoted from an inbox brief written by a session in sandbox-lies (deliverable
review finding m-8, 2026-10-07). My human partner chose option (a) on
2026-10-08: quote the command and migrate the legacy entry in place. Ships in
the next patch release with the wording corrections already committed.

## Problem, verified

`toolkit/install.sh` writes the version-guard hook as
`bash ${CLAUDE_PROJECT_DIR}/plugin-dev/version-guard.sh`, unquoted. The hook
shell word-splits a project path that holds a blank: probed with a project dir
`sp ace proj`, bash reports `No such file or directory` for `.../sp`. Exit 127
is a non-blocking hook error, so the guard fails open and nothing says so. The
two dogfood hooks beside it already quote the variable.

Quoting `hook_cmd` alone is unsafe. `add_hook` counts a hook present only on an
exact `.command` match, so a re-run on an existing consumer would append a
second, quoted guard beside the old one, firing twice and still failing on the
spaced path. `update.sh` never rewires `settings.json`, so existing consumers
keep the legacy entry until they re-run `install.sh`, which is idempotent and
safe on a vendored tree (documented; `migrations/v0.9.0.md` already asks for
it).

## Changes

### 1. `toolkit/install.sh`

- `hook_cmd` becomes the quoted form, the same shape as `pretool_cmd`.
- A `legacy_hook_cmd` holds the old unquoted string, kept as a constant for the
  migration only.
- `add_hook` gains an optional fourth argument, the legacy command. Contract:
  - new command present under the event: any legacy entry is removed (an entry
    left with no hooks is dropped), nothing else changes;
  - else legacy present: its `.command` is rewritten in place, so the matcher
    the consumer may have rescoped it to survives;
  - neither present: appended as today.
- Only the version-guard call passes the legacy argument.
- The run reports the rewrite as a change
  (`settings.json (version-guard hook requoted)`), so a migrated consumer sees
  it and a second run is still "already installed, nothing to do".
- The `SC2016` comments above `hook_cmd` stay load-bearing; add one for the
  legacy constant.

### 2. Tests (`tests/install-test.sh`, one script under test)

- `vg_cmd` (line ~229) becomes the quoted string; its comment explains the
  legacy spelling is migrated, not preserved.
- Migration scenarios, each red first against the unchanged installer:
  - legacy entry only: after a re-run, exactly one version-guard entry, the new
    string, same matcher;
  - legacy entry rescoped to another matcher: rewritten under that matcher;
  - legacy and new both present: one entry left, the new string;
  - second run after migration: byte-identical settings.json.
- Spaced-path scenario: install into a consumer under a directory with a space,
  take the command string the installer wrote, run it with `sh -c` and
  `CLAUDE_PROJECT_DIR` set to that directory, against a stub `version-guard.sh`
  that records it ran. It must run; the legacy string must demonstrably fail in
  the same fixture (the red).
- Existing scenarios that pin dedup on the command alone keep passing unchanged
  apart from the string.

### 3. Docs

- `CLAUDE.md` Conventions: the `${CLAUDE_PROJECT_DIR}` bullet currently says
  `hook_cmd` leaves it bare and stays so. Rewrite in place: all three commands
  quote it, and the legacy unquoted string is migrated by `add_hook`'s legacy
  argument. Keep the `SC2016` sentence.
- `docs/references/dogfood.md` ("`install.sh` wires the hooks", the paragraph
  ending "The version-guard's string stays unquoted") and
  `docs/references/version-guard.md` if it states the string: rewrite present
  tense with the reasoning (fail-open on a spaced path; exact-match dedup forces
  the migration). `docs/design.md` only if a hub conclusion states it.
- `toolkit/README.md`: the install section's hook description, kept in step with
  `tests/doc-sync-test.sh`.
- New `toolkit/migrations/v0.9.3.md` (named for the release that ships it; if
  the release number differs, rename): re-run `bash plugin-dev/install.sh` from
  the human's own shell, not an agent's sandboxed Bash, which refuses writes to
  `.claude/settings.json`; check `grep version-guard .claude/settings.json`
  shows one quoted entry. `tests/dist-tree-test.sh` already allows
  `migrations/vX.Y.Z.md`; no list change.
- Dated record `docs/changelog/2026-10-08-version-guard-quoting.md` and its
  index bullet.

## Process

Red runs saved under `reports/`, then the fix, docs, `just precommit` (run by
the main session, not a subagent), one `fix:` commit with tests and red file and
one `docs:` commit. Then `just release patch`; the dist tag carries the
migration note. Dogfood the day it ships: `just update-plugin-dev` in handoff
(whose path has no space) followed by the migration step, and a throwaway
consumer under a spaced path.

## Open

- Whether other consumers' paths contain spaces is unknown; the fix is needed
  regardless, since the guard fails open silently.
- The 2026-09-01 shell audit plan quotes the unquoted string without flagging
  it; frozen, left as written.
