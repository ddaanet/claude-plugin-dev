# 2026-10-05 — The dogfood shim stops syncing: `just dogfood` is the only promotion

`/deliverable-review` of the 2026-10-03 pass returned no Critical, 1 Major and 7
Minor findings, plus one item outside its range
(`plans/2026-10-03-dogfood-review-fixes/reports/deliverable-review.md`). The
outline for this pass is `plans/2026-10-05-dogfood-drop-auto-sync/outline.md`.
It lands in 0.9.1.

## The shim no longer syncs

The shim, new in 0.9.0, ran `dogfood.sh sync` before its exec, so a relaunch
promoted the working tree, except when `CLAUDE_CODE_PLUGIN_DIRS` already
equalled the copy: the shim and that skip both arrived in 0.9.0, and no release
before it had a shim. My human partner dropped the launch sync outright: it had
surprising effects, and restarting `claude` must not count as a deliberate
promotion. Every `claude` reaching the shim is a launch to it —
`claude --version`, a `claude mcp list` in a second terminal, each eval's
`claude -p` under a `just prerelease` run from the human's terminal — and each
re-promoted the tree repo-wide under every live session.

The shim now resolves its root physically, exports the variable, strips itself
from PATH and execs the next `claude` with argv unchanged, exiting 127 when
there is none, as before. The skip and the sync-failure path are gone, code,
tests and docs alike. When `<root>/dist/plugin` is not a directory the shim
prints one `dogfood:` line naming `just dogfood`, leaves
`CLAUDE_CODE_PLUGIN_DIRS` as it came and launches anyway, so `session-start`
reports a session without the copy; creating the copy would be a launch sync by
another trigger. The check is for presence only, with no staleness detection.
This pass first built a refusal there, exit 1 and nothing started; it was
replaced before release (below).

The cost is one more act: an agent definition or hook event goes live through
`just dogfood` and then a relaunch, and a fresh clone needs a first
`just dogfood` before a launch loads the plugin. `install.sh`'s Next steps and
both READMEs' install flows say so, and `migrations/v0.9.1.md` gives an existing
consumer the step. `migrations/v0.9.0.md`'s closing paragraph, which described a
launch-time sync failure, now points at the 0.9.1 note instead; its steps are
unchanged.

The red: the launcher suite failed on nine assertions against the 0.9.0 shim,
seven in the two new scenarios — a launch with the variable unset leaves the
empty copy without its manifest, and a missing copy refuses with one `dogfood:`
line naming `just dogfood` and no exec — and two in the rewritten
inherited-variable and 127 scenarios; and `install-test.sh`'s new check that the
install output names `just dogfood` failed on one.

## After the review: the sync refuses without rsync, a launch with no copy warns

Major 1 of this pass's deliverable review
(`plans/2026-10-05-dogfood-drop-auto-sync/reports/deliverable-review.md`) found
that `dogfood.sh sync` made `dist/plugin` before it ran `rsync`. With `rsync`
missing, a first `just dogfood` failed with the shell's `command not found` and
left an empty copy, which the shim's presence check passed: the session loaded
an empty plugin dir and nothing said so. The sync now refuses without `rsync` on
PATH, a fourth refusal beside the manifest, the ignore check and a pattern
character: one `dogfood:` line naming `rsync`, exit 1, before `dist/` is
touched. A refused first sync therefore leaves no copy, and the next launch says
so. Red: the sync-refusal suite's new scenario failed on three assertions
against the unchanged script — exit 127 for 1, `rsync`'s `command not found` for
the `dogfood:` line, and `dist/plugin` created.

My human partner then replaced the refusal of a launch with no copy, before it
shipped, with the warning described above: a launch while the copy cannot be
made, `rsync` missing say, still reaches `claude`, and `session-start` reports
the plain session. The manual's past-the-shim fallback, kept for that case in
bash and fish forms, is gone with it, which settles the review's minor 7 (the
zsh form, unprobed against zsh's `which` builtin) by removal. The review's Major
2, a test pinning exit 1 over 127, is moot: with no copy and no other `claude`
the shim prints the warning, then the 127 line, and exits 127. Red: the reworked
launcher scenarios — a missing copy warns and execs with argv intact and the
variable unset, an inherited value passes through, a file at `dist/plugin` is no
copy, and no copy with no other `claude` prints both lines and exits 127 —
failed on eleven assertions against the refusing shim. A mutant relaxing `-d` to
`-e` fails the file scenario, and one moving the copy check below the `claude`
lookup fails the two-line one.

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
  that did happen ran with `plugin-dev/bin` on PATH and the variable unset: the
  human's own terminal, or a session started past the shim, the 0.9.0 manual's
  fallback included, where an agent's `claude -p` reached the shim and synced
  inside the sandbox. The skip left all of them syncing.
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
- **Minor 6** — the past-the-shim fallback was first narrowed to a copy the sync
  cannot create and given verbatim in bash and fish forms; it was then removed
  before release, since a launch with no copy now starts `claude` (above).
- **Minor 7** — `CLAUDE.md`'s stray "cuts the" wrap is joined.
- **Outside the range** — the hub's Limitations name
  `just update-plugin-dev dist-vX.Y.Z`, since a bare `vX.Y.Z` is refused.
