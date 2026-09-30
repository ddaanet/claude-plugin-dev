# Review: Item 2.1 slice 3 — code review (post-GREEN)

**Scope**: `toolkit/bin/claude` as changed by commit 25a5401 (`Item 2.1/3`):
`path_without`'s identity check, the call site passing `${BASH_SOURCE[0]}`, and
the header and function comments. Tests are OUT (not edited). **Date**:
2026-09-30 **Mode**: review + fix

## Summary

The identity check is correct. It strips every spelling of the shim's entry,
keeps every other entry byte for byte, and holds up against every probe below.
One fix: the function comment's over-long line is reflowed to 80 columns. The
empty-entry choice has no test behind it. Mutating `${entry:-.}` to `$entry`
leaves the suite green, although the mutant loops until killed when launched
from `plugin-dev/bin` with an empty PATH entry. That is a test gap, and tests
are out of scope here, so it goes to the orchestrator (Recommendations).

**Overall Assessment**: Ready

## Probes

Run on scratch fixtures in `$TMPDIR` built like the suite's `make_consumer`
(consumer path with a space, stub `claude` recording its PATH), under a 10 s
`timeout`. The current SUT passed each probe:

| Probe | Result |
|---|---|
| Shim invoked as `plugin-dev/bin/claude` from the root (relative `${BASH_SOURCE[0]}`) | rc 0, stub ran, shim entry gone |
| Relative PATH entry `plugin-dev/bin` | rc 0, stripped |
| cwd = `plugin-dev/bin`, leading empty entry, launched by bash `exec` | rc 0, empty entry dropped (it *is* the shim), stub ran |
| Same, launched by `env claude` (glibc execvp passes bare `claude`, so `BASH_SOURCE[0]` = `claude`) | rc 0, dropped |
| cwd = `plugin-dev/bin`, `.` entry | rc 0, dropped |
| `/nonexistent` and a mode-000 directory ahead of the stub | rc 0, both kept as spelled (`-ef` false) |
| Directory holding a file symlink `claude` → shim, behind the stub | stripped (`-ef` follows the link) |
| Entry containing a newline | kept intact, stub ran |

Reasoning behind the table:

- **Relative `${BASH_SOURCE[0]}`.** `main` never changes directory: the `cd -P`
  runs inside a command substitution, and `dogfood.sh` is a child process. A
  relative `$1`, a relative entry and the final `exec claude` therefore all
  resolve against the same launch cwd.
- **Empty entry.** Testing it as `./claude` is the only non-looping choice when
  cwd is the shim's directory. Dropping it there removes "." from the PATH that
  `claude` passes down. That is unavoidable, and the comment says so. Anywhere
  else the entry is kept in place.
- **Missing or unsearchable entries.** `stat` fails, so `-ef` is false and the
  entry is kept. The exec's own lookup skips it too, so keeping it costs nothing
  and preserves PATH as spelled.
- **Symlinked `claude` in another directory.** Stripping it is right, because
  keeping it would exec the shim again. A shim *launched* through such a link
  derives `<root>` from the link's directory, which is unsupported for other
  reasons (see the test review's Recommendations).
- **Whitespace and newlines.** Splitting uses only `${rest%%:*}` and
  `${rest#*:}`, never `IFS`. `[[ … -ef … ]]` does no word splitting or globbing.
  The result is captured with the `printf x` sentinel, so a trailing newline
  survives. A trailing empty entry survives the rebuild too (`a:` → `:a:` →
  `a:`).
- **bash 3.2 and BSD.** `[[ -ef ]]` is a bash builtin (`test.c`'s `same_file`:
  `stat` on both operands, then compares dev and inode). It is present in 3.2
  and never calls BSD `test`. Parameter expansions `%%` and `#`, `local`, and
  `[[ ]]` are all 3.2-safe. This is reasoned from source: no bash 3.2 binary was
  run.
- **`set -e`.** `[[ … ]] && continue` is an AND list, so a false test does not
  trip errexit. The function returns `printf`'s status.
- **Header comment.** Still true: the shim syncs, execs the next claude with
  argv unchanged, drops every entry whose claude is the shim, exports
  `CLAUDE_CODE_PLUGIN_DIRS`, unsets CDPATH, and finds `<root>` from its own
  location.

## Mutated-SUT run

- **Mutation**, one exact-string replacement in `path_without`:
  `[[ "${entry:-.}/claude" -ef "$1" ]]` → `[[ "$entry/claude" -ef "$1" ]]`. This
  is the plausible-but-wrong version of the empty-entry choice: an empty entry
  is tested as `/claude`, so it is always kept.
- **Suite:** `bash tests/dogfood-launcher-test.sh` (foreground) stayed
  **green**. All 8 scenarios passed and **none redded**.
- **Probe under the mutant:** cwd = `plugin-dev/bin` with a leading empty entry
  ran into the 10 s `timeout` (rc 124) for both the bash-`exec` and `env`
  launches, and the stub never ran. The suite detects that the empty-entry
  handling is missing only where it breaks leading-empty preservation. It does
  not detect this wrong choice.
- **Restore**, by the inverse exact replacement:
  - `grep -c -F '[[ "${entry:-.}/claude" -ef "$1" ]]'` printed 1;
  - `grep -c -F '"$entry/claude"'` printed 0;
  - `git diff --stat -- toolkit/bin/claude` was empty.

## Issues Found

### Critical Issues

None.

### Major Issues

None.

### Minor Issues

1. **Over-long, unwrapped comment line**
   - Location: `toolkit/bin/claude`, the comment above `path_without`.
   - Note: the GREEN edit spliced the new empty-entry sentence into the old one,
     which left a 118-column line.
   - **Status**: FIXED. Reflowed to 80 columns with no word changed.

2. **The empty-entry choice (`${entry:-.}`) is untested**
   - Location: `tests/dogfood-launcher-test.sh`. The SUT is correct.
   - Note: see the mutated-SUT run above. The mutant loops when claude is
     launched from `plugin-dev/bin` with an empty PATH entry (a `.` entry is
     unaffected), and the suite stays green.
   - **Status**: OUT-OF-SCOPE. This dispatch covers the implementation only, and
     tests are never edited in code review. See Recommendations.

## Fixes Applied

- `toolkit/bin/claude`, the `path_without` comment: reflowed so that no line
  exceeds 80 columns. The wording is unchanged.

Post-fix checks:

- `shellcheck toolkit/bin/claude` clean;
- `bash -n` ok;
- no line over 80 columns;
- `bash tests/dogfood-launcher-test.sh` green, all 8 scenarios passed.

## Requirements Validation

| Requirement | Status | Evidence |
|---|---|---|
| D9 chaining: drop an entry when its `claude` is the shim (`-ef`), not by name; exec the next claude with argv unchanged | Satisfied | `path_without` identity test; `exec claude "$@"`; probes above |
| D4, D8 | Not in slice 3 | earlier and later slices |
| Slice 6 (exit 127, `dogfood: no other claude on PATH`), slices 4–5 | Not implemented, correctly | out of scope |

## Positive Observations

- Passing `${BASH_SOURCE[0]}` rather than `$here` makes the check file identity,
  not directory identity, so it matches the Interfaces text exactly.
- The one-line change keeps the newline-safe capture and the colon-prefix
  rebuild untouched.
- Testing the empty entry as `./claude` rather than `/claude` is the correct and
  non-obvious call, and the comment gives the reason.

## Recommendations

- **Test to add (for the orchestrator's next test dispatch, probably slice 4,
  subdirectory launch):**
  - Launch from `$consumer/plugin-dev/bin` with
    `path_head=":$shim_dir:$stubdir"`.
  - Assert that the stub ran and that its recorded PATH has no leading empty
    entry.
  - Under the `"$entry/claude"` mutant this reds as a watchdog kill.
  - It also pins the one case where dropping an empty entry is required,
    complementing `keeps the rest of PATH as spelled`, which pins keeping one.
- No REFACTOR-NEEDED.
