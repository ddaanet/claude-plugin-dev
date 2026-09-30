# Review: Item 2.1/6 test review — no next claude exits 127

**Scope**: uncommitted diff to `tests/dogfood-launcher-test.sh` (scenario
`=== no next claude exits 127 ===` and the new `$path_exact` option on
`run_claude`), against the RED report `reports/item-2-1-s6-red.md` **Date**:
2026-09-30 **Mode**: review + fix

## Summary

The scenario's fixture is sound: the PATH is exact (nothing inherited), the
tools directory holds everything the shim and `dogfood.sh sync` run, the sync is
proven to have run, and `run_claude` bounds the launch with the watchdog. The
stderr assertion was too loose to discriminate, though. A wrong GREEN, which
prints the line and then falls through to the failing `exec`, passed the whole
suite. That was demonstrated with an in-place SUT mutation. The assertion now
pins the whole of stderr to the interface line. The tools-has-no-claude
precondition is now the `command -v` lookup the runbook asks for.

**Overall Assessment**: Ready

## Mechanical check

The RED run was reproduced against the unchanged SUT. Before the fixes, it
failed on the stderr assertion:
`FAIL: no next claude exits 127: stderr does not say so: …/plugin-dev/bin/claude: line 22: exec: claude: not found`.
It also failed on that assertion after them:
`FAIL: … stderr is the shim's one line: expected 'dogfood: no other claude on PATH', got '…/plugin-dev/bin/claude: line 22: exec: claude: not found'`.
Neither run was an ERROR, and the other 11 scenarios passed in both.
`shellcheck` is clean.

## Issues Found

### Critical Issues

None.

### Major Issues

1. **The stderr assertion passes a GREEN that does not implement the exit**
   - Location: `tests/dogfood-launcher-test.sh`, the scenario's
     `grep -qF "no other claude on PATH"`
   - Problem: bash's own failed `exec` exits 127, so the `rc == 127` assertion
     is satisfied by the unimplemented shim, which leaves the grep as the only
     discriminator. The grep is a substring check with no `dogfood:` prefix. A
     GREEN that runs
     `command -v claude >/dev/null || echo "dogfood: no other claude on PATH" >&2`
     and then falls through to `exec claude "$@"` prints the phrase and exits
     127 through bash's exec failure. The suite passed in full against that
     mutation (`all dogfood launcher scenarios passed`). The same looseness
     would pass a message without the `dogfood:` prefix that the interface line
     specifies. It would also pass a sync that exits 127 on a missing command
     while something else prints the phrase.
   - Fix:
     `assert_eq "$(cat "$sandbox/stderr")" "dogfood: no other claude on PATH"`,
     so stderr must be the shim's one line and nothing else. This pins the
     prefix, rules out bash's `exec: claude: not found` line (so the 127 must be
     the shim's own exit), and rules out any sync noise, such as a
     `command not found` from a tool missing from the tools directory.
   - **Status**: FIXED. Re-run against the same wrong-GREEN mutation, the
     scenario reds with the two-line stderr shown.

### Minor Issues

1. **The no-claude precondition was a file check, not the lookup the runbook
   names**
   - Location: `assert_absent "$sandbox/tools/claude" …`
   - Problem: the runbook says "holding no `claude` (asserted first with
     `command -v`)". The fact the negative depends on is that a lookup under
     what the shim leaves of PATH finds nothing. `assert_absent` on one spelling
     of one file is a proxy for that. It does not name the lookup, and it would
     miss anything that resolves differently from that literal path.
   - Fix: `found="$(PATH="$sandbox/tools" command -v claude || true)"`, asserted
     empty. The existing positive (`command -v claude` under the full PATH is
     the shim) stays, which pairs the negative with a positive over the same
     fixture.
   - **Status**: FIXED

2. **`$path_exact` was cleared by an `unset` after the call instead of being
   reset in `make_consumer`**
   - Location: `run_claude` header, `make_consumer`, `unset path_exact` in the
     scenario
   - Problem: `$path_head`, the sibling option, is reset in `make_consumer` and
     documented in its header. `$path_exact` relied on each scenario that sets
     it remembering to `unset` it afterwards. It was not listed with the other
     fixture variables. The `run_claude` comment line also ran to 81 columns,
     where the file wraps its comments at 80.
   - Fix: `make_consumer` sets `path_exact=""` and documents it beside
     `$path_head`. The scenario's `unset` is dropped, and the comment is
     reflowed.
   - **Status**: FIXED

## Checks with no finding

- **`$path_exact` leaves other scenarios unchanged.** It is empty unless set.
  `${path_exact:-}` is safe under `set -u`, and the `else` branch is the old
  line verbatim. All 11 other scenarios passed on every run: unchanged SUT, both
  mutations, and after the fixes. The SC2030 directive now sits above the `if`
  and covers both `export`s. `shellcheck` is clean.
- **The tools directory is sufficient.** The shim runs `bash` (through the
  `env bash` shebang and for `dogfood.sh`) and `dirname`. `sync` runs `dirname`,
  `git`, `mktemp`, `mkdir` and `rsync`, and its EXIT trap runs `rm`. `cd` and
  `printf` are builtins. The right-GREEN run passed with stderr held to the one
  line, which proves the sync ran to completion silently under that PATH.
  `assert_file` on the copy's manifest, which is absent at fixture birth, proves
  the sync ran.
- **Watchdog.** `run_claude` always runs under it, so a GREEN that loops (for
  example, by re-finding the shim) fails at 10 s rather than hanging.
- **Whitespace.** `$shim_dir` contains `my consumer`. Every use is quoted, and
  PATH entries holding a space are looked up correctly: the positive
  precondition passes with that spelling.

## Mutated-SUT runs

Each mutation is an in-place exact-string replace of `toolkit/bin/claude`'s
`exec claude "$@"` line, restored by the inverse replace. After all runs,
`git status --short toolkit/` was empty and `grep -c 'no other claude'` gave 0.

| Mutation | Before fixes | After fixes |
|---|---|---|
| none (RED) | red on stderr | red on stderr |
| line, then fall through to `exec` (wrong GREEN) | **green** | red on stderr |
| `command -v claude … \|\| { echo "dogfood: no other claude on PATH" >&2; exit 127; }` (right GREEN) | — | green, all scenarios |

## Fixes Applied

- `tests/dogfood-launcher-test.sh` `make_consumer` header — `$path_exact`
  documented beside `$path_head`.
- `tests/dogfood-launcher-test.sh` `make_consumer` — `path_exact=""` reset.
- `tests/dogfood-launcher-test.sh` `run_claude` header — reflowed to 80 columns.
- `tests/dogfood-launcher-test.sh` scenario comment — states why stderr must be
  exactly the shim's line: bash's exec failure and a sync missing a command both
  exit 127.
- `tests/dogfood-launcher-test.sh` scenario — `assert_absent tools/claude`
  replaced by `command -v claude` under the tools-only PATH, asserted empty.
- `tests/dogfood-launcher-test.sh` scenario — `unset path_exact` dropped.
- `tests/dogfood-launcher-test.sh` scenario — substring `grep` replaced by
  whole-stderr equality with `dogfood: no other claude on PATH`.

## Requirements Validation

| Requirement | Status | Evidence |
|---|---|---|
| Slice 6: PATH = shim dir + tools dir of symlinks, no `claude` | Satisfied | `path_exact="$shim_dir:$sandbox/tools"`, symlink loop |
| Slice 6: no-claude asserted first with `command -v` | Satisfied | both `command -v` preconditions, before `run_claude` |
| Slice 6 / interface: exit 127 | Satisfied | `assert_eq "$rc" "127"` |
| Interface: `dogfood: no other claude on PATH` on stderr | Satisfied | whole-stderr `assert_eq` |

## Positive Observations

- An exact PATH with nothing inherited removes the runner's own `claude` as a
  way for the negative to pass by accident.
- The copy-manifest assertion separates "the shim found no claude" from "the
  sync failed with 127".
