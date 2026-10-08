# Probe: four unprobed dogfood claims

2026-10-08, Claude Code 2.1.294, jq 1.7 installed, rsync 3.x, Linux. Nothing
tracked was edited. Scratch material lives under `/tmp/claude/unprobed/`
(`$TMPDIR` is `/tmp` for an unsandboxed command). Every `claude` call ran
unsandboxed, through `/tmp/claude/unprobed/cc.sh`, a wrapper that `exec`s the
real binary from `$CLAUDE_CODE_EXECPATH` with every parent `CLAUDE*` variable
unset and `GITLORE_LAUNCHED=1` (the PATH `claude` here is gitlore's shim). Nine
`claude -p` runs in total, plus one tmux interactive session.

Verdicts: 1 twice, 2 accepted silently (logged at error level, flagged only by
`plugin validate`), 3 all three go live, 4 not probed on 1.6 (no published
checksum); 1.6 source says 4, not 2; the guard exits 1 whatever the status.

## 1. Hooks firing twice under the shim

### Procedure

Scratch root `/tmp/claude/unprobed/p1/`:

- `src/` is a root-layout plugin (`p1plug`), `copy/` an `rsync -a` of it, and
  `proj/.claude/settings.json` the project settings. `copy/` is loaded with
  `CLAUDE_CODE_PLUGIN_DIRS=/tmp/claude/unprobed/p1/copy`, cwd `proj/`.
- The hook script appends `"$1 script=$0 pid=$$"` to `p1/log.txt`.
- Three events, each registered as follows:
  - `SessionStart` (case A): the same absolute command string in
    `hooks/hooks.json` and in `settings.json`
    (`/tmp/claude/unprobed/p1/shared/hook.sh A-identical`).
  - `UserPromptSubmit` (case B, the gitlore shape): the plugin's `hooks.json`
    says `${CLAUDE_PLUGIN_ROOT}/hook.sh B-resolved-differs`, the settings file
    the resolved path into the source tree (`.../p1/src/hook.sh ...`).
  - `Stop` (case C, control): plugin only.
- Run 1:
  `cc.sh proj -p --model haiku --output-format stream-json --verbose "Reply with the single word ok."`
  with the variable set.
- Run 2: the same without the variable (control: settings alone).
- Run 3: the same as run 1 with
  `--setting-sources project --permission-mode bypassPermissions --output-format json`,
  the flags of gitlore's `claude-runner.sh`.

### Evidence

Run 1 (variable set), `log.txt`:

```text
A-identical script=/tmp/claude/unprobed/p1/shared/hook.sh pid=372021
A-identical script=/tmp/claude/unprobed/p1/shared/hook.sh pid=372068
B-resolved-differs script=/tmp/claude/unprobed/p1/src/hook.sh pid=372121
B-resolved-differs script=/tmp/claude/unprobed/p1/copy/hook.sh pid=372124
C-plugin-only script=/tmp/claude/unprobed/p1/copy/hook.sh pid=372204
```

Run 2 (no variable):

```text
A-identical script=/tmp/claude/unprobed/p1/shared/hook.sh pid=373130
B-resolved-differs script=/tmp/claude/unprobed/p1/src/hook.sh pid=373406
```

Run 3 (variable, `--setting-sources project`): the same five lines as run 1,
four distinct pids for A and B. The init event listed `p1plug@inline` at the
`copy/` path.

### Conclusion (CC 2.1.294)

Claude Code runs the hook twice. It does not de-duplicate a hook registered by a
plugin (loaded through `CLAUDE_CODE_PLUGIN_DIRS`) and by a settings file, even
when the two command strings are byte-identical (case A, two pids). With
differing strings (case B) there is of course no chance of de-duplication, and
the two scripts are different files. `--setting-sources project` does not stop
the variable's plugin from loading.

### Gitlore's evals

Established by reading `/Users/david/code/gitlore` (read-only):

- `tests/evals/lib/setup.sh` copies the plugin's `hooks/hooks.json` into the
  eval repo's `.claude/settings.json` with `${CLAUDE_PLUGIN_ROOT}` replaced by
  the gitlore source root. That is case B.
- `tests/evals/lib/claude-runner.sh` runs
  `(cd "$CWD" && claude -p ... --output-format json --setting-sources project --permission-mode bypassPermissions ...)`,
  the `claude` found on PATH, with `GITLORE_LAUNCHED=1` exported (so gitlore's
  own `.gitlore/bin/claude` shim passes through without `--plugin-dir .`).
- Nothing in the evals passes `--plugin-dir` or sets the variable.

So an eval meets the double run exactly when the `claude` it execs is the
dogfood shim and `<gitlore>/dist/plugin` exists: the shim then exports the
variable, the plugin loads from the copy, and its hooks run beside the ones in
the eval repo's settings (run 3 reproduces that).

Not established: whether that holds today. Gitlore's vendored toolkit is
`plugin-dev/VERSION` 0.7.1 with no `plugin-dev/bin/`, its `.envrc` has no
`PATH_add plugin-dev/bin`, and `dist/` does not exist there, so its evals do not
currently meet it. Whether the user runs `just evals` inside direnv after
adopting the shim cannot be read from the repo. The eval repo's `.claude/skills`
and `.claude/commands` copies of the plugin's skills would also sit beside the
loaded plugin's; that was not probed.

### Docs wording

`docs/references/dogfood.md:140-142` ("may run them twice, which is unprobed"):
true but unsupported as written. Proposed replacement for lines 140-142:

```text
Every `claude` through the shim loads the copy when there is one, so a script
that wires the plugin's hooks into its own settings, as gitlore's evals do,
runs them twice: Claude Code does not de-duplicate a hook registered by a
plugin and by a settings file, even with identical command strings, and
`--setting-sources project` does not stop the variable (probed on CC 2.1.294).
Such a script meets it only when the shim is on its PATH and the copy exists.
```

## 2. An empty plugin-root `.mcp.json`

### Procedure

`/tmp/claude/unprobed/p2/{none,empty,braces,malformed,valid}/plug`, each a
root-layout plugin with a bare `plugin.json`, and `.mcp.json` respectively
absent, zero bytes, `{}`, `{` and
`{"mcpServers":{"probesrv":{"command":"/bin/false"}}}` (positive control). Each
loaded with `CLAUDE_CODE_PLUGIN_DIRS=<its plug>`, cwd `<its>/proj`:

- `claude -p --model haiku --output-format stream-json --verbose "Reply with the single word ok."`
  for none, empty, braces, malformed; read the init event (`mcp_servers`,
  `plugins`, `plugin_errors`), the result and stderr.
- `claude plugin list` and `claude mcp list` for empty, braces, malformed,
  valid.
- `claude plugin validate <plug>` for none, empty, braces, malformed.
- One more `-p` run for empty with `--debug-file`.

### Evidence

All four `-p` runs: exit 0, `result: success is_error=false ok`, empty stderr,
`plugin_errors: null`, and an identical `mcp_servers` list (five `claude.ai`
connectors only) and the plugin listed in `plugins`. Nothing distinguishes empty
from none, from `{}`, or from the malformed `{` in the init event.

`claude plugin list` shows every one of them `Status: ✔ loaded`.
`claude mcp list` shows no plugin entry for none, empty, braces and malformed.
For the positive control it shows the file is read:

```text
plugin:p2valid:probesrv: /bin/false  - ✘ Failed to connect — CONNECTION_CLOSED
```

`claude plugin validate`:

```text
none      rc=0  Validation passed with warnings (author only)
braces    rc=0  Validation passed with warnings (author only)
empty     rc=1  ✘ json: Invalid JSON syntax: JSON Parse error: Unexpected EOF.
                The plugin loader logs this at debug level and loads no
                servers from the file.
malformed rc=1  ✘ json: Invalid JSON syntax: JSON Parse error: Expected '}'.
                (same sentence)
```

The `--debug-file` run for empty:

```text
[DEBUG] --plugin-dir /tmp/claude/unprobed/p2/empty/plug is one plugin: .mcp.json at its top marks it
[ERROR] Failed to load MCP servers from .../empty/plug/.mcp.json: SyntaxError: JSON Parse error: Unexpected EOF
```

The ERROR line appears three times in one run; the session went on, answered
`ok`, and exit 0.

### Conclusion (CC 2.1.294)

A zero-byte plugin-root `.mcp.json` is accepted silently at the user surfaces:
no stderr, no init `plugin_errors`, plugin `✔ loaded`, no failed-server entry in
`claude mcp list` or `/mcp`. It is parsed and fails: the loader logs a parse
error to the debug log only, and loads no servers from the file. For a plugin
that ships no `.mcp.json` nothing is lost. The one visible trace is
`claude plugin validate` on the copy, which fails with "Unexpected EOF". `{}` is
accepted and validates clean, as does no file. A malformed non-empty file
behaves like the empty one, so the empty file is not special-cased.

### Docs wording

`docs/references/dogfood-sync.md:166-169` ("how Claude Code treats an empty
plugin-root `.mcp.json` is unprobed") and `toolkit/README.md:285-286` ("how
Claude Code reads an empty `.mcp.json` is unverified"): unsupported; now
settled. Proposed replacements:

`docs/references/dogfood-sync.md`, replace from "(probed with a simulated mask"
to "is unprobed" (lines 166-169):

```text
(probed with a simulated mask on rsync 3.5.0, in the deliverable review's code
report). Claude Code accepts it silently, on CC 2.1.294: the plugin loads, no
server is listed and no error shows, and the loader logs a JSON parse error to
its debug log and loads no servers from the file; only `claude plugin validate`
on the copy fails, with "Unexpected EOF".
```

`toolkit/README.md`, replace the end of the paragraph, "and how Claude Code
reads an empty `.mcp.json` is unverified." (lines 285-286):

```text
Claude Code loads the plugin regardless, ignores the file and reports nothing
in the session, though `claude plugin validate` on the copy fails on it.
```

(The README sentence currently reads "...it stays until the next sync from your
shell deletes it, and how Claude Code reads...": keep the first clause, end it
with a full stop and add the new sentence.)

Items 3 (`/reload-plugins`) and 4 (jq 1.6 exit status) continue in
`unprobed-items-3-4.md`, split out for the 400-line cap.
