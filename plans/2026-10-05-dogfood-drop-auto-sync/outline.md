# Outline — the dogfood shim stops syncing (0.9.1)

Input: `plans/2026-10-03-dogfood-review-fixes/reports/deliverable-review.md` (1
Major, 7 Minor, one item outside the range). Lands in patch release 0.9.1;
releasing is not part of this job.

## Decisions

My human partner's decision, not open: **the shim no longer syncs.** A launch, a
relaunch or any other `claude` through the shim is not a promotion;
`just dogfood` is the only one.

Defaults applied, each overridable:

1. **The shim keeps** physical root resolution, the export of
   `CLAUDE_CODE_PLUGIN_DIRS=<root>/dist/plugin`, the PATH strip, exit 127 with
   no other `claude`, and the exec with argv unchanged. The skip on a variable
   equal to the copy and the sync-failure path go entirely: code, tests, header
   comment, docs. No compat leftovers.
2. **A missing copy refuses the launch** (replaced 2026-10-06, see the last
   section). When `<root>/dist/plugin` is not a directory the shim starts
   nothing, prints one `dogfood:` line naming `just dogfood`, and exits 1. The
   check comes before the PATH strip. No staleness detection.
3. **Docs are rewritten in place** (hub, dogfood node, both READMEs, the
   `CLAUDE.md` Layout bullet, `install.sh` Next steps); a new
   `toolkit/migrations/v0.9.1.md` carries the by-hand step. A new dated record
   `docs/changelog/2026-10-05-the-shim-stops-syncing.md` carries the reversal
   and the corrections to the 2026-10-03 record (Major 1's premise, minor 4's
   probe, minor 2's "names"); the 2026-10-03 record is not edited.
4. **`toolkit/migrations/v0.9.0.md`'s closing paragraph is rewritten**, not left
   describing a launch-time sync: it is shipped guidance, printed only to
   consumers crossing into a tree whose shim no longer syncs, and not a dated
   record. Its steps 1-4 stand. (Overridable: leaving it and relying on the
   v0.9.1 note printed after it.)
5. **The broken-sync fallback survives in narrower form** (reversed 2026-10-06,
   see the last section): with no copy and a sync that cannot create one (rsync
   missing, say), launch past the shim. Given verbatim, bash and fish forms
   (minor 6).

## Work items

1. Tests first — `tests/dogfood-launcher-test.sh`: the fixture starts with a
   copy; new scenarios "a launch does not sync, the variable unset" and "a
   missing copy refuses the launch"; drop the skip, glob-skip, list-syncs,
   sync-before-exec, failed-sync and failed-rsync scenarios; trim the 127
   scenario's tool list to what the shim runs. `tests/install-test.sh`: the
   install output names `just dogfood`. Record the red.
2. Code — `toolkit/bin/claude` (header and body), `toolkit/install.sh` Next
   steps.
3. Docs — `docs/design.md` (Requirements, D4, failed-sync and shim decisions,
   new missing-copy decision, Limitations' `dist-vX.Y.Z`),
   `docs/references/dogfood.md` (problem, promotion section with the launch sync
   rejected, sync failure, shim, bounds, minor 1), `toolkit/README.md`
   (component list, Setup, Launching, Promoting, Conventions minor 3),
   `README.md`, `CLAUDE.md` (Layout bullet, minor 7), migrations, changelog.
4. `just precommit` green in the foreground; commits by explicit path.

## Review findings

- Major 1, minor 2, minor 5: moot once the shim stops syncing; verify no doc
  still describes the skip or a launch-time sync.
- Minor 1: re-word for "the shim never syncs".
- Minor 3: `release: X.Y.Z` lands as `🔖 X.Y.Z`.
- Minor 4: corrected in the new dated record.
- Minor 6: verbatim fallback where the text survives.
- Minor 7: `CLAUDE.md` wrap.
- Outside the range: hub Limitations names `dist-vX.Y.Z`.

## Deliverable-review fixes (2026-10-06)

My human partner's decisions on `reports/deliverable-review.md`; what was done
is in `reports/review-fixes.md`.

- **Decision 2 replaced: a missing copy warns and launches.** When
  `<root>/dist/plugin` is not a directory the shim prints one `dogfood:` line
  saying there is no copy, that `claude` starts without it, and that
  `just dogfood` creates it; it does not export `CLAUDE_CODE_PLUGIN_DIRS`,
  leaving whatever the environment had, and goes on to the PATH strip, the 127
  check and the exec with argv unchanged. `session-start` then reports the plain
  session. With a copy, behaviour is unchanged.
- **Decision 5 reversed: no fallback.** A launch with no copy runs `claude`, so
  the past-the-shim command blocks go from the manual, the notes, the node and
  the hub.
- **Major 1:** `dogfood.sh sync` refuses without `rsync` on PATH, checked before
  it creates `<root>/dist/plugin`: a fourth refusal, same style and channel as
  the other three. A failed first `just dogfood` leaves no directory, so the
  next launch warns instead of loading an empty copy in silence. Tests first,
  red recorded.
- **Major 2:** moot under the new decision 2. Replaced by a scenario for no copy
  and no other `claude`: the warning line, then the 127 line, rc 127.
- **Minor 9:** a regular file at `dist/plugin` is no copy (warning, no export),
  red against an `-e` mutant.
- **Minors 1, 5, 6:** hub and node present-tense, the rejected launch sync
  argued in the conditional, "every `claude` that reaches the shim"; "and
  children" dropped from the hub.
- **Minors 2, 3, 4:** the 2026-10-05 record amended in place (unshipped), with
  the rsync refusal and the replaced refusal added. The 2026-10-03 record is
  untouched.
- **Minor 7:** resolved by removal of the fallback (decision 5 reversed).
- **Minor 8:** smallest edit reaching `just dogfood` from a hand-read v0.9.0
  note: the manual's pointer and the note's closing paragraph.
