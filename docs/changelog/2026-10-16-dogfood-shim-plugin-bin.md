# 2026-10-16 — The dogfood shim puts the copy's `bin/` on PATH

A consumer (ghmem, at toolkit 0.9.3) found that a plugin loaded through
`CLAUDE_CODE_PLUGIN_DIRS`, which is what `plugin-dev/bin/claude` sets, gets no
`bin/` on PATH, while a marketplace install does. A dogfood session could not
exercise a command the plugin ships for agents' Bash. The consumer had patched
its vendored shim with a marked local block as a stopgap and sent a brief; the
patch is overwritten by the next `just update-plugin-dev`, so the behaviour
lands here.

## What changed

- `toolkit/bin/claude` appends `<root>/dist/plugin/bin` to the PATH it execs
  `claude` with, after every entry the user had, and sets
  `CLAUDE_CODE_PLUGIN_DIRS` at `<root>/dist/plugin`, both unconditionally. PATH
  is fixed at launch and a later `just dogfood` can create the directory in a
  running session; a PATH entry that names a missing directory is inert, so no
  probe for the copy or for `bin/` is made, and a repeated entry is inert too,
  so the walk that skipped an entry already on PATH is gone. The one remaining
  walk strips the shim's own entries. The append comes after that strip and
  after the check for another `claude`, so a `claude` shipped in `bin/` is never
  exec'd as the next one. The shim still never syncs and leaves argv unchanged.
  It no longer warns about a missing copy or leaves the variable as it came:
  probed on CC 2.1.301, claude starts cleanly with a plugin directory that does
  not exist (exit 0, answer on stdout, empty stderr, one load error in
  `/plugin`), and a headless `/reload-plugins` after the directory was created
  loaded it, 16 plugins and one error before, 17 and none after. So the first
  `just dogfood` of a running session needs `/reload-plugins`, not a relaunch.
  The interactive `/reload-plugins` was not run. `session-start` is silent in a
  shim session with no copy, since the variable names it; its no-copy line is
  unchanged and now reaches only a session that started past the shim.
- `tests/dogfood-launcher-bin-test.sh` is a new suite split from the path suite
  to stay under the 400-line cap. It pins the append last (a root holding a
  space), a copy without a `bin/`, no copy, and the shipped `claude` case. The
  exec suite pins a silent launch with no copy that exports the path and
  replaces an inherited value. `tests/dogfood-sync-copy-test.sh` pins that a
  `bin/` file keeps its executable bit through `sync`.
- `docs/references/dogfood.md` records the Claude Code fact the behaviour rests
  on, and `docs/design.md` its one-line conclusion. `toolkit/README.md` and the
  CLAUDE.md layout line describe the shim's new step.

## The fact, version-stamped (CC 2.1.299)

A marketplace-installed plugin's `bin/` is on the PATH of the main thread's Bash
and of a general-purpose subagent's Bash, after the user's entries. A plugin
loaded through `CLAUDE_CODE_PLUGIN_DIRS` gets none. Hook-process PATH and a
plugin-shipped agent's PATH are unmeasured, so the shim promises neither.

The shim sets PATH on the `claude` process, so hooks, MCP servers and plugin
agents inherit `bin/` in dogfood while a marketplace install is only known to
give it to the Bash tool. That is a known divergence the shim cannot close: a
hook calling a bare `bin/` command works in dogfood and may fail after release.

## Why appended

Claude Code appends marketplace plugins' `bin/` last and its docs say it cannot
shadow system commands. Prepending would make dogfood differ from the release it
stands in for: a dogfood command could shadow a system one that the released
plugin never shadows. Telling every consumer to add `bin/` to PATH was rejected
because the dogfood copy is what the shim already owns.

No migration note: a consumer's next `update-plugin-dev` carries the shim, and
nothing is done by hand. A consumer that kept a local patch for this drops it.
