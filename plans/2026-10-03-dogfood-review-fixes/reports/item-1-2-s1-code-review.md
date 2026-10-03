# Review: Item 1.2/1 code review — `pre-tool` maps a jq failure to a non-blocking status

**Scope**: `pre_tool` and its header comment in `toolkit/dogfood.sh`, as changed
by GREEN commit d6df153. Tests out of scope and not edited. **Date**: 2026-10-03
**Mode**: review + fix

## Summary

GREEN adds `|| exit 1` to both jq calls in `pre_tool`: the payload read and the
deny build. jq's stderr is untouched. The code is minimal and correct, and it
holds under bash 3.2. The one finding is in the comment. Its rationale cited
only jq 1.6's parse-error status. jq 1.7 also exits 2 on a usage or system error
(probed). The comment also called the non-jq failure path "non-zero" next to the
new "exits 1". Both are fixed in place, and the comment kept the same line
count.

**Overall Assessment**: Ready

## Exit-path audit: can anything leave `pre_tool` with status 2?

| Path | Status on failure | Evidence |
|---|---|---|
| `command -v jq … \|\| exit 0` | 0 | stand-down by design |
| `root="$(root_dir …)"` | 1 (cd/dirname), 127 (missing dirname) | `cd -P --` failure is 1 (probed); errexit propagates the substitution's status |
| `path="$(jq -j …)" \|\| exit 1` | 1 | GREEN; covered by tests 1–2 |
| `physical="$(physical_path …)"` | 1 | every failing step inside is an explicit `exit 1`; probed a mode-000 directory on the path, which gives `cd: … Permission denied` and status 1 |
| `[[ -L … && -e … ]]` | n/a | `if` condition; errexit is exempt |
| `physical="$(readlink -fn …)"` | 1 | GNU and BSD readlink exit 1 on failure and on a bad option. `-e` has already passed, so it is reachable only through a race |
| `jq -nc … \|\| exit 1` | 1 | GREEN; covered by test 3 |
| `set -u` unbound variable | 127 (bash 5.2, probed) | not 2; and every variable is set |
| bash syntax error | 2 | ruled out by `bash -n` in precommit |

No path out of `pre_tool` carries status 2. The non-jq paths (`root_dir`,
`physical_path`, `readlink`) already exit 1, so no widening was needed. Outside
`pre_tool`, `usage` exits 2. It is reachable only through a hook command
miswired to a subcommand other than `pre-tool`, and `install.sh` writes that
subcommand fixed. That is outside m1 and outside this slice. It is noted here
and not raised as a finding.

`set -e` on `var="$(…)" || exit 1`: errexit is off inside the substitution, so a
failing jq short-circuits `&& printf x`. The assignment then takes jq's status.
That status is on the left of `||`, so errexit does not fire and the explicit
`exit 1` does. bash 3.2 has the same semantics, and the change uses no newer
construct.

## Issues Found

### Critical Issues

None.

### Major Issues

None.

### Minor Issues

1. **The comment's rationale was narrower than the mechanism, and its two exit
   claims disagreed in precision.**
   - Location: `toolkit/dogfood.sh`, `pre_tool` header comment (the sentences
     after "into the copy is not refused here.").
   - Note: the comment justified never passing jq's status through only by "jq
     1.6 exits 2 on a parse error". On a 1.7 host a reader could take the
     mapping as legacy and drop it. The probe here showed jq 1.7 exiting 2 on
     `Could not open file` and on `Unknown option`. The preceding sentence also
     said an unreadable payload or an unenterable directory "stops the script
     non-zero", while the next one said "exits 1". The probe confirmed exit 1
     for the directory case too. There was also a ragged short line left from
     the insertion.
   - **Status**: FIXED. "non-zero" now reads "with exit 1". The rationale now
     reads: jq exits 2 on a usage or system error, and on a parse error in 1.6,
     and exit 2 from a PreToolUse hook blocks the tool call. The paragraph was
     reflowed. It is the same 8 lines, with no narration added.

## Fixes Applied

- `toolkit/dogfood.sh`, `pre_tool` header comment: Minor 1. The change is
  comment-only, and the code is unchanged.

## Mutated-SUT run

- Mutation (exact replacement, in place, on the `path=` line): `|| exit 1`
  became `|| exit $(( $? == 2 ? 1 : $? ))`. This is the plausible GREEN that
  maps only status 2 and passes every other jq status through.
- Result: the suite redded.
  `FAIL: pre-tool fails loudly on a payload jq cannot read exit code: expected '1', got '5'`
  This was 1 failure. The stub-2 and deny-build scenarios stayed green, as
  expected, because that mutation maps their status correctly.
- Restored by the inverse exact replacement. `git diff` afterwards shows only
  the comment fix.
- The test review already probed the complementary half-GREEN (read mapped, deny
  build unmapped) and that one redded. So both "only one call" and "only status
  2" are detected.

## Verification

- `bash tests/dogfood-pre-tool-test.sh`, after the restore, in the foreground:
  all dogfood pre-tool scenarios passed.
- `just precommit`, in the foreground: exit 0. The log shows version-guard,
  check-version, release, update-plugin-dev, install, the dogfood sync, sync
  refusal, pre-tool, session-start and launcher suites all passed, with the
  linters and doc checks ending in `ok`.
- Nothing committed. Changed tree: `toolkit/dogfood.sh` (comment).

## Requirements Validation

| Requirement | Status | Evidence |
|---|---|---|
| m1: `pre-tool` never exits 2 on a jq failure | Satisfied | both jq calls end `\|\| exit 1`; exit-path audit above |
| m1: map to a non-blocking non-zero status (chosen: 1) | Satisfied | exit 1 at both sites; the suite asserts `rc == 1` in three scenarios |
| m1: assert the exact status in the suite | Satisfied | the mutated-SUT run redded on the exact-status assertion |
| jq stderr kept (no-stderr-suppression) | Satisfied | no redirect on either jq call; the suite asserts the diagnostic on stderr |

## Positive Observations

- The minimal change keeps `$(… && printf x)` newline shielding intact. The
  mapping sits outside the substitution, so it cannot leak into the captured
  value.
- No blanket `main "$@" || exit 1` or ERR trap was used. Either would also have
  rewritten `sync`'s rsync status, which that subcommand's contract passes
  through.

## Recommendations

None in scope. No `REFACTOR-NEEDED`.
