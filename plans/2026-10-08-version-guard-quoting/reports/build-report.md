# Build report: version-guard quoting

Result: PASS. All requested checks green.

## Changes

1. `tests/install-test.sh`
   - `vg_cmd` is the quoted string, `legacy_cmd` holds the old one; comment
     rewritten (legacy is migrated, not preserved).
   - New scenarios, with helpers `legacy_fixture`, `legacy_entry`, `vg_entries`,
     `empty_entries`: legacy only (one quoted entry, same matcher, report line,
     consumer hook and permissions kept, byte-identical second run); legacy
     rescoped to `Bash`; a requote that adds no hook (no "wired" line); legacy
     beside quoted, sharing an entry with a consumer hook and standing alone (no
     empty entry left); spaced-path scenario (`my consumer`, stub
     `version-guard.sh`, written command run via `sh -c`, legacy run in the same
     fixture as an anchor).
   - Red: `reports/red-install.txt`, run against the HEAD installer (a copy of
     the tree under $TMPDIR with HEAD's `install.sh`), the final test file. 14
     FAIL lines, each an assertion (string mismatch, missing report line, exit
     127, missing marker), none a setup error.
   - Passing on the unchanged installer by construction (guards against
     regressions in the fix, not red): the "second run byte-identical" asserts
     (nothing migrated yet, so nothing changes), `empty_entries == 0` in the
     lone-entry case (the old installer removes nothing), and the legacy anchor
     in the spaced scenario (it is a fixture check, expected to fail the
     command).
2. `toolkit/install.sh`
   - `hook_cmd` quoted; `legacy_hook_cmd` added with its SC2016 disable.
   - `add_hook` takes an optional 4th argument with the plan's contract (new
     present: drop legacy, drop entries left empty; else legacy present: rewrite
     `.command` in place; else append). Only the version-guard call passes it.
   - Reporting: `requoted` is read from the file before the write. A requote
     reports `settings.json (version-guard hook requoted)`; the "wired" line is
     kept when a command not previously in the file was added (or when nothing
     was requoted), so a requote alone does not claim hooks were wired. Added
     commands are found by `comm -13` over the distinct commands of old and new
     file (`settings_cmds`; residual bound noted: a command containing a newline
     reads as two).
3. Docs: `CLAUDE.md` Conventions bullet rewritten in place (four SC2016
   comments; all three live commands quoted; legacy migrated via the 4th
   argument). `docs/references/dogfood.md` paragraph rewritten (reflowed with
   `rumdl fmt` on that one file only). `docs/design.md` hub conclusion extended
   (it said the installer "only ever adds"). `toolkit/README.md` paragraph in
   "Installing in a plugin" (outside the fenced blocks doc-sync compares).
   `docs/references/version-guard.md` states no command string: unchanged. New
   `toolkit/migrations/v0.9.3.md`; record
   `docs/changelog/2026-10-08-version-guard-quoting.md` and its top bullet in
   `docs/changelog.md`.

## Checks (all run in the foreground, all rc 0)

`bash tests/install-test.sh`, `doc-sync-test.sh`, `docs-test.sh`,
`dist-tree-test.sh`, `citation-test.sh`, `update-plugin-dev-test.sh`;
`shellcheck toolkit/install.sh tests/install-test.sh`;
`bash -n toolkit/install.sh`. Not run (forbidden): `just precommit`,
`just format-docs`. `rumdl check` on the new/changed docs under `docs/` is clean
after the one-file fmt; `just format-docs` may still reflow other files.

## Probe

`reports/probe-spaced-path.txt`: scratch consumer at
`/tmp/probe dir/sp ace proj`, legacy settings. Legacy command via `sh -c` fails
(rc 126, because the path starts `/tmp/probe`, a directory; 127 in the test
fixture). Installer leaves one quoted entry under `Write|Edit`, prints the
requote line, the written command runs the stub with the spaced
`CLAUDE_PROJECT_DIR`, and the second run is "nothing to do" with byte-identical
settings.

## Deviations and notes

- Two legacy copies in one file would both be rewritten in place (two quoted
  copies result); not collapsed, since the consumer had two before.
- The probe and migration note's wording "exit 127" follows the plan.
- Version 0.9.3 in the migration note is the plan's guess for the release
  number.
- `settings.json` mode preservation is unchanged (write via redirection).

## Files to commit

fix: commit
- `toolkit/install.sh`
- `tests/install-test.sh`
- `plans/2026-10-08-version-guard-quoting/reports/red-install.txt`

docs: commit
- `CLAUDE.md`
- `docs/design.md`
- `docs/references/dogfood.md`
- `docs/changelog.md`
- `docs/changelog/2026-10-08-version-guard-quoting.md`
- `toolkit/README.md`
- `toolkit/migrations/v0.9.3.md`
- `plans/2026-10-08-version-guard-quoting/reports/probe-spaced-path.txt`
- `plans/2026-10-08-version-guard-quoting/reports/build-report.md`
