# Review: Item 1.1/1 code review — the shim syncs only outside a dogfood session of its own repo

**Scope**: `toolkit/bin/claude` as changed by 9104046: the sync condition and
its header comment. **Date**: 2026-10-03 **Mode**: review + fix

## Summary

The change wraps `dogfood.sh sync` in
`[[ "${CLAUDE_CODE_PLUGIN_DIRS-}" != "$root/dist/plugin" ]]` and leaves the
export unconditional. That matches decision 1 word for word. The comparison is
exact string equality against the physical root (`cd -P`), so a list value or a
logical spelling syncs. One minor comment gap was fixed: the header now states
why `<root>` must be physical, because this change makes `cd -P` load-bearing.

**Overall Assessment**: Ready

## Checks

- **Conformance to the decision.** Sync runs unless the variable equals
  `<root>/dist/plugin`, where `<root>` is the physical root the shim already
  computes. The export at the next line runs on both branches. The variable
  unset, empty, another path, or a list that includes the copy all sync, which
  the decision's word "equals" requires.
- **`set -u` safety.** `${CLAUDE_CODE_PLUGIN_DIRS-}` expands to empty when the
  variable is unset. Set-but-empty also syncs, since `-` and `:-` behave the
  same against a non-empty right-hand side.
- **Literal comparison.** The right-hand side is quoted inside `[[ ]]`, so it is
  compared as a string and not matched as a glob. Checked on a root containing
  `[1]`: quoted, it skips correctly. Unquoted, it would sync inside the live
  session it is meant to protect.
- **Whitespace and trailing newlines in `$root`.** `$root` comes from the
  existing `printf x` / `${root%x}` capture, so a trailing newline survives, and
  `[[ ]]` does not word-split. The suite's consumer is `my consumer`, so the
  space case runs on every scenario.
- **bash 3.2 / macOS.** The change uses only `[[ != ]]` with a quoted operand
  and `${var-}`, both available in bash 3.2 with the same semantics. It adds no
  external command.
- **Comment.** The new paragraph is accurate and gives the reason (re-promoting
  under a live session), not a narration of the code. "exactly" carries the
  equals-not-contains reading. The opening paragraph still says it "syncs … and
  then execs" with no qualifier, but the qualifier is the very next sentence, so
  it is not misleading.
- `bash -n` and `shellcheck` are clean.

## Mutated-SUT run (once, in place)

- Mutant: the comparison's right-hand side unquoted, `!= "$root/dist/plugin"`
  changed to `!= $root/dist/plugin` (glob pattern matching). Applied and
  restored by exact inverse string replacement. After restore,
  `git diff --stat -- toolkit/bin/claude` was empty.
- Result: **the whole launcher suite stayed green.** No fixture root contains a
  glob metacharacter, so the suite detects a missing sync but not this
  wrongness. The shim as committed is correct, as shown by the direct probe
  above. Tests are OUT of this review's scope; see Recommendations.
- The test review already killed the logical-root (C) and list-entry (D) mutants
  against this suite.

## Issues Found

### Critical Issues

None.

### Major Issues

None.

### Minor Issues

1. **The header did not say why `<root>` must be the physical path**
   - Location: `toolkit/bin/claude`, header comment, the `<root>` lines
   - Note: before this change, `cd -P` only made a tidy path. Now the skip test
     depends on it: the inherited variable is the physical path the outer shim
     exported, and a nested `claude` may reach the shim through a symlinked PATH
     entry. If someone "simplified" `cd -P` to `cd`, the comparison would stop
     matching and the shim would sync under the live session. A test (mutant C)
     catches that, but nothing in the code said so.
   - **Status**: FIXED. The comment now says `<root>` is resolved physically
     because the variable carries the physical path, so a symlinked spelling
     still matches.

## Fixes Applied

- `toolkit/bin/claude` header comment: the `<root>` sentence now gives the
  reason for physical resolution. Comment only, no code change.
- Verified: `shellcheck` clean, `bash tests/dogfood-launcher-test.sh` all
  scenarios passed, `just precommit` exit 0 (`ok`). Nothing committed.

## Requirements Validation

| Requirement | Status | Evidence |
|---|---|---|
| Sync unless the variable equals `<root>/dist/plugin` (physical root) | Satisfied | `toolkit/bin/claude` `main`: quoted `[[ != ]]` against `$root` from `cd -P` |
| Export the variable in every case | Satisfied | the `export` sits outside the conditional |
| Unset → syncs; equal → no sync and still execs with the variable; other path → syncs and overrides | Satisfied | launcher scenarios "the shim syncs before exec", "a variable equal to this copy skips the sync", "an inherited variable is overwritten", "a variable listing this copy among others syncs" |

**Gaps:** none in scope. The failed-sync `dogfood:` line (m3) is the next slice
and is not assessed here.

## Positive Observations

- The change is minimal: one conditional around the existing call. The export,
  PATH filtering and exec are untouched.
- `${VAR-}` with a quoted literal operand is the correct `set -u`-safe,
  glob-free form.
- The header states the condition, the reason and the export invariant in one
  paragraph, in the file's existing voice.

## Recommendations

- A later test pass could name a fixture root with a glob metacharacter (for
  example `my [consumer]`) so that the unquoted-pattern mutant reds. That
  belongs to a test slice, not this code review.
