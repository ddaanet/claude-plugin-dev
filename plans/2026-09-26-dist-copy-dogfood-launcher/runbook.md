# Runbook — dogfood launcher loads the plugin from a synced copy

Design: `outline.md` beside this file (no `design.md`). Requirements input:
`plans/2026-09-26-brief-dist-copy-dogfood-launcher.md`, which carries no IDs;
the outline's twelve Key decisions stand in for them as `D1`–`D12`. Probe
evidence: `reports/probe-hooks.md`, `reports/probe-subdir-hooks.md`,
`reports/research-probes.md`. Recall: `recall-artifact.md`.

**Field lines are nested bullets**, so `just format-docs` cannot reflow them
into prose (`reflow-joins-field-lines`).

## Two gates shape the item boundaries

**A new `toolkit/` file fails `just precommit` until two lists name it.**
`tests/dist-tree-test.sh` pins `toolkit/`'s contents exactly, and
`tests/doc-sync-test.sh` requires the backtick-quoted `toolkit/` paths in
`CLAUDE.md` to be exactly the shipped files — so no bare `toolkit/bin/` either.
So the slice that first commits `toolkit/dogfood.sh` (1.1/1) and the one that
first commits `toolkit/bin/claude` (2.1/1) each carry, in their GREEN commit:
the path in `dist-tree-test.sh`'s `expected` list, a `CLAUDE.md` Layout bullet
for it, and the `justfile` `precommit` wiring — `shellcheck` on the script,
`bash -n` on its new suite, and a `bash tests/<suite>` line. That splits
`CLAUDE.md` across three items against the prose-atomicity rule; the gate forces
it, and Item 3.6 owns every other `CLAUDE.md` edit.

**Genuine red where the order cannot supply one.** Each slice's tests must fail
on an assertion against the previous slice's GREEN. A slice whose tests already
pass there proves discrimination by one mutation of the code under test instead,
reported with the failing assertion's output and the green line after the revert
(`craft:test-discipline`).

## Fixtures shared by the suites

- **The consumer fixture** is a git repo whose own path contains a space
  (`$sandbox/my consumer`): a root `.claude-plugin/plugin.json`, a `.gitignore`
  holding `/dist/plugin/`, a tracked `skills/demo/SKILL.md`, and
  `plugin-dev/dogfood.sh` (plus `plugin-dev/bin/claude` in the launcher suite)
  copied from `toolkit/` and committed, the way a subtree vendors them. Each
  test appends the ignore patterns it needs. `<root>` in an assertion is the
  fixture's `pwd -P` spelling: macOS `$TMPDIR` sits under a symlink.
- **A watchdog, not `timeout`,** bounds any run that could loop: run it in the
  background, kill it after 10 s, fail on the kill. macOS ships no `timeout`,
  and a macOS consumer running these suites is the check outline Risks names.
- **A jq-less PATH** is one directory of symlinks to the commands the script
  invokes, jq excluded. Each test using it first asserts `command -v jq` fails
  under it, so the negative cannot pass for a PATH that still reaches jq.
- **The stub `claude`** records its argv NUL-separated, its `$PWD`, `PATH`,
  `CDPATH` (or an unset marker) and `CLAUDE_CODE_PLUGIN_DIRS` to a file under
  `$sandbox`, then exits 0.

## Requirements mapping

| Requirement | Phase | Items | Notes |
|---|---|---|---|
| D1 a real copy | 1 | 1.1 | Slice 1 asserts a regular file, not a link |
| D2 source set | 1 | 1.1 | Slices 1–5 |
| D3 plugin root = repo root | 1 | 1.1 | Slice 6 refusal |
| D4 sync on promotion only | 2, 3 | 2.1, 3.1, 3.3 | No `PostToolUse` anywhere |
| D5 one script, root from its own location | 1, 3 | 1.1–1.3, 3.6 | |
| D6 copy guard | 1, 2 | 1.2, 2.2 | 2.2 wires its matcher |
| D7 `session-start` report | 1, 2, 3 | 1.3, 2.2, 3.3 | 2.2 wires it |
| D8 loud sync failure | 1, 2, 3 | 1.1, 2.1, 3.1 | 1.1/7, 2.1/5; 3.1 inherits |
| D9 the shim | 2, 3 | 2.1, 3.2, 3.3, 3.4, 3.6 | `.envrc` step, docs |
| D10 `just dogfood` | 3 | 3.1, 3.3, 3.4, 3.6 | |
| D11 `install.sh` wiring | 2, 3 | 2.2, 3.3 | 3.3 documents the unedited files |
| D12 migration note | 3 | 3.2 | |

Item 3.5 carries D1–D12 as documentation, the node holding every decision's
argument, so it is on no row.

**Out of scope, per `outline.md` Scope/OUT:** nested roots and edify, editing
consumer repos, gitlore's `GITLORE_AUTO_CLAUDE_PLUGIN_DIR`, cutting the release.
**Not in this runbook:** the macOS `sync` run (outline Risks) — it needs a macOS
consumer and stays on the task file's Remaining list.

## Phase 1: `toolkit/dogfood.sh` (type: tdd)

`tests/dogfood-test.sh` passed 400 lines, so the Phase 1 boundary split it by
subcommand: `dogfood-sync-test.sh` and `dogfood-sync-refusal-test.sh` (1.1/5–7)
for Item 1.1, `dogfood-pre-tool-test.sh`, `dogfood-session-start-test.sh`.

- **Item 1.1:** `toolkit/dogfood.sh` `sync`, in the two sync suites.
  - Requirements: D1, D2, D3, D5, D8
  - Slices:
    1. External contract. `sync copies a tracked file`: the copy's
       `skills/demo/SKILL.md` is a regular file (`-f` and not `-L`) with the
       source's bytes (`cmp`). `sync leaves out an ignored file and .git`: an
       ignored `build.log` and `.git` are absent from the copy.
       `sync resolves the root from its own location`: run with the cwd at
       `$sandbox` and `CLAUDE_PROJECT_DIR` naming another directory, the copy
       lands in the fixture's `dist/plugin/`. `unknown subcommand is usage`:
       `dogfood.sh bogus` and no argument each exit 2 with stderr naming `sync`,
       `pre-tool` and `session-start`. GREEN also carries the gate bookkeeping
       above.
    2. Deletions. `a committed deletion propagates`: sync, `git rm` and commit a
       skill file, sync again — it is gone from the copy.
       `a tracked file deleted in the worktree does not fail sync`: delete a
       tracked file without committing; sync exits 0 and the copy lacks it. Both
       are red against the naive `git ls-files | rsync --files-from` sync; if
       1.1/1's GREEN already passes them, the mutation is swapping in that sync.
       `a file that becomes ignored leaves the copy`: pins `--delete-excluded`
       (added at test review).
    3. Whitespace. `names with spaces survive`: a tracked `skills/a b/SKILL.md`
       is copied, and an ignored `out dir/x` is absent.
    4. Nested repos and the copy itself. `a nested repo's .git stays out`:
       `memory/` is its own repo with `fact.md` committed inside it, recorded in
       the fixture as a gitlink the way the consumers' memory submodule is — the
       copy has `memory/fact.md` and no `memory/.git`.
       `sync never recurses into the copy`: after two consecutive syncs the copy
       holds no `dist/plugin` path. Residual, stated in the test's comment: with
       `/dist/plugin/` git-ignored — which slice 6 makes a precondition — the
       ignore list excludes the copy as well, so dropping the hard
       `/dist/plugin/` exclude survives this test.
    5. Pattern characters.
       `an ignored entry holding a pattern character aborts`: one fixture per
       name `a*b.log`, `a?b.log`, `a[b.log`, `a]b.log`, `a\b.log` (ignored by
       `*.log`); each exits 1, stderr contains the name, a sentinel file
       pre-placed in `dist/plugin/` survives, and a newly committed file is not
       copied — rsync never ran.
    6. Refusals. `refuses without a root manifest`: no
       `.claude-plugin/plugin.json` — exit 1, stderr contains
       `.claude-plugin/plugin.json`, no `dist/plugin/` created.
       `refuses when dist/plugin is not ignored`: `.gitignore` emptied — exit 1,
       stderr contains `/dist/plugin/`, no `dist/plugin/` created.
       `a git failure stops sync before rsync`: a stub `git` fails `ls-files` —
       exit non-zero, no `dist/` created (from 1.1/1's code review).
    7. rsync failure. `an rsync failure keeps its status and stderr`: a stub
       `rsync` first on PATH writes `rsync: stub failure` to stderr and exits
       23; `sync` exits 23 and its stderr contains that line exactly once.
  - Interfaces:
    - `<root>` = the physical (`pwd -P`, `CDPATH` unset) parent of the script's
      own directory; never `CLAUDE_PROJECT_DIR` or a payload `cwd`
    - `bash <root>/plugin-dev/dogfood.sh sync` → exit 0, no stdout;
      `<root>/dist/plugin/` mirrors the source set of D2
    - refusal → exit 1, one `dogfood: …` line on stderr naming the offending
      path, `dist/plugin/` untouched
    - the ignore check asks git about `dist/plugin/` with the trailing slash: a
      first sync has no directory yet, and `git check-ignore dist/plugin` then
      misses a `/dist/plugin/` pattern (git 2.47, probed at review)
    - git failure → git's status and stderr; no rsync, `dist/` untouched
    - rsync failure → rsync's own exit status, rsync's stderr unredirected
    - any other subcommand, or none → exit 2, usage on stderr

- **Item 1.2:** `toolkit/dogfood.sh` `pre-tool`, in the pre-tool suite.
  - Requirements: D5, D6
  - Depends on: Item 1.1
  - Slices:
    1. External contract. `pre-tool denies an Edit into the copy`: payload
       `{"tool_name":"Edit","tool_input":{"file_path":"<root>/dist/plugin/skills/demo/SKILL.md"}}`
       — stdout parses with jq; `.hookSpecificOutput.hookEventName` is
       `PreToolUse`, `.hookSpecificOutput.permissionDecision` is `deny`,
       `.hookSpecificOutput.permissionDecisionReason` contains the denied path,
       `.hookSpecificOutput.additionalContext` contains
       `<root>/skills/demo/SKILL.md`, and `.systemMessage` contains
       `dist/plugin` and no newline; exit 0. `pre-tool allows a source edit`:
       `<root>/skills/demo/SKILL.md` — exit 0, stdout and stderr empty.
    2. `pre-tool denies a NotebookEdit into the copy`: the same path under
       `.tool_input.notebook_path`, no `file_path` — the same deny, mapped path
       included.
    3. Paths outside the copy. `pre-tool allows a path outside the repo` (a file
       under `$sandbox`), `… a sibling of the copy` (`<root>/dist/other`), and
       `… a prefix-sharing sibling` (`<root>/dist/plugin-old/x`): each allowed.
    4. Physical spelling, `new/` absent: deny, source `<root>/new/file.md`.
       `pre-tool denies a copy path through a symlinked repo`;
       `… through a symlink to the copy` (test review).
       `pre-tool follows .. past a directory not yet created`, into the copy and
       out of it, and `pre-tool keeps a trailing newline and a bare - in a name`
       (code review).
       `pre-tool invoked through the symlink denies a physical path`.
    5. `pre-tool is silent without jq`: the jq-less PATH, a copy-path payload —
       exit 0, stdout and stderr empty. Its guard is not a stderr discard:
       `pre-tool fails loudly on a payload jq cannot read` (test review).
    6. Leaf symlink, added: followed into the copy, chains too; one out allowed.
  - Interfaces:
    - `bash <root>/plugin-dev/dogfood.sh pre-tool` < PreToolUse payload → exit 0
      per verdict; non-zero on an unreadable payload or an unenterable directory
    - edited path = `.tool_input.file_path // .tool_input.notebook_path`,
      resolved as `pwd -P` on existing dirs, `readlink -f` on a leaf link
    - under `<root>/dist/plugin/` → stdout is one object:
      `.hookSpecificOutput.hookEventName = "PreToolUse"`,
      `.hookSpecificOutput.permissionDecision = "deny"`,
      `.hookSpecificOutput.permissionDecisionReason` (the verdict, worded to
      read after CC's `PreToolUse:<Tool> hook error:` prefix),
      `.hookSpecificOutput.additionalContext` (the source path `<root>/<rel>`),
      `.systemMessage` (one line)
    - otherwise, or with no jq on PATH → empty stdout

- **Item 1.3:** `toolkit/dogfood.sh` `session-start`, in its own suite.
  - Requirements: D5, D7
  - Depends on: Item 1.1
  - Slices:
    1. External contract, with `dist/plugin/` present in the fixture.
       `session-start is silent on the copy`: `CLAUDE_CODE_PLUGIN_DIRS` =
       `<root>/dist/plugin` — exit 0, stdout empty.
       `session-start warns when the variable is unset`: stdout parses;
       `.systemMessage` starts with `\u001b[0m` and contains
       `<root>/dist/plugin`; `.hookSpecificOutput.hookEventName` is
       `SessionStart`; `.hookSpecificOutput.additionalContext` contains
       `<root>/dist/plugin`.
    2. Entry matching. Silent for `/x/other:<root>/dist/plugin:/y/other`,
       `<root>/dist/plugin/`, `$sandbox/link/dist/plugin`, and past a sealed
       directory; warns on a relative entry and on one resolving to `plugin<LF>`
       (code review).
    3. Mismatches warn on both channels: `<other>/dist/plugin` (another repo's
       real copy), `/x<root>/dist/plugin` (a longer, non-existent entry), and
       `<root>/dist/plugin/skills` (a longer real entry). An unresolved entry is
       compared literally, trailing slash stripped.
    4. `session-start reports a missing jq on systemMessage only`: the jq-less
       PATH, variable unset — stdout parses (with the suite's own jq);
       `.systemMessage` starts with `\u001b[0m` and contains `jq`;
       `.hookSpecificOutput` is absent.
  - Interfaces:
    - `bash <root>/plugin-dev/dogfood.sh session-start` → exit 0 always, stdin
      not read
    - some `:`-separated entry of `CLAUDE_CODE_PLUGIN_DIRS` equals
      `<root>/dist/plugin` after `pwd -P` → empty stdout
    - otherwise → one object: `.systemMessage` (leads with ESC `[0m`, names
      `<root>/dist/plugin`) and `.hookSpecificOutput` with
      `hookEventName = "SessionStart"` and `additionalContext` stating as fact
      that this session does not load `<root>/dist/plugin`
    - no jq on PATH → one static object, `.systemMessage` only; the copy check
      is skipped

## Phase 2: the shim and the hook wiring (type: tdd)

- **Item 2.1:** `toolkit/bin/claude` (bash, mode 100755), new suite
  `tests/dogfood-launcher-test.sh`.
  - Requirements: D4, D8, D9
  - Depends on: Item 1.1
  - Slices:
    1. External contract. PATH = `<root>/plugin-dev/bin:<stubdir>:$PATH`.
       `the shim execs the next claude with argv intact`: run with
       `--foo 'a b'`; the stub's argv is exactly `--foo`, `a b`.
       `the shim syncs before exec`: `dist/plugin/.claude-plugin/plugin.json`
       exists. `the shim exports the copy`: the stub recorded
       `<root>/dist/plugin`. `the shim unsets CDPATH`: set to `/tmp` going in,
       the stub recorded it unset. GREEN also carries the gate bookkeeping
       above, plus a `dist-tree-test.sh` assertion that `toolkit/bin/claude`'s
       index mode is `100755` — a non-executable shim is skipped by PATH lookup
       without a word.
    2. `an inherited variable is overwritten`: with
       `CLAUDE_CODE_PLUGIN_DIRS=/elsewhere/dist/plugin` exported, the stub
       recorded exactly `<root>/dist/plugin`.
    3. Stripping by identity. `the shim strips its own entry in any spelling`:
       PATH = `<root>/plugin-dev/bin/:<root>/plugin-dev/bin:<stubdir>:$PATH`,
       run under the watchdog — the stub ran, and no entry of its recorded PATH
       holds a `claude` that is `-ef` the shim. `… keeps another bin/claude`: a
       `$sandbox/other/bin/claude` stub ahead of `<stubdir>` is the one that
       ran. `… keeps the rest of PATH as spelled`: a leading empty entry
       survives (2.1/1 code review).
    4. `a subdirectory launch resolves the root`: cwd `<root>/skills/demo` — the
       stub ran, recorded `<root>/dist/plugin`, and recorded
       `<root>/skills/demo` as its `$PWD`.
    5. `a failed sync aborts the launch`: manifest removed — the shim exits 1,
       stderr contains `.claude-plugin/plugin.json`, and the stub's record file
       does not exist.
    6. `no next claude exits 127`: PATH = the shim dir plus a tools directory of
       symlinks holding no `claude` (asserted first with `command -v`) — exit
       127, stderr contains `no other claude on PATH`.
  - Interfaces:
    - `<root>/plugin-dev/bin/claude [arg…]`, `<root>` = physical
      `<shim dir>/../..`
    - runs `bash <root>/plugin-dev/dogfood.sh sync`; non-zero → that status, no
      exec
    - then exports `CLAUDE_CODE_PLUGIN_DIRS=<root>/dist/plugin`, unsets
      `CDPATH`, drops every PATH entry whose `claude` is `-ef` itself, and execs
      the next `claude` with argv unchanged
    - no next `claude` → exit 127, `dogfood: no other claude on PATH` on stderr

- **Item 2.2:** `toolkit/install.sh` step 3, in
  `tests/update-plugin-dev-test.sh` scenario
  `install.sh: wires into an existing settings.json without replacing it`, whose
  fixture already holds a matcher-less `PreToolUse` entry. Step 3's jq block
  becomes one function of (event, matcher, command), called three times, the
  no-settings branch included (seeded with `{}`); `hook_cmd` for version-guard
  keeps its unquoted spelling, since changing it would make a re-run add a
  duplicate. The header's step 3 and the `changed` line name all three hooks.
  Out of scope: moving install.sh's scenarios into their own suite, though this
  one passes 400 lines (outline item 4).
  - Requirements: D6, D7, D11
  - Depends on: Item 1.2, Item 1.3
  - Slices:
    1. External contract. `install adds the pre-tool hook once`: exactly one
       `PreToolUse` entry carries the pre-tool command, its matcher
       `Write|Edit|NotebookEdit`. `install adds the session-start hook once`:
       exactly one `SessionStart` entry carries the session-start command and
       has no `matcher` key. `the commands quote the project dir`: each contains
       the literal `"${CLAUDE_PROJECT_DIR}"`, unexpanded.
    2. `a re-run is a no-op`: a second install leaves `settings.json`
       byte-identical (`cmp`) and prints `already installed, nothing to do`.
    3. `a pre-existing SessionStart entry survives`: the fixture gains an
       unrelated `SessionStart` hook (`echo consumer-start`); after install it
       is still present beside the new one.
    4. Idempotency ignores the matcher.
       `an entry under another matcher counts as present`: after slice 2's
       re-run, rewrite the matcher of the entries carrying the pre-tool and
       version-guard commands to `Bash`, then install again — `settings.json` is
       byte-identical (`cmp`). If 2.2/1's GREEN already passes it, the mutation
       is restoring today's null-or-`Write|Edit` matcher test.
    5. `a fresh settings.json carries all three hooks`: in the scenario
       `install.sh: no ref resolves the newest dist tag`, whose fixture has no
       `settings.json`, `.hooks.PreToolUse` carries version-guard's and the
       pre-tool command and `.hooks.SessionStart` the session-start command.
  - Interfaces:
    - pre-tool command:
      `bash "${CLAUDE_PROJECT_DIR}/plugin-dev/dogfood.sh" pre-tool`
    - session-start command:
      `bash "${CLAUDE_PROJECT_DIR}/plugin-dev/dogfood.sh" session-start`
    - present = some entry under the same event carries a hook whose `.command`
      equals it, whatever the entry's `matcher`, or none

## Phase 3: recipe, docs and the migration note (type: general)

- **Item 3.1:** `toolkit/release.just` — add the `dogfood` recipe,
  `bash "{{toolkit_prefix}}/dogfood.sh" sync`, depending on no gate, with a
  one-line doc comment; add `rsync` to the header's `Requirements:` line. In
  `justfile`'s `_import-check`, after the `resume-release` block:
  `--dry-run dogfood` output must contain `dogfood.sh" sync` and must not
  contain `stub-precommit`, and the closing recap becomes
  `release.just import: ok (plain + widened + missing gate, resume-release, dogfood)`.
  Mutation gate: deleting the recipe, and adding `precommit` as its dependency,
  each fail `just _import-check`. `precommit` already carries 1.1/1's and
  2.1/1's lines; this item touches only `_import-check`.
  - Requirements: D4, D8, D10
  - Depends on: Item 1.1
  - Interfaces:
    - `just dogfood` → `bash "plugin-dev/dogfood.sh" sync`, no gate, starts no
      `claude`

- **Item 3.2:** `toolkit/migrations/v0.9.0.md` — named for a minor bump from
  `0.8.0` (new shipped scripts and a new recipe); rename it if the release picks
  another bump, since `update.sh` prints notes in (old, new] only. Its steps,
  per D12 and in this order: re-run `bash plugin-dev/install.sh`; delete any
  `.bin/claude`, its `PATH_add .bin`, and any recipe line naming it (craft's
  `precommit` shellchecks it); add `PATH_add plugin-dev/bin` after
  `PATH_add .gitlore/bin`, then `direnv allow`; ignore `/dist/plugin/`; make
  `clean` spare it.
  - Requirements: D9, D12
  - Depends on: Item 2.1, Item 2.2
  - Interfaces:
    - file `toolkit/migrations/v0.9.0.md`, one numbered step per D12 bullet

- **Item 3.3:** `toolkit/README.md` — a dogfood section: `.envrc`
  (`PATH_add plugin-dev/bin`, after gitlore's), `.gitignore` (`/dist/plugin/`),
  a `clean` that spares `dist/plugin/`, `just dogfood` then `/reload-plugins`
  for skill bodies versus a restart through the shim for agents and hook events,
  the copy lagging the source by design, both `SessionStart` warnings, launching
  from the repo root (project hooks do not fire from a subdirectory,
  `reports/probe-subdir-hooks.md`), and the `.mcp.json` caveat (run
  `just dogfood` from your own shell). Contents gains `dogfood.sh` and
  `bin/claude`, its `release.just` bullet names `dogfood`, and its `install.sh`
  bullet says it wires the version-guard and both dogfood hooks; Requirements
  gains `rsync`. In "Installing in a plugin", the prose step that wires the
  version-guard hook names the two dogfood hooks too — prose only, no fenced
  block changes. The dogfood section itself stays out of that section and
  "Updating in a plugin".
  - Requirements: D4, D7, D9, D10, D11
  - Depends on: Item 2.1, Item 2.2, Item 3.1, Item 3.2
  - Interfaces:
    - section heading `## Dogfooding`, linked from `README.md`

- **Item 3.4:** `README.md` — "What a consumer plugin gets" gains the shim and
  `just dogfood`, one line each, pointing at the manual's `## Dogfooding`; the
  opening summary's list of what ships gains the shim; "Installing in a
  plugin"'s prose sentence on wiring the version-guard hook names the dogfood
  hooks too; Requirements gains `rsync`. No fenced block changes, so
  `tests/doc-sync-test.sh` is untouched.
  - Requirements: D9, D10
  - Depends on: Item 3.3

- **Item 3.5:** `docs/design.md`, new node `docs/references/dogfood.md`,
  `docs/changelog/2026-MM-DD-dogfood-launcher.md` (dated the day it is written)
  and its `docs/changelog.md` line. The hub gains a Requirements bullet and a
  decision group linking the node, one-line conclusions only; the node holds
  D1–D12's arguments, why sync-on-edit was rejected, and the Q3 and subdirectory
  probe results with CC 2.1.284, and the outline Risks that stay true once
  shipped (CC drift and its re-run procedure, benign rsync exits, repo-wide
  promotion, the inherited variable, unguarded Bash writes, non-plugin content
  in the copy). The hub's `install.sh` summary under Distribution, and
  `docs/references/distribution.md`'s "Single `install.sh` handles bootstrap and
  wire" (which says it appends one hook), name the dogfood hooks and the
  any-matcher idempotency rule; Limitations gains the subdirectory launch and
  the unprobed macOS rsync. Present tense in hub and nodes.
  - Requirements: D1–D12
  - Depends on: Item 3.3
  - Interfaces:
    - node file `docs/references/dogfood.md`, linked from the hub's new decision
      group heading

- **Item 3.6:** `CLAUDE.md` — the Quality gate paragraph names the four dogfood
  suites above and `dogfood-launcher-test.sh`; the `docs/references/` bullet's
  node list gains `dogfood`; the Layout bullets 1.1/1 and 2.1/1 added are
  brought to the shape of their neighbours, the `release.just` bullet names
  `dogfood`, and the `install.sh` bullet says it wires the dogfood hooks beside
  version-guard. The Conventions bullet on `hook_cmd`'s single quotes extends to
  the two dogfood commands, which quote `"${CLAUDE_PROJECT_DIR}"` where
  version-guard's does not, and says why version-guard's stays unquoted.
  - Requirements: D5, D9, D10
  - Depends on: Item 3.5
