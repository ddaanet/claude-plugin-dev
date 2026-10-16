# 2026-10-16 — Gate sentinels and the quiet bats runner ship as an opt-in

handoff's release printed several hundred lines of bats TAP and re-ran its whole
gate on a tree it had just passed. gitlore already had answers to both: a quiet
`scripts/run-bats.sh`, and gate sentinels in its justfile's `bash_prolog`. My
human partner judged they belong in the toolkit rather than copied per plugin,
and the brief left five points open. The choices below were taken by the
implementing session, to be overridden if wrong.

## What changed

- `toolkit/gates.just` is new. Imported by a consumer, it defines the private
  `plugin_dev_gate_prolog`, which a gate recipe interpolates as its shebang. It
  carries `sentinel-guard`, `check-sentinel`, `record-sentinel` and
  `gate-inputs-hash`, ported from gitlore with the names changed.
- `toolkit/run-bats.sh` is new: gitlore's runner with the log prefix
  `plugin-dev-bats.`.
- `toolkit/docs/gates.md` is the manual chapter, with a stub section in
  `toolkit/README.md`, which sits at 393 lines.
- `toolkit/migrations/v0.11.0.md` converts an existing `precommit`, and has its
  own section for gitlore.
- Design: `docs/references/gates.md` is new, with its conclusions in the hub.

## Decisions taken for the open points

1. **Names.** `PLUGIN_DEV_GATE_DIR`, `PLUGIN_DEV_GATE_FORCE`, the gitdir path
   `plugin-dev/gates`, the log prefix `plugin-dev-bats.`. No aliases for the
   gitlore spellings. `GITLORE_TEST_JOBS` is not ported, since `run-suites` is
   not.
2. **Tool versions** are an exported `PLUGIN_DEV_GATE_TOOLS` in the consumer's
   justfile, one shell command per line, empty by default. A just variable
   defined in the import and overridden by the importer was not tried: whether
   just allows the same name on both sides was not established.
3. **No allow-list drift check ships.** The rule that every check reads inside
   the list is in the manual.
4. **One guard per body** is documented and enforced: the prolog exits on a
   second `check-sentinel`.
5. **Opt-in** as a separate importable file. `release.just` and the
   `precommit`/`prerelease` contract are as they were.

The migration note is `v0.11.0.md`, a minor, because this is a feature.
`toolkit/VERSION` was 0.10.0 and 0.10.1 was not yet cut; if 0.10.1 releases
first as a patch and this lands as 0.10.2, the note must be renamed to match,
since `update.sh` prints notes by the version they are named for.

## Differences from gitlore's functions

- The refusals are new: a second gate in one body, `record-sentinel` with no
  guard, a guard with no pathspec, a gate name with a `/`, and a missing
  sentinel directory. gitlore had none of them, and its `check-sentinel` would
  have carried on past a failed `mkdir` or an unset gitdir.
- The tool versions are not hashed by default.
- A gitlink was found to hash by name only: neither an edit inside the submodule
  nor a new commit of it moves the hash. gitlore's comment had it as "one path
  and nothing to `cat`"; the commit is invisible too.

## Tests

`tests/run-bats-test.sh` drives the runner against a stub `bats`.
`tests/gates-sentinel-test.sh` and `tests/gates-guards-test.sh` run real `just`
recipes in a fixture consumer whose path holds a space; the second also runs
`shellcheck` over the evaluated prolog. Each was written before the file it
tests existed and failed on assertions first. `_import-check` now imports
`gates.just` beside `release.just`.
