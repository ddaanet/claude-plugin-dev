# 2026-10-08 — Four dogfood claims left unprobed are probed, and one was wrong

Four claims in the dogfood docs and the `dogfood.sh` header carried "unprobed"
or "unverified". They were probed on 2026-10-08 on Claude Code 2.1.294 (Linux,
jq 1.7 installed, rsync 3.x). The probe report is
`plans/2026-10-08-dogfood-0.9.2/reports/unprobed-items.md`. This pass applies
its corrections to the prose and one source comment. No code changed, no
migration note is needed, and the version is not bumped: the comment in
`toolkit/dogfood.sh` ships with the next release.

## Hooks run twice under the shim

A plugin loaded through `CLAUDE_CODE_PLUGIN_DIRS` and the same hook in a
settings file both fire, even with byte-identical command strings, and
`--setting-sources project` does not stop the variable's plugin from loading.
`docs/references/dogfood.md` said "may run them twice, which is unprobed"; it
now states that they run twice and that such a script meets it only when the
shim is on its PATH and the copy exists.

Gitlore's evals reach the double run only after it adopts the shim. Its
`tests/evals/lib/setup.sh` copies the plugin's hooks into the eval repo's
settings, and nothing in the evals passes `--plugin-dir` or sets the variable.
Today its vendored toolkit has no `bin/` and its `.envrc` has no
`PATH_add plugin-dev/bin`, so its evals do not meet it. Whether its skill and
command copies in the eval repo also sit beside the loaded plugin was not
probed.

## An empty plugin-root `.mcp.json` is accepted silently

A zero-byte file loads the plugin, lists no server and shows no error in the
session. The loader logs a JSON parse error at error level, to the debug log,
and loads no servers from the file; a malformed non-empty file behaves the same,
and `{}` and no file validate clean. Only `claude plugin validate` on the copy
fails, with "Unexpected EOF". `docs/references/dogfood-sync.md` and
`toolkit/README.md` drop their "unprobed" and "unverified" for this.

## `/reload-plugins` makes commands, `.mcp.json` and output styles live

Held back without it, live after it: a changed or new command, the plugin's MCP
server set, and an output style's listing, new style file and the active style's
body from the next turn. The probe loaded the plugin through
`CLAUDE_CODE_PLUGIN_DIRS`, the dogfood path. Agent definitions and hook events
were not probed, and the "new session" wording for them stands. The README's two
"unverified" bullets become one, and the sync node's trade-off list and
`just dogfood` section name the three components.

## jq 1.6 exits 4 on a parse error, not 2

The docs and the `pre-tool` header comment said jq 1.6 exits 2 on a parse error.
Reading the 1.6 source (`src/main.c`, `src/util.c` of `jq-1.6.tar.gz`) gives 4;
jq 1.7 gives 5 (probed). The 1.6 figure was read and not run: the published
release has no checksum to check a downloaded binary against, so none was
executed. `docs/references/dogfood.md` states the 1.7 and 1.6 figures with that
provenance, and the `toolkit/dogfood.sh` comment drops the 1.6 clause and keeps
the usage and system-error exit 2. The design is unchanged: the guard exits 1 on
any nonzero `jq` status, which the probe confirmed with stub `jq`s exiting 2 and
4, so a blocking exit 2 cannot leak whichever status 1.6 returns.

`tests/dogfood-pre-tool-test.sh` still carries two comments saying 1.6 exits 2
on a parse error. They are comments, not assertions, and tests were out of scope
for this pass.

## Docs

`docs/design.md` states none of the four corrected claims and is unchanged.
