# 2026-10-05 — The dogfood shim stops syncing: `just dogfood` is the only promotion

`/deliverable-review` of the 2026-10-03 pass returned no Critical, 1 Major and 7
Minor findings, plus one item outside its range
(`plans/2026-10-03-dogfood-review-fixes/reports/deliverable-review.md`). The
outline for this pass is `plans/2026-10-05-dogfood-drop-auto-sync/outline.md`.
It lands in 0.9.1.

## The shim no longer syncs

Through 0.9.0 the shim ran `dogfood.sh sync` before its exec, so a relaunch
promoted the working tree. 0.9.0 added a skip for a `CLAUDE_CODE_PLUGIN_DIRS`
already equal to the copy. My human partner dropped the launch sync outright: it
had surprising effects, and restarting `claude` must not count as a deliberate
promotion. Every `claude` reaching the shim is a launch to it —
`claude --version`, a `claude mcp list` in a second terminal, each eval's
`claude -p` under a `just prerelease` run from the human's terminal — and each
re-promoted the tree repo-wide under every live session.

The shim now resolves its root physically, exports the variable, strips itself
from PATH and execs the next `claude` with argv unchanged, exiting 127 when
there is none, as before. The skip and the sync-failure path are gone, code,
tests and docs alike. When `<root>/dist/plugin` does not exist the shim starts
nothing, prints one `dogfood:` line naming `just dogfood`, and exits 1: a
session started anyway would load no plugin with nothing saying so, and creating
the copy would be a launch sync by another trigger. The check is for presence
only, with no staleness detection.

The cost is one more act: an agent definition or hook event goes live through
`just dogfood` and then a relaunch, and a fresh clone needs a first
`just dogfood` before it can launch. `install.sh`'s Next steps and both READMEs'
install flows say so, and `migrations/v0.9.1.md` gives an existing consumer the
step. `migrations/v0.9.0.md`'s closing paragraph, which described a launch-time
sync failure, now points at the 0.9.1 note instead; its steps are unchanged.

The red: the launcher suite's new scenarios — a launch with the variable unset
leaves the empty copy without its manifest, and a missing copy refuses with one
`dogfood:` line naming `just dogfood` and no exec — failed on nine assertions
against the 0.9.0 shim, and `install-test.sh`'s new check that the install
output names `just dogfood` failed on one.

## Corrections to the 2026-10-03 record

That record is not revised; these correct it.

- **Its premise for the skip was wrong (review Major 1).** It says an agent
  running `claude -p` inside a dogfood session re-promoted the tree under the
  live session. That route did not reach the shim even before the fix: the shim
  exports the PATH it stripped of its own entry, so the session and its Bash
  tool inherit a PATH without `plugin-dev/bin`, and an agent's `claude` finds
  the next one. The review's scratch-fixture probe saw no re-sync with the
  pre-fix shim either. The skip fired only where `plugin-dev/bin` came back on
  PATH inside a session — `direnv exec`, a script naming the shim. The syncs
  that did happen were the human's own, which the skip left syncing.
- **Its m2 probe is overstated (review minor 4).** "A sandboxed `just dogfood`
  was probed to copy a zero-byte sandbox mask" describes a simulated mask
  (`: > .mcp.json`, `chmod 444`) followed by an unsandboxed `dogfood.sh sync`,
  as the dogfood node says, not a sandboxed `just dogfood` observed end to end.
- **"Names" was the wrong word (review minor 2).** Its index bullet says the
  shim skipped when the variable "already names its own copy"; the skip was on
  whole-value equality, while "names" is `session-start`'s per-entry match. The
  skip is gone, so this only matters to a reader of that record.

## The other findings

- **Major 1, minor 2, minor 5** — moot with the launch sync gone: nothing
  depends on the skip's premise, and no `claude` subcommand promotes.
- **Minor 1** — the node's sandbox-mask bound says the exposure is any sync run
  through an agent's sandboxed Bash, `just dogfood` or `dogfood.sh sync`, since
  the shim never syncs; the manual says a launch is unaffected.
- **Minor 3** — the manual's Conventions say the gitmoji hook maps
  `release: X.Y.Z` to `🔖 X.Y.Z`, not `🔖 release X.Y.Z`.
- **Minor 6** — the past-the-shim fallback survives, narrowed to a copy the sync
  cannot create, and the manual gives it verbatim in bash and fish forms.
- **Minor 7** — `CLAUDE.md`'s stray "cuts the" wrap is joined.
- **Outside the range** — the hub's Limitations name
  `just update-plugin-dev dist-vX.Y.Z`, since a bare `vX.Y.Z` is refused.
