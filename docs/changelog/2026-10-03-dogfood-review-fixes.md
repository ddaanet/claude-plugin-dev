# 2026-10-03 — The dogfood launcher reviewed: a `claude` inside a dogfood session does not promote

`/deliverable-review` of the dogfood launcher returned no Critical, 2 Major and
12 Minor findings
(`plans/2026-09-26-dist-copy-dogfood-launcher/reports/deliverable-review.md`).
One of them changed a design decision; the rest are fixes to the code, the
suites and the prose. The fix outline is
`plans/2026-10-03-dogfood-review-fixes/outline.md`.

## The shim promoted on every `claude` it fronted

The shim synced the working tree into `dist/plugin/` and exported
`CLAUDE_CODE_PLUGIN_DIRS` on every invocation, whatever its arguments. In a
migrated consumer every `claude` a recipe or script runs from the direnv shell
goes through it — `claude --version`, `claude mcp …`, and gitlore's evals, which
start a `claude -p` per turn under `just prerelease`. Run by an agent inside a
dogfood session, each of those re-promoted the tree under the live session,
which is the half-edited-hook exposure "sync only on deliberate promotion"
exists to prevent. The outline's "Children inherit the variable" risk covered
only what a child loads, not what it syncs.

The review offered three venues: a shim-side opt-out variable, no sync for a
non-interactive argv, or a documented rule that scripts call the next `claude`.
My human partner took none of them. The shim now runs `dogfood.sh sync` unless
`CLAUDE_CODE_PLUGIN_DIRS` already equals `<root>/dist/plugin`, the physical root
it computes, and exports the variable in every case. A launch from a plain shell
syncs, `claude -c` included; a `claude -p` an agent runs inside a dogfood
session of the same repository inherits the variable and skips the sync; a
session in repository A whose `claude` reaches repository B's shim syncs B.
There is no `-p`/`--print` rule, so a `just prerelease` my human partner runs
from their own terminal still syncs on each eval's `claude -p`, accepted as a
deliberate act.

The variable already says whether a live dogfood session of this repository sits
underneath, which is the question that matters, and it reaches every child with
nothing for a script to set or remember. The argv rule keyed on the wrong axis,
and the opt-out and the documented rule both failed silently when a script
forgot them. D4 and D9 are rewritten in place in `docs/design.md` and
`docs/references/dogfood.md`, where the rejected venues are argued.

Left open: a script that wires the plugin's hooks into its own settings, as
gitlore's evals do, now loads the copy as well when run through the shim, and
whether its hooks then fire twice is unprobed.

## The other fixes in the same pass

Code, each with its red first:

- **m3** — a failed sync at launch keeps the sync's own stderr and adds
  `dogfood: sync failed, so claude was not started`, exiting with the sync's
  status. An rsync error alone did not say that no session started.
- **m1** — `pre-tool` exits 1 on any `jq` failure, reading the payload or
  building the deny, with `jq`'s stderr kept. It propagated `jq`'s own status
  before, and `jq` 1.6 exits 2 on a parse error (read from its source, not
  probed), which from a `PreToolUse` hook blocks the edit. The suite now asserts
  the exact status.

Tests, with the scripts unchanged:

- **Major 2**, reclassified by my human partner as a test gap of minor severity:
  `sync_copy`'s leading-`/` anchor was correct and unpinned. A fixture now
  tracks `skills/demo/build.log` beside an ignored root `/build.log`, and
  ignores root names beginning `- ` and `+ `, so dropping the anchor reds.
- **m10** — `pre-tool`'s payloads carry a `cwd` naming another directory.
- **m11** — the launcher's `the shim exports the copy` scenario exports
  `CLAUDE_PROJECT_DIR` naming another consumer.
- **m12** — the symlinked-spelling `session-start` case moved from the launcher
  suite into `tests/dogfood-session-start-test.sh`, which had no case invoking
  the script through a symlinked repository. The launcher suite tests only the
  shim.

Prose:

- **m2** — a sandboxed `just dogfood` was probed to copy a zero-byte sandbox
  mask, an empty `.mcp.json` among them, into the copy, including into a plugin
  that ships none; it stays until the next unsandboxed sync. The node's
  "zero-byte shape, unprobed" bound is settled, and the manual's advice to
  promote from the human's own shell no longer scopes itself to plugins that
  ship a `.mcp.json`.
- **m4** — `install.sh`'s closing output and both READMEs' install flows point a
  fresh install at the dogfood Setup, which the `SessionStart` warning otherwise
  reaches only through two failures.
- **m5, m6** — the v0.9.0 migration note's step 2 removes the `.bin` reference
  from a justfile line and deletes the line only when that reference is all it
  checks, since handoff's and sandbox-lies's lines name `.bin/*` beside other
  paths. The note names rsync as a requirement and how to launch by the next
  `claude`'s absolute path while the sync is broken.
- **m7** — the manual's list of what goes live when covers `commands/`,
  `.mcp.json` and output styles.
- **m8** — the hub's Motivation, and the front page, state the problem the
  launcher solves: a self-loaded plugin prompts on every edit and runs
  half-edited hooks.
- **m9** — the node's no-op sync timing is "across four repositories"; one of
  the four, edify, is not a toolkit consumer.

Two unprobed observations from the review stay out of scope: a nested
`CLAUDE.md` in the copy, and case-insensitive spellings of the copy path on
APFS.
