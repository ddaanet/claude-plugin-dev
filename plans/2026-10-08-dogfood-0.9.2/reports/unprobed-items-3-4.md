# Probe: four unprobed dogfood claims, items 3 and 4

Continues `unprobed-items.md` (items 1 and 2, and the shared setup and summary
at its top); same versions: CC 2.1.294, jq 1.7.

## 3. What `/reload-plugins` picks up

### Procedure

Scratch plugin `/tmp/claude/unprobed/p3/plug` (`p3`): `commands/hello.md`
(`description: cmd-desc-v1`, body `Reply with exactly: CMD-BODY-V1`),
`output-styles/s1.md` (`description: style-desc-v1`), `.mcp.json` with server
`srvone` (`/bin/false`). Non-interactive first:

```sh
CLAUDE_CODE_PLUGIN_DIRS=.../p3/plug cc.sh .../p3/proj -p --model haiku \
  --output-format stream-json --verbose '/reload-plugins'
```

It is honoured: the init lists `reload-plugins` and `reload-skills` among the
slash commands, and the reply is a synthetic assistant message
`Reloaded: 16 plugins · 64 skills · 21 agents · 56 hooks · 0 plugin LSP servers`
with zero tokens. That run cannot show an edit taking effect (one process, no
gap), so the real probe was interactive:

- `tmux -L probe3 new-session -d -s p3 -x 180 -y 50 ...` running
  `CLAUDE_CODE_PLUGIN_DIRS=.../p3/plug cc.sh .../p3/proj --model haiku`; accept
  the trust prompt (Up, Enter).
- `look.sh` types `/p3:` (command menu), `/mcp` and `/output-style`, and greps
  the pane.
- Look 1 (baseline); then edit the files: `hello.md` to
  `cmd-desc-v2`/`CMD-BODY-V2`, add `commands/newcmd.md`, `s1.md` to
  `style-desc-v2`, add `s2.md`, `.mcp.json` to server `srvtwo`; look 2 (control,
  no reload); `/reload-plugins`; look 3.
- Style body: set `s1`'s body to "Begin every reply with the exact token
  STYLE-A.", `/reload-plugins`, `/output-style p3:s1`, prompt; edit the body to
  STYLE-B, prompt (no reload); `/reload-plugins`, prompt.
- Command body: invoke `/p3:hello` after the reload.

### Evidence

```text
BEFORE edit:   /p3:hello (p3) cmd-desc-v1 | plugin:p3:srvone | p3:s1: style-desc-v1
AFTER edit, BEFORE reload (control):
               /p3:hello (p3) cmd-desc-v1 | plugin:p3:srvone | p3:s1: style-desc-v1
               (no /p3:newcmd, no p3:s2)
/reload-plugins:
  Reloaded: 16 plugins · 65 skills · 22 agents · 56 hooks · 1 plugin MCP server · 0 plugin LSP servers
AFTER reload:  /p3:hello (p3) cmd-desc-v2 | /p3:newcmd (p3) cmd-new
               plugin:p3:srvtwo (srvone gone)
               p3:s2: style-two-new | p3:s1: style-desc-v2
/p3:hello  ->  ● CMD-BODY-V2
```

Output style body, with the style selected:

```text
(after reload, STYLE-A body)     ● STYLE-A Hi.
(body edited to STYLE-B, no reload)   ● STYLE-A Hi again.
(after /reload-plugins)          ● STYLE-B Hi a third time.
```

### Conclusion (CC 2.1.294)

`/reload-plugins` makes all three live, and each was held back without it: (a) a
changed command's description and body, and a new command file; (b) the plugin
`.mcp.json` (the server set is replaced; the summary line gains "N plugin MCP
server"); (c) an output style's listing, a new style file, and the body of the
active style from the next turn. The plugin was loaded through
`CLAUDE_CODE_PLUGIN_DIRS`, the dogfood path. Agent definitions and hook events
were not probed here; the existing "new session" wording is untouched.

### Docs wording

`toolkit/README.md:261-265` is unsupported as written (the commands and
`.mcp.json`/output-style bullets say unverified), and
`docs/references/dogfood-sync.md:60` and `:138-139` are incomplete rather than
false. Proposed replacements:

`toolkit/README.md`, lines 261-265:

```text
- **Commands, `.mcp.json` and output styles** — after `/reload-plugins` in the
  session, like skill bodies: a changed or new command, the plugin's MCP
  servers and a style's body (from the next turn) all go live. A relaunch after
  `just dogfood` does too, since it re-reads everything Claude Code reads at
  start.
```

`docs/references/dogfood-sync.md:60`:

```text
- skill bodies, commands, `.mcp.json` and output styles need `/reload-plugins`
  whatever loads them;
```

`docs/references/dogfood-sync.md:138-139`:

```text
git-ignored copy. After it, a skill body, a command, `.mcp.json` or an output
style goes live on `/reload-plugins`, and an agent definition or hook event on a
relaunch through the shim.
```

(Line 138's tail "After it, a skill body goes live on `/reload-plugins`, and an"
and line 139 are one sentence; the replacement above spans the same two lines
and may rewrap by one.)

## 4. jq 1.6's exit status on a parse error

### Procedure

jq 1.7 (installed) probed directly. For 1.6:

- The release `jq-1.6` at `github.com/jqlang/jq` lists seven assets
  (`jq-1.6.tar.gz`, `.zip`, `jq-linux32`, `jq-linux64`, `jq-osx-amd64`,
  `jq-win32.exe`, `jq-win64.exe`), via
  `curl https://api.github.com/repos/jqlang/jq/releases/tags/jq-1.6`, none with
  a digest. `.../jq-1.6/sha256sum.txt` (also under the old `stedolan/jq` path)
  returns 404.
- `jq-linux64` was downloaded into `/tmp/claude/unprobed/jq16/` (alone in the
  directory). Its sha256 is
  `af986793a515d500ab2d35f8d2aecd656e764504b789b66d7e1a0b727a124c44`. No
  published checksum exists to compare it with, so by the rule set for this
  probe it was NOT executed.
- So the 1.6 behaviour was read, not run: `jq-1.6.tar.gz` (sha256
  `5de8c8e29aaa3fb9cc6b47bb27299f271354ebb72514e3accadc7d38b5bbaa72`, likewise
  unverified against a published file) was fetched into
  `/tmp/claude/unprobed/jq16src/` and `src/main.c` and `src/util.c` read; only
  those two files were extracted, and nothing was built or executed.
- The guard was exercised against real jq 1.7 and against PATH stubs named `jq`
  that read stdin, print a parse error and exit 2 or 4
  (`/tmp/claude/unprobed/fakejq/s2/jq`, `s4/jq`).

### Evidence

jq 1.7 exit statuses:

```text
printf '{' | jq .               parse error: Unfinished JSON term at EOF   rc=5
printf '' | jq .                (no output)                                rc=0
jq --nonsense . </dev/null      Unknown option --nonsense                  rc=2
jq '.a |' (compile error)       jq: 1 compile error                        rc=3
jq . /nonexistent/file          Could not open file                        rc=2
```

jq 1.6 source (`src/main.c` of the 1.6 tarball):

```text
 94   exit((ret < 0 && code == 0) ? 2 : code);   (usage; die() exits 2 at line 100)
598     ret = 3;                                  (program compile error)
636-641 // Parse error
        if (!(options & SEQ)) {
          ret = 4;
          fprintf(stderr, "parse error: %s\n", jv_string_value(msg));
          break;
        }
659     if (jq_util_input_errors(input_state) != 0) ret = 2;
```

`jq_util_input_errors` is `state->failures`, which `util.c` increments only for
a file that cannot be opened (line 301) or a stream read error (lines 316-320),
never for a parse error. The return path (lines 660-667) passes a `ret` below 10
through. So, on the source, a parse error exits 4 in 1.6. The empty-stdin and
truncated-document cases follow the same loop (a truncated document is a parse
error at EOF; an empty stdin yields no value, so `ret` stays 0). No usage case
exists with a program given; with none and a terminal the usage exits 2.

`toolkit/dogfood.sh pre-tool`, whole script, exit status:

```text
real jq 1.7, payload '{'                  exit=1  stdout 0B  stderr: jq: parse error ...
real jq 1.7, payload ''                   exit=0  stdout 0B
real jq 1.7, valid non-copy payload       exit=0  stdout 0B
stub jq exiting 2 on '{'                  exit=1  stdout 0B
stub jq exiting 4 on '{'                  exit=1  stdout 0B
```

### Conclusion

Not probed on 1.6, because no published checksum exists, so the binary was not
run. The documented claim "exit 2 on a parse error in 1.6" is contradicted by
the 1.6 source, which sets 4; it is also not what 1.7 does (5). The claim's
consequence does not depend on the number: the guard assigns
`path="$(jq ... && printf x)" || exit 1` (`toolkit/dogfood.sh:131`) and the deny
build ends `|| exit 1` (`:154`), so any nonzero jq status, 2 included, becomes
exit 1, a non-blocking hook error. The stub run with jq exiting 2 shows that
directly. `pre-tool` cannot leak a blocking exit 2 from jq 1.6 meeting a
malformed payload, whatever 1.6 returns. The empty-payload case exits 0 (the
path is empty, so it is not under the copy).

If a probe of the binary is wanted, the call is the user's: the downloaded
`jq-linux64` hash matches the value jq's download page listed for 1.6, but only
from memory and not from a file fetched here, so it was treated as unverified.

### Docs wording

`docs/references/dogfood.md:82-85` and `toolkit/dogfood.sh:119-121`: the
parenthetical "and on a parse error in 1.6 (read from its source, not probed)"
is false on the source. Proposed replacements:

`docs/references/dogfood.md`, lines 82-85 (from "Any `jq` failure"):

```text
cannot be entered, stops the script with exit 1, which Claude Code shows as a
non-blocking hook error. Any `jq` failure exits 1 with `jq`'s stderr kept, never
with `jq`'s own status: `jq` exits 2 on a usage or system error (1.7 probed),
and exit 2 from a `PreToolUse` hook blocks the tool call. A parse error exits 5
in 1.7 (probed) and 4 in 1.6 (read from its source, not run), so the choice of
exit 1 holds whichever version meets the payload.
```

(The first two lines of that block are lines 80-82 of the current text and are
shown only as the anchor; the edit is to the sentence from "Any `jq` failure"
through "blocks the tool call".)

`toolkit/dogfood.sh`, lines 119-121 (comment, ships to consumers; a change means
a release):

```text
# the deny, exits 1 with jq's stderr kept, never with jq's own status: jq exits
# 2 on a usage or system error, and exit 2 from a PreToolUse hook blocks the
# tool call. With no jq on PATH the guard stands down
```

(Line 122-123 then continue unchanged: "in silence rather than fail every edit
of the session; the session-start warning is where a missing jq is reported.")
