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
  `claude` with, only when that directory exists. It is appended after every
  entry the user had, and skipped when an entry already names the directory in
  any spelling. The append comes after the strip of the shim's own entries and
  after the check for another `claude`, so a `claude` shipped in `bin/` is never
  exec'd as the next one. A copy with no `bin/` sees no change, and the shim
  still never syncs, leaves argv unchanged and launches without a copy.
- `tests/dogfood-launcher-path-test.sh` pins the append (a root holding a
  space), the no-repeat rule, no change without a `bin/`, and the shipped
  `claude` case. `tests/dogfood-sync-copy-test.sh` pins that a `bin/` file keeps
  its executable bit through `sync`.
- `docs/references/dogfood.md` records the Claude Code fact the behaviour rests
  on, and `docs/design.md` its one-line conclusion. `toolkit/README.md` and the
  CLAUDE.md layout line describe the shim's new step.

## The fact, version-stamped (CC 2.1.299)

A marketplace-installed plugin's `bin/` is on the PATH of the main thread's Bash
and of a general-purpose subagent's Bash, after the user's entries. A plugin
loaded through `CLAUDE_CODE_PLUGIN_DIRS` gets none. Hook-process PATH and a
plugin-shipped agent's PATH are unmeasured, so the shim promises neither.

## Why appended

Claude Code appends marketplace plugins' `bin/` last and its docs say it cannot
shadow system commands. Prepending would make dogfood differ from the release it
stands in for: a dogfood command could shadow a system one that the released
plugin never shadows. Telling every consumer to add `bin/` to PATH was rejected
because the dogfood copy is what the shim already owns.

No migration note: a consumer's next `update-plugin-dev` carries the shim, and
nothing is done by hand. A consumer that kept a local patch for this drops it.
