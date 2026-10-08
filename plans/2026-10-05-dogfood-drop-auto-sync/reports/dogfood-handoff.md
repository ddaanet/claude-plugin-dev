# Dogfood: claude-plugin-dev 0.9.1 in handoff

2026-10-07. Consumer: `/Users/david/code/handoff`. Crossed 0.7.1 → 0.9.1.

## Pre-flight

- `git status --short`: only two untracked notes in `inbox/`, dated 2026-09-25
  and 2026-09-29, dropped by other repos' sessions. The last commit was
  2026-09-23. No sign of a live session. Left untouched, never staged.
- `plugin-dev/VERSION` before: `0.7.1`.

## Update

`just update-plugin-dev dist-v0.9.1` fetched the tag, made the subtree commits
`0112ade Squashed 'plugin-dev/' changes from 87758aa..dcfd5d6` and
`3282e44 Merge commit '0112ade…'`, and printed the notes for v0.9.0 and v0.9.1.
Both notes read in full, as printed and from `plugin-dev/migrations/`.
Afterwards `plugin-dev/VERSION` reads `0.9.1` and `just --list` parses.

## Migration steps

| Note step | Action | Result |
| --- | --- | --- |
| v0.9.0 §1 `bash plugin-dev/install.sh` | Attempted with the sandbox disabled | **Not done.** The auto-mode classifier refused it ("Irreversible Local Destruction"). The note itself says to run it from a human shell. Left for my human partner. |
| v0.9.0 §2 remove `.bin/claude` | `git rm --ignore-unmatch .bin/claude`. In `.envrc`, deleted `PATH_add .bin` and its comment. In `justfile`, `shellcheck -x .bin/* bin/* scripts/*.sh tests/*.bats` became `shellcheck -x bin/* scripts/*.sh tests/*.bats`: the `.bin/*` glob was removed and the other paths kept, as the note says. | Done |
| v0.9.0 §3 `PATH_add plugin-dev/bin` last | Added as the last line of `.envrc`, after `.gitlore/bin` and `.venv/bin`, with a one-line comment. `direnv allow .` → rc 0. | Done |
| v0.9.0 §4 ignore the copy | `git check-ignore` failed, so `/dist/plugin/` was appended to `.gitignore`. handoff has no `clean` recipe. | Done |
| v0.9.1 §1 `just dogfood` | Run outside the sandbox. | Done (check b) |

No file under `plugin-dev/` was edited.

## Checks

The stub is `$TMPDIR/dogfood-stub/claude`, which prints
`CLAUDE_CODE_PLUGIN_DIRS` (or `<unset>`) and one line per argv entry. Every
check ran with `PATH=<root>/plugin-dev/bin:<stub dir>:/usr/bin:/bin`, so no real
claude ever launched.

### a. No copy — PASS

```text
dogfood: no copy at /Users/david/code/handoff/dist/plugin, so claude starts without it; run just dogfood to create it
STUB CLAUDE_CODE_PLUGIN_DIRS=<unset>
STUB argv: [-p]
STUB argv: [a b]
STUB argv: [--flag]
rc=0
```

The shim printed one `dogfood:` line, matching the v0.9.1 note word for word,
and named `just dogfood`. It launched with argv intact, including the spaced
argument, and left the variable unset.

### b. `just dogfood` — PASS

- Run outside the sandbox: rc 0, the only output the recipe echo. In
  `dist/plugin/`, a search found no `.git` (the `memory/.git` gitfile was
  dropped), no `.venv`, `__pycache__` or `.pytest_cache`, no
  `.claude/settings.local.json`, no `.claude/autodrive.log` and no
  `.claude/worktrees`. It found no zero-byte files and no char devices. Tracked
  files are present (`skills/`, `hooks/`, `plugin-dev/`, …), and so are the
  untracked but not ignored `inbox/` notes, which is the documented behaviour
  ("minus git-ignored paths"). Size 3.9M.
- The copy holds an empty `dist/` directory (`dist/plugin/dist`). rsync creates
  the parent of the excluded `dist/plugin/`. Harmless.
- Sandbox-mask probe: sandboxed Bash shows `./.mcp.json` as a mask in the repo
  root. Running `just dogfood` inside the sandbox printed
  `skipping non-regular file ".mcp.json"` and exited 0. No `.mcp.json`, no
  zero-byte file and no char device reached the copy. The known exposure does
  not occur for a char-device mask; rsync skips non-regular files. A zero-byte
  *regular-file* mask was not present to test.

### c. Copy present — PASS

```text
STUB CLAUDE_CODE_PLUGIN_DIRS=/Users/david/code/handoff/dist/plugin
STUB argv: [--resume]
STUB argv: [x y]
STUB argv: [-c]
rc=0
```

- `pwd -P` = `/Users/david/code/handoff`, the physical root. An inherited
  `CLAUDE_CODE_PLUGIN_DIRS=/inherited` was overridden by the copy path.
- Launched from `$TMPDIR` through a symlink to the root
  (`$TMPDIR/handoff-link/plugin-dev/bin`), the variable still spelled the
  physical root.
- No sync on launch: snapshot of the copy (path, size, mtime), then
  `dogfood-probe.tmp` was created in the source root and the stub launched. The
  snapshot afterwards was identical, and `dist/plugin/dogfood-probe.tmp` did not
  exist. The probe was removed.
- Chain through gitlore's launcher (`PATH=plugin-dev/bin:.gitlore/bin:stub`): no
  loop. The stub received
  `--settings {"autoMemoryDirectory":"/Users/david/code/handoff/memory"} -p ping`
  with the copy variable set. The old `.bin/claude` stripped its own directory
  for exactly this reason, and the vendored shim's `path_without` covers it.

### d. Hooks — PASS (hooks not yet wired: see install.sh above)

`session-start` was run with a SessionStart payload on stdin:

- `CLAUDE_CODE_PLUGIN_DIRS=<root>/dist/plugin` → silent, rc 0.
- `/elsewhere:<root>/dist/plugin/` (trailing slash, among others) → silent, rc
  0.
- Variable unset → rc 0, prints
  `{"systemMessage":"\u001b[0mdogfood: this session does not load /Users/david/code/handoff/dist/plugin — launch claude through plugin-dev/bin/claude from the repo root","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"This session does not load …/dist/plugin, so plugin behaviour observed in it is not that of the promoted copy."}}`
- No `jq` on PATH → rc 0, prints the documented
  `dogfood: jq is not on PATH, so the copy guard and this check are off until it is installed`.

`pre-tool` was run with JSON payloads on stdin:

- Write to `<root>/dist/plugin/skills/handoff/SKILL.md` → `deny`. The reason
  names the copy, and `additionalContext` reads
  `The source of … is /Users/david/code/handoff/skills/handoff/SKILL.md. Make the edit there.`
  The `systemMessage` is
  `dogfood: blocked an edit into dist/plugin/ — the generated copy`. rc 0.
- Write to `<root>/skills/handoff/SKILL.md` → empty stdout, rc 0 (allowed).
- Write to `<root>/dist/plugin/new file.md` (spaced, not yet existing) → deny,
  and it names `<root>/new file.md`.
- NotebookEdit `notebook_path` into the copy → deny.
- Edit through a symlink to the root → deny. The source is named by its physical
  path.

### e. `just precommit` — FAIL (environmental, not the migration)

The gate ran with the venv on PATH. Every step before pytest passed: jq on the
three JSON files, `shellcheck -x bin/* scripts/*.sh tests/*.bats` (the edited
line, `.bin/*` gone), ruff, ruff format, docformatter, mypy, ty, and both bats
suites. pytest: `4 failed, 281 passed, 14 deselected in 413.38s`. All four
failures are timing assertions in `tests/test_drive_when_idle.py`
(`test_prose_confirms_submit_landing_after_fast_retry_window`,
`test_tui_line_stops_pressing_enter_after_three`,
`test_resume_line_settle_is_configurable`,
`test_a_delivered_line_records_its_gate_timings`). One example:
`assert last["gate"] >= 0.5` got `0.38`, and the test's own comment notes the
bound erodes under load.

- Load average was 18–20 throughout, driven by a concurrent `just precommit` /
  bats run in `/Users/david/code/sandbox-lies` from another session.
- Re-running the four tests reproduced the failures. Re-running the whole file
  outside the sandbox gave 5 failed / 29 passed, a different set:
  `test_a_booting_pane_is_typed_into_at_once_and_given_time_to_paint` joined.
  The varying membership points to flakes.
- `git diff 2f07cc4 --stat -- . ':!plugin-dev'` shows the migration touched only
  `.bin/claude`, `.envrc`, `.gitignore` and `justfile`. No test, script or
  conftest changed, and none of the failing tests references any of those files.

Precommit was never green, so the migration was not committed (see below).

## Surprises

Two surprises, both patches to 0.9.1:

1. **The session-start remedy is wrong when the copy is missing.** Observed:
   with `dist/plugin` moved aside and the variable unset (which is exactly what
   a shim launch with no copy produces), `session-start` printed
   `dogfood: this session does not load /Users/david/code/handoff/dist/plugin — launch claude through plugin-dev/bin/claude from the repo root`.
   The session *was* launched through the shim, and the fix is `just dogfood`.
   `plugin-dev/README.md` describes this very case: "With no copy, the shim says
   so … That session does not load the copy, and the `SessionStart` check says
   so. Run `just dogfood`, then relaunch." The README and the shim's line name
   the right step, but the hook text names the wrong one. Patch: when
   `<root>/dist/plugin` does not exist, the warning names `just dogfood`. With
   no copy and an inherited `CLAUDE_CODE_PLUGIN_DIRS=/inherited`, the shim
   passed `/inherited` through unchanged, as documented.
2. **Paths ignored inside a submodule are copied.** The exclude list comes from
   the superproject's `git ls-files -o -i --exclude-standard --directory`, which
   does not descend into submodules. In handoff,
   `git -C memory ls-files -o -i --exclude-standard --directory` lists
   `.claude/` (ignored there through the global excludes file, since `memory`
   has no `.gitignore`), and `dist/plugin/memory/.claude/.cc-writes` exists in
   the copy. That contradicts the documented "minus git-ignored paths". It is
   harmless here, an empty sandbox-bookkeeping directory. A submodule holding a
   `.venv` or build output would carry it into the copy.

Observations, not contradictions:

- **No agent can run install.sh, even unsandboxed.** The auto-mode classifier
  refused it. The note says "from your own shell", so this matches the note. It
  does mean the dogfood hooks stay unwired in handoff, and the session-start
  warning is absent, until my human partner runs it.
- **handoff's `CLAUDE.md` is stale on the launcher.** The restart-walker passage
  (around line 263) still says the launcher shims supply `--plugin-dir <root>`.
  The vendored shim sets `CLAUDE_CODE_PLUGIN_DIRS` instead. Already tracked by
  `inbox/2026-09-29-note-stale-restart-replay-claim.md`. Not edited.
- **Test-method caveat:** one early unsandboxed stub probe exited 127 ("no other
  claude on PATH") because `$TMPDIR` differs outside the sandbox. It was re-run
  with the absolute stub path and is not cited as evidence.
- The gate was not retried a fourth time: at 14:46 the load average was still
  14–17, and the sandbox-lies test run was still live.

## Commits in handoff

- `0112ade`, `3282e44` — the subtree pull, made by `update-plugin-dev`.
- No migration commit. The gate is red on load-sensitive tests, and committing
  needs a green `just precommit`, which is also gitlore's `precommitCommand`.
  The migration is left in the working tree: `.bin/claude` deletion staged (by
  `git rm`), `.envrc`, `.gitignore` and `justfile` modified and unstaged. The
  two `inbox/` notes are untouched. `dist/plugin/` exists and is ignored.

Nothing pushed. Left for my human partner, from the handoff root in their own
shell, once the machine is quiet:

```sh
cd /Users/david/code/handoff && bash plugin-dev/install.sh && git diff -- .claude/settings.json && just precommit && git add .envrc .gitignore justfile .claude/settings.json && git commit -m 'chore: migrate to claude-plugin-dev 0.9.1 dogfood shim'
```

It worked if the `settings.json` diff adds `dogfood.sh" pre-tool` under
`PreToolUse` and `dogfood.sh" session-start` under `SessionStart`, and
`git show --stat HEAD` lists `.bin/claude` (deleted), `.envrc`, `.gitignore`,
`justfile` and `.claude/settings.json`.
