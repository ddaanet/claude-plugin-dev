# 2026-10-08 — The version-guard hook command quotes the project dir, and the installer migrates the old one

`toolkit/install.sh` wrote the version-guard hook as
`bash ${CLAUDE_PROJECT_DIR}/plugin-dev/version-guard.sh`, the variable bare. The
hook shell word-splits a project path that holds a blank: with a project dir
`sp ace proj`, bash reported `No such file or directory` for `.../sp`. Exit 127
is a non-blocking hook error, so the guard failed open and nothing said so. The
two dogfood hooks beside it already quoted the variable. A deliverable review of
sandbox-lies raised it (finding m-8, 2026-10-07), and my human partner chose to
quote the command and migrate the legacy entry in place.

## Quoting alone was not enough

`add_hook` counts a hook present only on an exact `.command` match. Quoting
`hook_cmd` by itself would have made every existing consumer's next run append a
quoted guard beside the unquoted one, firing twice and still failing on a spaced
path. `update.sh` never rewires `settings.json`, so existing consumers keep the
unquoted entry until they re-run `install.sh`, which is idempotent and safe on a
vendored tree.

## What changed

`hook_cmd` is the quoted spelling, the same shape as the dogfood commands. The
unquoted one survives as `legacy_hook_cmd`, a constant read only to find and
migrate it. `add_hook` takes the legacy command as an optional fourth argument,
and only the version-guard call passes it:

- the new command present: any legacy entry is removed, and an entry left with
  no hooks is dropped;
- else the legacy command present: its `.command` is rewritten in place, so a
  matcher the consumer rescoped it to survives;
- neither present: appended, as before.

The run reports the rewrite as `settings.json (version-guard hook requoted)`, so
a migrated consumer sees it, and the "wired the version-guard and dogfood hooks"
line is kept for runs that add a hook. A second run is "already installed,
nothing to do".

## Tests

`tests/install-test.sh` pins the new string and adds migration scenarios: a
legacy entry only; a legacy entry rescoped to another matcher; legacy and quoted
both present, with the legacy command sharing an entry with a consumer hook and
standing alone; a requote that adds no hook; and a second run that leaves
`settings.json` byte-identical. A spaced-path scenario takes the command the
installer wrote, runs it through `sh -c` with `CLAUDE_PROJECT_DIR` set to a
directory holding a space against a stub `version-guard.sh`, and runs the legacy
spelling in the same fixture to show it fails there. Against the unchanged
installer 14 assertions fail, each on its own; the output is
`plans/2026-10-08-version-guard-quoting/reports/red-install.txt`.

## Docs and migration

`CLAUDE.md`'s `${CLAUDE_PROJECT_DIR}` convention, the hub conclusion in
`docs/design.md`, `docs/references/dogfood.md` and `toolkit/README.md` state the
quoted command and the migration in the present tense. The reference node's
sentence that the version-guard string "stays unquoted" is rewritten. A new
`toolkit/migrations/v0.9.3.md` asks for a re-run of `install.sh` from the
maintainer's own shell and a `grep` for one quoted entry; it is named for the
release expected to ship it and is renamed if the number differs.

The 2026-09-01 shell audit plan quotes the unquoted string without flagging it;
it is frozen and left as written.
