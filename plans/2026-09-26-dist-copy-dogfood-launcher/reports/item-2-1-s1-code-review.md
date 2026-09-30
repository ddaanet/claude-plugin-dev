# Review: Item 2.1 slice 1 — code review (post-GREEN)

**Scope**: commit `✨ Item 2.1/1 — the shim syncs and execs the next claude`
(HEAD): `toolkit/bin/claude`; gate bookkeeping in `tests/dist-tree-test.sh`,
`justfile`, and the new CLAUDE.md Layout bullet. Tests not edited. **Date**:
2026-09-30 **Mode**: review + fix

## Summary

The shim meets the slice 1 contract. Its `here`/`root` derivation is
newline-safe and matches `dogfood.sh`'s `root_dir` shape. Two defects in the
PATH rebuild changed PATH beyond the removal of the shim's own entry, and both
are fixed. Also fixed: an inaccurate claim in the Layout bullet, and two wording
points in the dist-tree check.

**Overall Assessment**: Ready

## Issues Found

### Critical Issues

None.

### Major Issues

1. **PATH capture strips a trailing newline from the last entry**
   - Location: `toolkit/bin/claude` main, `PATH="$(path_without "$here")"`
   - Problem: command substitution drops trailing newlines, so a last PATH entry
     ending in `\n` reached the next claude without it. Probed: PATH
     `…:/bin:$s/tail\n` came back from the stub ending `…/tail`.
   - Fix: capture with the file's own sentinel pattern,
     `path="$(path_without "$here" && printf x)"; export PATH="${path%x}"`.
     Re-probed: the stub recorded `…/tail\n`.
   - **Status**: FIXED

2. **A leading empty PATH entry was dropped**
   - Location: `toolkit/bin/claude` `path_without`, `out="${out:+$out:}$entry"`
   - Problem: when `out` is empty, an empty first entry cannot be told apart
     from no entry, so the empty entry was lost. A PATH of
     `:<shim dir>:<stub>:…` reached claude as `<stub>:…`, with the working
     directory silently removed from the search. Only the shim's own entry is
     supposed to go.
   - Fix: add each kept entry as `:$entry` and strip one leading colon on output
     (`printf '%s' "${out#:}"`), with a two-line comment explaining why.
     Re-probed: recorded `:<stub>:/usr/bin:/bin`. `PATH=""`, `PATH=":"`, `a::b`
     and trailing `:` keep their shape by the same arithmetic.
   - **Status**: FIXED

### Minor Issues

1. **Layout bullet claims vendoring puts the shim on PATH**
   - Location: `CLAUDE.md` Layout, `toolkit/bin/claude` bullet
   - Note: "first on PATH once vendored" is wrong. Vendoring leaves PATH alone.
     D9 says the consumer's `.envrc` puts it there (`PATH_add plugin-dev/bin`),
     and `install.sh` wires only `.claude/settings.json` (D11). The bullet now
     says the consumer's `.envrc` puts it first on PATH as `plugin-dev/bin`. The
     rest of the bullet was already accurate and is unchanged. Item 3.6 aligns
     it further.
   - **Status**: FIXED

2. **Header comment omitted the CDPATH unset from the shim's effects**
   - Location: `toolkit/bin/claude` header
   - Note: the only comment on the unset gives the `cd` reason, but the
     interface also requires the exec'd claude to inherit no CDPATH. A reader
     could take the unset as only a local guard and move it. The header now
     lists "with CDPATH unset" among the effects. The inline comment stays
     word-for-word the same as `dogfood.sh`'s.
   - **Status**: FIXED

3. **dist-tree mode check: title says "committed", check reads the index**
   - Location: `tests/dist-tree-test.sh` section echo
   - Note: this file deliberately asserts against the index, not history (see
     its comment above the set check). The title now reads "is executable in the
     index", which matches the failure message.
   - **Status**: FIXED

4. **dist-tree sign-off recap omitted the new check**
   - Location: `tests/dist-tree-test.sh` final echo
   - Note: a quiet gate lists the checks that passed. The recap now reads
     `(N files, bin/claude executable, no gitlink)`.
   - **Status**: FIXED

## Probes requested

- **Whitespace/newline safety**: `here` (`dirname … && printf x`, `${here%?x}`)
  and `root` (`cd -P -- … && printf '%s' "$PWD" && printf x`, `${root%x}`) hold
  up. Probed with a consumer directory whose name ends in `\n`: the exported
  value was `…/nl\n/dist/plugin`. The PATH rebuild had the two defects above,
  both now fixed. The suite's `my consumer` fixture covers spaces.
- **Header truthfulness**: accurate for this slice once CDPATH was added. "the
  next claude on PATH" holds only while the shim's entry is spelled as its
  `dirname`. That is slice 3's by-design gap and is not flagged.
- **Consistency with `dogfood.sh`**: same `set -euo pipefail`, the same
  `unset CDPATH` line and comment, and the same sentinel pattern for `here`.
  `root` is inlined rather than put in a `root_dir` function, which is
  equivalent: one caller, and a `..` deeper.
- **bash 3.2 / BSD**: `[[ ]]`, `${BASH_SOURCE[0]}`, `${v%%…}`/`${v#…}`, `local`,
  `cd -P --` and `dirname` are all 3.2- and BSD-safe, and the shim uses no
  GNU-only tool. Not run under a real bash 3.2, since none is on this box.
  Residual: `exec claude "$@"` with no arguments under `set -u` is the same
  pattern `dogfood.sh`'s `main "$@"` already ships.
- **`set -e` and slice 5**: slice 5's behaviour already holds.
  `bash …/dogfood.sh sync` is a plain command in `main`, which is called outside
  any `if`/`&&`/`||` context, so errexit exits with sync's status before the
  export and the exec. Probed with the manifest removed: stderr was
  `dogfood: …/.claude-plugin/plugin.json not found; sync refused`, rc=1, and the
  stub recorded nothing.
  **Slice 5 will pass on arrival and needs a mutation proof** (e.g.
  `… sync || true`). Also noted, not probed with the suite: slice 2 (the
  inherited variable is overwritten) holds too, since a plain `export`
  overwrites. Slice 4 (subdirectory launch) very likely holds, because `<root>`
  comes from `BASH_SOURCE`. Both need the same treatment.
- **dist-tree mode assertion**: sound. It reads the stage-0 index mode, which is
  what the next split tag is cut from, and `core.fileMode=false` does not affect
  it. An absent file yields `''` and fails with a clear message, and the
  exact-set check fails alongside it. A conflicted multi-stage entry yields
  several lines and fails, which is acceptable. A `git ls-files` failure aborts
  under `set -e` with git's own stderr.
- **justfile wiring**: the shim is in the `shellcheck` line, and the suite is in
  the `bash -n` line and the run list. Correct.

## Mutated-SUT run

Mutation: `root="$(cd -P -- "$here/../.."` → `root="$(cd -- "$here/../.."`
(logical root), applied and inverted by exact-string edit.

- Mutated:
  `FAIL: the shim exports the copy: expected '…/my consumer/dist/plugin', got '…/link/dist/plugin'`,
  rc=1. The other three tests stayed green, as expected, because they do not use
  the symlinked spelling.
- Restored: `grep -nF 'root="$(cd -P -- "$here/../.."'` matched line 15. The
  suite is green (4/4), and the index mode is still 100755.

(A first attempt with `sed` did not match its regex and changed nothing. The
file was confirmed unchanged before the exact-string edit was used.)

## Fixes Applied

- `toolkit/bin/claude` main: sentinel-captured PATH rebuild through a new local
  `path`, so a trailing newline on the last entry survives.
- `toolkit/bin/claude` `path_without`: colon-prefix accumulation with
  `${out#:}`, so a leading empty entry survives. Two-line comment added.
- `toolkit/bin/claude` header: "with CDPATH unset" added to the stated effects.
- `CLAUDE.md` Layout: the bullet now says the consumer's `.envrc` puts the shim
  on PATH.
- `tests/dist-tree-test.sh`: the section title reads "is executable in the
  index", and the sign-off recap includes `bin/claude executable`.

Post-fix: `bash tests/dogfood-launcher-test.sh`, `bash tests/dist-tree-test.sh`
and `bash tests/doc-sync-test.sh` are green. `shellcheck toolkit/bin/claude` is
clean.

## Requirements Validation

| Requirement | Status | Evidence |
|-------------|--------|----------|
| D9 root from own location, physical | Satisfied | `cd -P -- "$here/../.."`; the mutation reds "exports the copy" |
| D9 sync, export, unset CDPATH, exec | Satisfied | `main`; tests 1–4 |
| D9 strip by `-ef` identity | Partial by design | Exact-spelling strip; slice 3 |
| D8 failed sync aborts before exec | Satisfied (untested) | errexit; probed rc=1, no exec; slice 5 |
| D4 sync at launch only | Satisfied | Sync runs once, before exec, and nowhere else |

**Gaps:** none outside the slices deferred to 2–6.

## Recommendations

- The two PATH fixes have no test. Neither the newline nor the leading-empty
  case is in the suite. Slice 3 already asserts on the recorded PATH, so a
  leading-`:` entry could go into its fixture at little cost. That is a
  test-side decision for the orchestrator, not made here.
- No REFACTOR-NEEDED.
