## Brief: dogfood shim should put the plugin's bin/ on PATH

2026-10-14

From the ghmem session (a consumer of the toolkit at 0.9.3). Written by an agent
for my human partner; the measurements below are real, the proposed shape is a
recommendation, not a decision.

### Decisions

- **Gap.** A plugin loaded through `CLAUDE_CODE_PLUGIN_DIRS` — what
  `plugin-dev/bin/claude` sets — gets no `bin/` on PATH. A marketplace install
  does. So a dogfood session cannot exercise a plugin's `bin/`, and anything
  that depends on it (a command shipped for agents' Bash) is untestable until it
  is released and installed.
- **Wanted.** The shim adds `<root>/dist/plugin/bin` to the PATH it execs
  `claude` with, only when that directory exists, **appended** after the user's
  entries. Claude Code appends marketplace plugins' `bin/` last and the docs say
  it cannot shadow `git` or `ls`; prepending would make dogfood differ from the
  release it is standing in for.
- **Applied locally, not by editing the toolkit's source.** ghmem's vendored
  `plugin-dev/bin/claude` carries a marked `LOCAL HACK` block after the
  `export PATH=...` line in `main()` doing exactly the above. It is a stopgap
  that the next `just update-plugin-dev dist-vX.Y.Z` overwrites; this brief is
  the way it comes back as the real thing.

- **Also record it as a design fact in the toolkit's docs.** It is a property of
  Claude Code that the shim's behaviour rests on, and the ghmem session routed
  it here instead of storing it as a ghmem memory. The fact: a
  marketplace-installed plugin's `bin/` is on PATH in the main thread's Bash and
  in a subagent's Bash, after the user's entries; a plugin loaded through
  `CLAUDE_CODE_PLUGIN_DIRS` gets none, and a `bin/` command there fails with
  `command not found`; hook-process PATH and a plugin-shipped agent's PATH are
  unmeasured. Consequence for plugin authors: hooks find their own scripts by
  `${CLAUDE_PLUGIN_ROOT}` or `$0`, never through `bin/`; `bin/` serves agents'
  and users' Bash. Version-stamp it (CC 2.1.299).

### Constraints

- The shim finds `<root>` from its own location and resolves it physically; keep
  that. `bin/` lives at the plugin root, which in the dogfood copy is
  `<root>/dist/plugin/bin`; a consumer without a `bin/` must see no change.
- `path_without` drops every PATH entry whose `claude` is the shim itself;
  append after that step, or the added directory is subject to the strip.
- `dogfood.sh sync` mirrors the tree with rsync; the executable bit on `bin/*`
  must survive it (rsync `-a` does; worth a bats case).
- Unrelated and untested here: whether hook commands see plugin `bin/` on PATH,
  and whether a plugin-shipped agent's Bash does (only a general-purpose
  subagent was measured). Do not make the shim promise either.

### Rejected approaches

- **Prepending `bin/`.** Diverges from marketplace behaviour (plugin `bin/`
  after the user's entries); a dogfood command could shadow a system one that
  the released plugin never shadows.
- **Telling consumers to add `bin/` to PATH themselves.** Every consumer's
  launch script, and the dogfood copy is what the shim already owns.
- **A stub-plugin probe to settle the question.** Tried in ghmem with a scratch
  `bin/ghmem` loaded by `CLAUDE_CODE_PLUGIN_DIRS`: the main thread's PATH lacked
  it and a plugin agent got `command not found`, which is what made the gap
  visible, but it could not say anything about subagents. The marketplace case
  was measured instead (below).

### Additional context

- **Measurements, CC 2.1.299.** Marketplace install: the main thread's PATH ends
  with `~/.claude/plugins/cache/ddaanet/handoff/0.15.0/bin`, and a
  general-purpose subagent's Bash resolves `command -v handoff-checkpoint` to
  that directory (it is entry 19 of its PATH). `CLAUDE_CODE_PLUGIN_DIRS`: the
  scratch plugin's `bin/` was absent from the main thread's PATH
  (`command -v ghmem; echo "$PATH"` run in the main thread).
- **Docs.** `https://code.claude.com/docs/en/plugins/components.md#executables`
  says only that `bin/` files are on the Bash tool's PATH "while the plugin is
  enabled". Hook PATH, plugin-agent PATH and reload behaviour are undocumented.
- **Why ghmem cares.** Its agents call a bare `ghmem`; today that comes from a
  `uv tool install`. A shipped `bin/ghmem` launcher would remove that, but could
  only be tested in dogfood once the shim does this.
- A positive acceptance check: with a `bin/` holding an executable stub in a
  dogfood copy, a session launched through the shim resolves it in the main
  thread's Bash (`command -v`) and in a subagent's.
