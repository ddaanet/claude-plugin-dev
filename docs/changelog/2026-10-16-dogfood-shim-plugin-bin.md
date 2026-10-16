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
  `claude` with whenever `dist/plugin` exists, whether or not it holds a `bin/`
  yet: PATH is fixed at launch and a later `just dogfood` can create the
  directory in a running session, and a missing PATH directory is harmless. It
  is appended after every entry the user had, and skipped when an absolute entry
  already names the directory, spelled alike or the same by `-ef`. An empty or
  relative entry never counts, since it names the launch directory and would
  suppress the append for a launch from elsewhere. The append comes after the
  strip of the shim's own entries and after the check for another `claude`, so a
  `claude` shipped in `bin/` is never exec'd as the next one. One walk of PATH
  does the strip and the already-listed test. No copy adds nothing, and the shim
  still never syncs, leaves argv unchanged and launches without a copy.
- `tests/dogfood-launcher-bin-test.sh` is a new suite split from the path suite
  to stay under the 400-line cap. It pins the append (a root holding a space),
  the no-repeat rule, a copy without a `bin/`, no copy, empty and relative
  entries, and the shipped `claude` case. `tests/dogfood-sync-copy-test.sh` pins
  that a `bin/` file keeps its executable bit through `sync`.
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
