# Item 3.6 — CLAUDE.md names the dogfood launcher

Only `CLAUDE.md` changed (plus this report).

## Where each runbook clause landed

- **Quality gate names the four dogfood suites, `dogfood-launcher-test.sh` and
  `install-test.sh`**: `## Quality gate`, the enumeration of every test under
  `tests/`. `install-test.sh` (with "`install.sh`'s vendoring and settings
  wiring") sits after `update-plugin-dev-test.sh`, matching the `justfile`
  order. After `citation-test.sh` come "the four `dogfood.sh` suites"
  (`dogfood-sync-test.sh`, `dogfood-sync-refusal-test.sh`,
  `dogfood-pre-tool-test.sh`, `dogfood-session-start-test.sh`) and
  `dogfood-launcher-test.sh` ("the `bin/claude` shim"). The stranded `A` line
  that followed the list was joined into the next line; the rest of the
  paragraph is unchanged.
- **`docs/references/` node list gains `dogfood`**: the `docs/references/*.md`
  Layout bullet now lists `distribution`, `dogfood`, `release-flow`, `recovery`,
  `self-release`, `version-guard`. The bullet was rewrapped because the added
  name pushed a line to 78 columns.
- **Layout bullets for `toolkit/dogfood.sh` and `toolkit/bin/claude` brought to
  their neighbours' shape**:
  - `toolkit/dogfood.sh` now opens "the dogfood launcher's one script, with
    three subcommands" and says what each one is: `sync` (the mirror into
    `dist/plugin/`, minus git-ignored paths and every `.git`), `pre-tool` (the
    `PreToolUse(Write|Edit|NotebookEdit)` hook that refuses agent edits into the
    copy and names the source path) and `session-start` (the `SessionStart` hook
    that warns when the session does not load the copy or `jq` is missing). It
    closes on where the root comes from: the script's own location, never
    `CLAUDE_PROJECT_DIR` or a payload's `cwd` (D5). The shape follows
    `toolkit/version-guard.sh` and `toolkit/update.sh`: role first, then what it
    does.
  - `toolkit/bin/claude`: "the dogfood shim, a `claude` that the consumer's
    `.envrc` puts first on PATH as `PATH_add plugin-dev/bin`. Runs
    `dogfood.sh sync`, then execs the next `claude` on PATH with its arguments
    unchanged and `CLAUDE_CODE_PLUGIN_DIRS` set to the copy; a failed sync
    aborts the launch." (D9). Checked against `toolkit/bin/claude`.
- **`release.just` bullet names `dogfood`**: the recipe list now ends
  `update-plugin-dev`, `dogfood` (D10). Checked against `toolkit/release.just`.
- **`install.sh` bullet says it wires the dogfood hooks beside version-guard**:
  "adds the version-guard hook and, beside it, the two dogfood hooks
  (`dogfood.sh pre-tool` and `session-start`) to its `.claude/settings.json`".
  Checked against `install.sh` step 3, which pipes settings through `add_hook`
  three times.
- **Conventions bullet on `hook_cmd`'s single quotes**: now headed
  "`${CLAUDE_PROJECT_DIR}` in `install.sh`'s hook commands is intentionally
  single-quoted", and it names `hook_cmd` (version-guard), `pretool_cmd` and
  `session_cmd`. It says the `# shellcheck disable=SC2016` above each of the
  three is load-bearing. In `install.sh` each directive is on the line above its
  assignment, so the old wording "on that line" was imprecise and now reads
  "above each". It says the two dogfood commands double-quote
  `"${CLAUDE_PROJECT_DIR}"` inside the single quotes so a repo path with a space
  survives the hook shell. It also says `hook_cmd` leaves it bare, and why.

## Notes from the previous orchestrator

- **Both `install-test.sh` and `dogfood-launcher-test.sh` named, and the list
  covers every suite `just precommit` runs**: done. Checked mechanically. The
  sorted `bash tests/*.sh` lines of `justfile`'s `precommit` were diffed against
  the sorted `*-test.sh` names in CLAUDE.md's Quality gate section: identical,
  15 suites. The `tests/` listing was also diffed against those `justfile`
  lines: identical, so no suite goes unrun.
- **`toolkit/dogfood.sh` bullet covers all three subcommands**: done (above).
- **`hook_cmd` Conventions bullet covers `pretool_cmd` and `session_cmd`, with
  the reason for leaving version-guard's unquoted**: done (above). Both new
  commands carry SC2016 directives (`install.sh`, the two lines above their
  assignments) and quote `"${CLAUDE_PROJECT_DIR}"`.
- **doc-sync constraint on backtick `toolkit/` paths**: CLAUDE.md gained no new
  `toolkit/...` path, and there is no bare `toolkit/bin/`. The shim is referred
  to as `bin/claude`, which has no `toolkit/` prefix. `tests/doc-sync-test.sh`
  passes (see Checks).

## Sourced reason for version-guard's unquoted `hook_cmd`

The reason comes from two sources that agree:

- The outline, D11, "Quoting": "version-guard's string is left as is, since
  changing it would make a re-run add a duplicate."
- `docs/references/dogfood.md`, "`install.sh` wires the hooks, and only the
  hooks": "presence is matched on the command string, so changing it would make
  a re-run add a duplicate beside every existing consumer's entry."

The code confirms the mechanism. `install.sh`'s `add_hook` counts an entry as
present when `[.hooks[$event][]? | .hooks[]? | select(.command == $cmd)]` is
non-empty, which is an exact match on the command string.

## Final line count

`CLAUDE.md`: 233 lines (was 214), under the 400 cap.

## Checks run

- A width check: the only lines over 72 bytes that I changed hold em-dashes
  counted as 3 bytes, and every one is within the existing ~72-column hand wrap.
- The Quality gate list against the `justfile`, and `tests/` against the
  `justfile` (above).
- `just precommit` in the foreground: see "Precommit" below.

## Precommit

`just precommit` ran in the foreground and exited 0 on the first run, ending
`ok`. Its log includes
`release.just import: ok (plain + widened + missing gate, resume-release, dogfood)`
and `doc sync ok (5 shared command blocks, Layout matches toolkit/)`. No
intermittent failure occurred. `format-docs` reflowed this report in that run;
`CLAUDE.md` is outside its scope and was not touched by it.
