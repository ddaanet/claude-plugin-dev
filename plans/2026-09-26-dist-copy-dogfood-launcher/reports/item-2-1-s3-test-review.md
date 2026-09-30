# Review: Item 2.1 slice 3 — test review (RED)

**Scope**: the three new scenarios and the `path_head` harness change in
`tests/dogfood-launcher-test.sh` (`git diff`), and the RED report
`reports/item-2-1-s3-red.md`. `toolkit/bin/claude` was touched only by
mutations, each restored by the inverse exact-string replacement. **Date**:
2026-09-30 **Mode**: review + fix

## Summary

The RED run is valid: `strips its own entry in any spelling` reds genuinely, as
a watchdog kill, and the stub never runs. Two gaps are fixed. First, the fixture
could not tell `-ef` from string normalisation: a shim that strips on
`${entry%/}` would have passed the whole suite. Second, the "no shim entry left"
count could pass on an empty or unsplit recorded PATH. The scenario now puts two
more spellings of the shim behind the stub, one through a symlinked directory
and one with `/./`, and adds a positive control. The two mutation-proven tests
red under mutations of my own. All three survive a runner PATH that already
holds empty entries.

**Overall Assessment**: Ready

## Mechanical check

Suite run in the foreground, SUT identical to HEAD.

- Before the fixes: 2 FAIL, both in the first scenario, rc 1, about 11.3 s:
  - `the launcher ran past the 10 s watchdog`
  - `the stub ran: '<sandbox>/rec/path' is not a regular file`
- After the fixes: 3 FAIL, all in the first scenario, rc 1, about 11.2 s. The
  new positive control adds
  `the recorded PATH splits to the stub's entry: expected '1', got '0'`.
- The other seven scenarios pass. `bash -n` and `shellcheck` are clean. The
  suite is 255 lines.

### Mutation proofs, reproduced with different mutations

Each mutation was one exact-string replacement in `toolkit/bin/claude`, made by
a scratch script that asserts a single match. Each was reverted by the swapped
replacement before the next one was applied.

| Mutation | Target test | Result |
|---|---|---|
| C′ `path_without` also drops an entry whose last component equals the shim dir's (`bin`) and that holds a `claude`: `[[ "$entry" == "$1" \|\| ( "${entry##*/}" == "${1##*/}" && -e "$entry/claude" ) ]]` | keeps another bin/claude | both assertions red: `expected 'ran', got '<stub did not record other>'` and `'<sandbox>/rec/argv' exists` |
| D `rest="$PATH:"` → `rest="${PATH#:}:"` (a leading empty entry is lost) | keeps the rest of PATH as spelled | `expected ':<stub>:…', got '<stub>:…'` |

- C′ also reds `keeps the rest of PATH as spelled` on this box, because the
  runner's `~/.local/bin` holds a real `claude`. That is a side effect of the
  mutation, not of the test.
- An earlier, broader C (drop every `*/bin` entry) removed `/usr/bin` and failed
  every scenario with rc 127, like the RED report's. It was discarded as a proof
  because it does not isolate the test.
- Restore check after each mutation:
  - `grep -c '##\*/'` and `grep -c 'PATH#:'` on the SUT printed `0`.
  - `git diff --quiet toolkit/bin/claude` exited 0.
  - The suite came back to exactly the three slice-3 failures.

## Wrong-reason hunting

- **The watchdog kills the loop.** The looping shim re-`exec`s itself, so the
  whole chain is one pid, which is `$launch_pid`. I polled `ps` every 0.5 s
  through a full run:
  - Up to the kill, the loop showed as pid 223 with a fresh `dogfood.sh sync`
    and `rsync` child on each hop.
  - After the kill, no `claude`, `dogfood.sh` or `rsync` from that sandbox was
    left.
  - An in-flight sync child is orphaned by the kill and ends within
    milliseconds.
  - The watcher that fired is reaped by `wait "$watcher"`. The only survivors
    are the `sleep 10` orphans of watchers killed in passing scenarios. Slice 1
    made that choice on purpose; they hold no pipe.
- **A vacuous "no shim entry left" count.** An empty recorded PATH, or one read
  unsplit, counted 0 and passed that assertion. `assert_file` covered only the
  stub never running. **Fixed:** the same loop now counts entries whose `claude`
  is `-ef` the stub and asserts exactly 1. That fails on an empty PATH, on an
  unsplit PATH (`<whole>/claude` does not exist) and on a missing record.
- **`-ef` against string normalisation.**
  - With `$shim_dir/:$shim_dir` both ahead of the stub, a shim that strips
    `${entry%/} == ${1%/}` removes both on the first hop and passes.
  - Adding more spellings *ahead* of the stub would not help. Each hop runs the
    shim under that entry's own spelling (`dirname` of it is the entry), so a
    normalising shim strips each spelling as it hops through it and reaches the
    stub after one extra sync.
  - Only an entry *behind* the stub is never hopped through, so only the first
    hop's identity test can remove it. **Fixed:** `path_head` now continues
    `…:$stubdir:$sandbox/link/plugin-dev/bin:$consumer/plugin-dev/./bin`, with
    `$sandbox/link` → `$consumer`.
- **Candidate shims against the fixed fixture**, as scratch mutations of the
  strip line, each restored:

  | Candidate | Result |
  |---|---|
  | HEAD (exact spelling) | watchdog kill, stub never ran |
  | `${entry%/}` normaliser | `entries of the shim left on PATH: expected '0', got '2'` |
  | `realpath -sm` lexical normaliser | `… got '1'` (the symlinked spelling survives) |
  | `[[ "$entry/claude" -ef "$1/claude" ]]` | all scenarios pass |

- **`keeps another bin/claude` against over-stripping.** A shim that drops other
  entries holding a `claude` lets the stub run instead. Both the positive
  (`other` recorded `ran`) and the negative (no stub `argv`) red under C′, so
  the pair is not a bare negative. **Fixed:** the other `claude` now lives under
  `$sandbox/other tools/bin`. A kept entry with a space now reaches an
  assertion; before, the only spaced entries were the stripped shim ones.
- **The leading-empty-entry expectation.** It is exact string equality with
  `":$stubdir:$PATH"`, where `$PATH` is the suite's own, the same value the
  launch appended. I ran the suite with a runner PATH holding `::` mid-list and
  a trailing `:`. The scenario still passed, and the only failures were the
  three expected slice-3 reds. The empty entry resolves to `$launch_dir`, the
  consumer root, which holds no `claude`, so it cannot capture the lookup.
- **`path_head` scoping.** `make_consumer` sets `path_head=""` on every call,
  and every scenario starts with `make_consumer`, so nothing leaks between
  scenarios. The earlier scenarios keep the `$shim_dir:$stubdir` default.
- **Whitespace, `my consumer`.** `path_head` is expanded inside double quotes.
  The identity loop splits on `IFS=:` alone. The symlinked and `/./` spellings
  both carry the space, since `link` → `my consumer`. With the fix above, the
  kept `other tools/bin` does too.

## Issues Found

### Critical Issues

None.

### Major Issues

1. **The first scenario did not require `-ef`**
   - Location: `tests/dogfood-launcher-test.sh`,
     `the shim strips its own entry in any spelling`.
   - Problem: every spelling of the shim sat ahead of the stub, so a shim that
     strips `${entry%/}` passed. The runbook says "in any spelling", and the
     Interfaces say `-ef`.
   - Fix: add `$sandbox/link/plugin-dev/bin` and `$consumer/plugin-dev/./bin`
     behind the stub. Rewrite the comment to say why they go behind it.
   - **Status**: FIXED. The trailing-slash and lexical normalisers red. The
     `-ef` candidate passes.

2. **The "no shim entry left" assertion could pass vacuously**
   - Location: same scenario, the identity loop.
   - Problem: an empty or unsplit recorded PATH gives a count of 0.
   - Fix: count entries `-ef` the stub in the same loop and assert `"1"`:
     `the recorded PATH splits to the stub's entry`.
   - **Status**: FIXED. It reds against HEAD (the stub never ran) and passes for
     the `-ef` candidate.

### Minor Issues

1. **No kept entry carried whitespace**
   - Location: `the shim keeps another bin/claude`.
   - Note: `$sandbox/other/bin` → `$sandbox/other tools/bin`.
   - **Status**: FIXED.

## Fixes Applied

All in `tests/dogfood-launcher-test.sh`:

- strips-in-any-spelling scenario:
  - `ln -s "$consumer" "$sandbox/link"`;
  - `path_head` extended with the symlinked and `/./` spellings behind the stub;
  - the stub-entry count and its `assert_eq … "1"`;
  - the comment explains why the new entries go behind the stub.
- keeps-another-bin scenario: the other `claude` moved to
  `$sandbox/other tools/bin`.

`toolkit/bin/claude` is unchanged (`git diff --quiet` exits 0).

## Requirements Validation

| Requirement | Status | Evidence |
|---|---|---|
| D9 the shim strips its own entries by identity and execs the next claude | Covered for slice 3 | HEAD, both normalisers, C′ and D red; the `-ef` candidate passes |
| D4 / D8 | Not in slice 3 | slices 1 and 5 |

## Positive Observations

- The first test reds by a real loop that the watchdog bounds. A timeout-free
  suite on macOS depends on exactly that.
- `path_head` defaults to the old head, so no earlier scenario needed editing.

## Recommendations

- Not added: an entry in another directory whose `claude` is a *file* symlink to
  the shim. `-ef` strips it and a directory-identity strip would not. A shim
  reached that way derives `<root>` from `$0`'s directory, which is the wrong
  place, so the setup is unsupported on other grounds. Pinning file-level
  against directory-level identity would test a configuration the shim cannot
  serve.
