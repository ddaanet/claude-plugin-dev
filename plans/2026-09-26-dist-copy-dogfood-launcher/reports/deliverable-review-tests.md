# Deliverable review, Layer 1: tests

**Scope**: the shell suites in
`git diff fd16ae65f4b244f1098b94b7ee848f5a7f74c8f2..HEAD`:

- `tests/dogfood-launcher-test.sh`
- `tests/dogfood-pre-tool-test.sh`
- `tests/dogfood-session-start-test.sh`
- `tests/dogfood-sync-refusal-test.sh`
- `tests/dogfood-sync-test.sh`
- `tests/install-test.sh`
- `tests/update-plugin-dev-test.sh`
- `tests/dist-tree-test.sh`

The code under test is `toolkit/dogfood.sh`, `toolkit/bin/claude` and
`toolkit/install.sh`. The suites were checked against outline Items 1–4, the
runbook contracts and the D2/D5/D9 decisions.

**Method**: every mutation ran in a `git archive HEAD` extract at
`$TMPDIR/dr-tests`. Each suite copies the SUT from `$(dirname "$0")/../toolkit`,
so the mutated copy is the one that ran. A mutation was one exact-string
replacement that refuses unless its text matches exactly once. After each run
the file was restored, and the extract's `toolkit/` was compared byte for byte
with the repo's. Suites ran one at a time, in the foreground. No tracked file in
the repo was edited. `CLAUDE_PROJECT_DIR` is unset in this runner's shell.

The reports listed in the dispatch were read first: `review-code.md`,
`tdd-audit.md`, `tdd-audit-followup.md` and `orchestrator-3-report.md`. Nothing
they found or fixed is reported again below. Their accepted residuals and the
decisions my human partner already took are not findings.

## Verdict: `the shim exports the copy`

**The scenario discriminates the state of the world it claims to guard, and
invokes the shim as production does.** It has one Minor gap (F3) and one Minor
clarity issue (F4).

**Invocation.** `run_claude` runs `cd "$launch_dir"`, exports
`PATH="$shim_dir:$stubdir:$PATH"` and `CDPATH=/tmp`, then runs
`exec claude "$@"`. The shim is found by PATH lookup, not by an absolute path.
`$shim_dir` is the symlinked spelling `$sandbox/link/plugin-dev/bin`, which is
what direnv's `PATH_add` produces when the checkout was entered through a link.
The shim then runs `dogfood.sh sync` and execs the stub as the next `claude` on
PATH. One difference from production: a launch from another repo with the
consumer's shim still on PATH needs a PATH that direnv would normally have
unloaded. It is a synthetic way to separate "root from the shim" from "root from
the cwd". The realistic case is the subdirectory launch, which has its own
scenario.

**Mutations of `toolkit/bin/claude`'s root line**, run against the suite as
committed. The line is
`root="$(cd -P -- "$here/../.." && printf '%s' "$PWD" && printf x)"`.

| Mutant | Result |
|---|---|
| Logical root (`cd --`, no `-P`) | red: `the shim exports the copy: expected '…/my consumer/dist/plugin', got '…/link/dist/plugin'`. This is the only failure; the session-start follow-ons stay green, correctly, since session-start resolves entries physically |
| `root="${PWD}x"` (the launch directory) | red: the export records `…/elsewhere/dist/plugin`; `assert_absent …/elsewhere/dist` fails; `session-start takes the copy the shim exported` fails. The subdirectory and `plugin-dev/bin` scenarios also red |
| `git rev-parse --show-toplevel` from the cwd, falling back to `../..` | red with the same three failures, and only those |
| `${CLAUDE_PROJECT_DIR:-<shim-relative>}` | **green** (`all dogfood launcher scenarios passed`) with the variable unset. With `CLAUDE_PROJECT_DIR=/Users/david/code/claude-plugin-dev` exported it reds 21 assertions, but on setup (`bash: …/plugin-dev/dogfood.sh: No such file or directory`) rather than on the fixture. See F3 |

**Decoy fixture.** `$sandbox/elsewhere` is a viable consumer: a git repo, a
manifest, `/dist/plugin/` ignored, and `dogfood.sh` vendored. A cwd-derived root
syncs it instead of aborting. Both cwd-derived mutants above created
`elsewhere/dist`, so the paired `assert_absent` goes from green to red under a
wrong root. It is a transition, not a birth state, and it cannot pass vacuously.

**Stub.** The heredoc is unquoted on purpose: `$sandbox` and `$consumer` are
baked in when it is written, and the rest is escaped for run time. It records
everything the header promises: argv (NUL-separated), pid, `PWD`, `PATH`,
`CDPATH`, `CLAUDE_CODE_PLUGIN_DIRS` (`<unset>` when absent), and whether the
copy's manifest existed. Where the stub never ran, `recorded` returns
`<stub did not record …>`, so a missing record can never equal an expected
value.

**Reachability.** No assertion is behind an early exit. `assert_*` never exits,
and a failing `$(session_start …)` in an argument or inside `[[ ]]` does not
trigger errexit. Every assertion runs.

**Session-start follow-on.** It adds discrimination that the first assertion
lacks, but against `dogfood.sh`, not against the shim:

- `root_dir` made logical in `dogfood.sh` reds both follow-ons in this suite.
  The whole `dogfood-session-start-test.sh` stays green under the same mutant,
  because it never invokes the script through a symlink.
- `session_start` made always silent reds the second follow-on.
- An exact match that never exits 0 reds the first.

So the follow-on is not vacuous. The second assertion's argument is weak, though
(F4).

## Findings

### F1. The ignore list's leading-`/` anchor is unpinned

- **Location**: `tests/dogfood-sync-test.sh`, every scenario
- **Axis**: coverage / functional completeness
- **Severity**: Major
- **Problem**: D2 and the runbook's Item 1.1 contract require each ignore-list
  entry to be anchored with a leading `/`. No test fails without it.
- **Mutation**: in `sync_copy`, `printf '/%s\0' "$entry"` became
  `printf '%s\0' "$entry"`. `dogfood-sync-test.sh` and
  `dogfood-sync-refusal-test.sh` both stay green
  (`all dogfood sync scenarios passed`).
- **Probe**: a scratch fixture showed what the mutant gets wrong. It ignores
  `/build.log` and `/- dash` at the root and tracks `skills/demo/build.log` and
  `skills/- dash`. The unanchored sync exits 0 and:
  - drops the tracked `skills/demo/build.log` from the copy, because the
    unanchored `build.log` matches at any depth;
  - copies the ignored root file `- dash`, because `--exclude-from` reads an
    unanchored `- dash` as an exclude rule for `dash`.

  The anchored sync gets both right. This is a silent wrong copy: plugin content
  goes missing from the session, or ignored content is promoted into it.
- **What would pin it**: one fixture where a tracked file deeper in the tree
  shares its name with a root-level ignored entry, plus one root-level ignored
  name that starts with `- ` or `#`. Neither existing fixture shares a name
  across depths. The spaced-names fixture's ignored names (`out dir/`,
  ` lead.log`, `nl\nx.log`, `skills/a b/draft x.log`) have no tracked namesakes.
- **Side note**: deleting `--delete` while keeping `--delete-excluded` also
  survives the suite. That is not a gap: rsync's `--delete-excluded` implies
  `--delete`, so the mutant is equivalent.

### F2. `pre-tool` is never fed a payload `cwd`

- **Location**: `tests/dogfood-pre-tool-test.sh`, `run_pre_tool` (the payload is
  `{tool_name, tool_input}` only)
- **Axis**: coverage
- **Severity**: Minor
- **Problem**: D5 and the runbook contract say `<root>` never comes from "a
  payload `cwd`". The session-start suite pins that with a
  `cwd: $sandbox/elsewhere` payload, but session-start never reads stdin.
  `pre-tool` is the one subcommand that parses the payload, and its payloads
  carry no `cwd`, while a real PreToolUse payload always does.
- **Mutation**: the payload was read into a variable, and
  `root=.cwd if present`, with `path` taken from the same variable. Result:
  `all dogfood pre-tool scenarios passed`.
- **Fix**: add `cwd: "$sandbox/elsewhere"` to `run_pre_tool`'s payload. The
  existing `a path outside the repo:$sandbox/elsewhere/dist/plugin/x` case would
  then red such a root, as it already does for `CLAUDE_PROJECT_DIR`.
- **Why Minor**: a missed deny is still backed by Claude Code's own path-safety
  ask on the copy, and `root_dir` is shared, so a regression needs a
  pre-tool-specific root.

### F3. The launcher suite leaves `CLAUDE_PROJECT_DIR` to the runner

- **Location**: `tests/dogfood-launcher-test.sh` preamble and `run_claude`
- **Axis**: independence / coverage
- **Severity**: Minor
- **Problem**: the preamble unsets `CLAUDE_CODE_PLUGIN_DIRS` but neither unsets
  nor sets `CLAUDE_PROJECT_DIR`. The four `dogfood.sh` suites each set
  `CLAUDE_PROJECT_DIR="$sandbox/elsewhere"`.
- **Effect**: a shim that prefers `CLAUDE_PROJECT_DIR` passes the whole suite
  when the variable is absent, which is the normal case for a terminal
  `git commit` and for this runner (see the verdict table). When the variable is
  present, the suite reds by accident of setup:
  `…/plugin-dev/dogfood.sh: No such file or directory`. So whether D9's "root
  from its own directory" holds against that derivation depends on who runs the
  suite.
- **Fix**: export `CLAUDE_PROJECT_DIR="$sandbox/elsewhere"` in this scenario's
  launch. The decoy is already a viable consumer, so the red would come from the
  wrong copy being recorded, as it does for the cwd mutants.

### F4. The second follow-on argument is not another repo's copy

- **Location**: `tests/dogfood-launcher-test.sh`, the second session-start
  follow-on (`session_start /elsewhere/dist/plugin`, failure label
  `… another repo's copy is not rejected`)
- **Axis**: specificity / clarity
- **Severity**: Minor
- **Problem**: `/elsewhere/dist/plugin` is a literal root-level path that does
  not exist. It is not the decoy's copy (`$sandbox/elsewhere/dist/plugin`),
  which under a correct shim does not exist either. The assertion therefore
  checks only that session-start warns on a non-matching, unresolvable entry,
  which `dogfood-session-start-test.sh` already pins far more strictly. Its real
  value comes from the needle: `does not load $consumer/dist/plugin` pins the
  physical spelling of the message when the script is reached through the link
  (the logical-`root_dir` mutant reds it).
- **Fix**: relabel it to say what it pins, the physical copy named when the
  script is reached through the link.

### F5. The launcher suite invokes a second script directly

- **Location**: `tests/dogfood-launcher-test.sh`, the `session_start` helper
  inside `the shim exports the copy`
- **Axis**: conformance (CLAUDE.md: "One script under test per suite file")
- **Severity**: Minor
- **Problem**: the shim runs `dogfood.sh sync` itself, so that much is
  unavoidable. The follow-on, however, calls `dogfood.sh session-start`
  directly, through `bash "$shim_dir/../dogfood.sh"`. Production calls it as
  `bash "${CLAUDE_PROJECT_DIR}/plugin-dev/dogfood.sh"`.
- **Why it matters**: the follow-on is the only place that invokes
  `session-start` through a symlinked spelling. The logical-`root_dir` mutant
  leaves `dogfood-session-start-test.sh` green and reds only these two
  assertions; `pre-tool`'s symlink-invocation scenario covers the shared
  `root_dir`. The coverage is real but sits in the shim's suite.
- **Options**: either keep it and name it as the deliberate cross-script
  contract check, or move an invoked-through-a-symlink case into the
  session-start suite and leave the launcher asserting only on what the shim
  hands the stub. Which one is a choice for my human partner.

## Checked and found clean

**Wiring.** The `justfile` `precommit` runs `bash -n` on all eight suites, runs
`install-test.sh` and all five dogfood suites, and shellchecks
`toolkit/dogfood.sh` and `toolkit/bin/claude`. `shellcheck` over the eight suite
files is clean as well, though precommit does not run it on tests (pre-existing
convention). Each suite ran green standalone from the extract, and
`dist-tree-test.sh` ran green in the repo, where it needs the index
(`dist tree ok (11 files, bin/claude executable, no gitlink)`).

**Outline Items 1–4.** Every enumerated case is present and reached:

- **Item 1:** deletion, worktree deletion, ignored paths, spaces, the five
  pattern characters, `.git`, nested `.git` (gitfile and directory),
  `dist/plugin/` on the first sync, both refusals, and rsync status and stderr.
- **Item 2:** `file_path` and `notebook_path` three-channel denies, source and
  outside allows, repo symlink, silence without jq, and session-start silence
  for several entries, a symlinked spelling and a trailing slash. Session-start
  warns when the variable is unset, names another repo's copy, or holds the copy
  only as a substring, on both channels. The missing-jq warning is on
  `systemMessage` only.
- **Item 3:** exact argv, the overwritten inherited value, stripping in any
  spelling, the subdirectory launch, abort on sync failure, and 127.
- **Item 4:** both hooks added once, the re-run no-op, existing settings kept,
  the matcher-less entry, the quoted commands, and presence under any matcher.

**Mutations that went red as they should.** Each of these is one mutation, with
the suite it redded and the assertion that caught it.

- **Sync**:
  - no `--delete-excluded` → the becomes-ignored test;
  - `/.git` anchored → the nested-repo tests;
  - no hard `/dist/plugin/` exclude → first-sync recursion;
  - no pattern-character refusal → the backslash case;
  - no manifest check;
  - no ignored-copy check;
  - check-ignore without the trailing slash;
  - git error tolerated → the symlinked `dist/plugin` scenario;
  - no `pipefail` → the git failure scenario;
  - the list-build failure swallowed → the pattern-character cases;
  - no `--from0` → the spaces, `.git` and becomes-ignored tests;
  - `read` without `IFS=` → the leading-space name;
  - rsync stderr hidden;
  - rsync status replaced.
- **Pre-tool**:
  - no `notebook_path`;
  - an unanchored copy match → the outside-the-repo path;
  - no `physical_path`;
  - no leaf `readlink`;
  - no jq guard;
  - the source taken from the spelled path;
  - the denied path dropped from the reason;
  - a two-line `systemMessage`.
- **Session-start**:
  - a substring match;
  - no entry resolution;
  - no ANSI reset;
  - `additionalContext` without the copy;
  - first entry only and last entry only → one of several;
  - the jq message put on `hookSpecificOutput`.
- **Shim**:
  - string-compare stripping → the strip scenario, via the watchdog;
  - `CDPATH` kept;
  - exit 1 instead of 127;
  - sync failure ignored;
  - no `exec` → the pid assertion;
  - the inherited variable kept;
  - empty PATH entries dropped;
  - `cd` to the root before exec → the subdirectory `PWD`.
- **install.sh**:
  - the pre-tool matcher narrowed to `Write|Edit`;
  - a `SessionStart` matcher;
  - an unquoted command;
  - presence keyed on the matcher;
  - no session-start hook;
  - the event array replaced instead of appended.

**Two survivors, both already known.** The trailing-slash strip for an
unresolved entry is the orchestrator's accepted residual, "literal-compare rule
… unpinned". The `--delete` removal is equivalent, per F1's side note.

**The split suites.** `update-plugin-dev-test.sh` still exercises only the
update-side call site after the split, and its refusal scenario no longer needs
the manifest it used to create. `install-test.sh` carries the moved scenarios
verbatim, plus the new wiring assertions and the runtime check that runs each
written hook command through `sh -c` from a project directory with a space in
its path.

**`dist-tree-test.sh`.** The `bin/claude` mode check reads the index, which is
what a pre-commit hook is about to commit. An absent entry fails it, since the
mode reads empty.

**Independence.** Every scenario takes a fresh `mktemp -d` sandbox, and
`make_consumer` resets the launcher's per-scenario globals. The fixtures use
physical (`pwd -P`) spellings. Git's leaked environment is unset in every suite,
and `CDPATH` is unset as well. The only runner-environment dependency found is
F3.
