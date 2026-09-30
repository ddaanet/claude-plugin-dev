# Review: Item 1.3/2 code review — `session-start` matches any entry naming the copy

**Scope**: `session_start` and its comment block in toolkit/dogfood.sh, as of
the HEAD commit
(`Item 1.3/2 — session-start matches any entry naming the copy`). The tests were
read only for context, plus the three regression tests added below for this
review's fixes. **Date**: 2026-09-30 **Mode**: review + fix

## Summary

The GREEN splits the variable on `:` by parameter expansion and compares each
entry whole. An entry that is an existing directory is resolved with
`$(cd -- … && pwd -P)`, and any other entry has its trailing slashes stripped.
The split, the whole-entry compare and the exit status are sound. The resolution
branch had three defects:

- the capture strips a trailing newline from the resolved path;
- relative entries were resolved against the hook's cwd;
- a directory that cannot be entered was skipped rather than compared literally,
  and left a `cd` error on stderr.

All three are fixed by moving the branch onto `physical_path`, the file's
existing idiom, behind a stricter guard. Each fix has a new test that was red
against the committed code.

**Overall Assessment**: Ready

## Checks against the prompt's points

- **Exit status.** The loop's last body command is `[[ … ]] && exit 0`. When the
  last entry misses, the `while` compound returns 1, but errexit is ignored for
  a status that comes from the left side of `&&`. Probed on every warn path
  (unset, `:`, `/x:/y`, `/`, `///`, `-`, a sealed dir): rc 0 each time, and `jq`
  supplies the final status. `root="$(root_dir)"` can still stop the script
  non-zero, but that line predates this slice (1.3/1), so it is not a finding.
- **Unenterable directory.** Committed code printed
  `dogfood.sh: line 134: cd: …: Permission denied` and exited 0. On exit 0,
  Claude Code ignores stderr (plugin-craft:hook-authoring, output-channels), so
  no user sees it. The real problem is the contract: the Interfaces line says an
  entry that does not resolve is compared literally, but `|| continue` skipped
  it. Minor 2 fixes this.
- **Trailing newline.** This is the 1.2/4 class, and it is real (Major 1).
- **Relative entry.** A false silence (Major 2).
- **`/`, `///`, `-`.** Each warns with no stderr, before and after the fix.
  Under the old code, `cd -- -` meant `cd "$OLDPWD"`. `physical_path` passes an
  absolute operand, so `-` is never read as that.
- **Reuse `physical_path`.** Done. It fits the contract once it is confined to
  the existing-directory branch. Non-resolving entries stay literal, so every
  1.3/3 warn case is unaffected:
  - `<other>/dist/plugin` resolves to the other repo's copy;
  - `/x<root>/dist/plugin` does not exist, so it is compared literally;
  - `<root>/dist/plugin/skills` resolves to a longer path.

## Issues Found

### Critical Issues

None.

### Major Issues

1. **A resolved path's trailing newline is stripped, giving a false silence**
   - Location: toolkit/dogfood.sh, `session_start`,
     `entry="$(cd -- "$entry" && pwd -P)"`
   - Problem: `$(...)` strips every trailing newline from `pwd -P`'s output.
     Take an entry (say `$sandbox/nl`) that resolves to a real directory
     `<root>/dist/plugin<LF>`, a sibling of the copy. It came out as
     `<root>/dist/plugin`, and the hook went silent. Claude Code `realpath`s the
     entry to the sibling, so the session does not load the copy. This is the
     same class slice 1.2/4's review fixed in `physical_path`.
   - Fix: resolve with `physical_path "$entry" && printf x`, then strip the `x`,
     as `pre_tool` already does.
   - Test: `session-start keeps a resolved entry's trailing newline`. It was red
     against the committed code (stdout `''`, warning expected).
   - **Status**: FIXED

2. **A relative entry is resolved against the hook's cwd**
   - Location: toolkit/dogfood.sh, `session_start`, the `[[ -d "$entry" ]]`
     branch
   - Problem: Claude Code keeps only absolute entries. A relative one is dropped
     with `skipped …: a plugin folder here is an absolute local path` (memory
     `cc-plugin-dirs-env-var`). The hook resolved a relative entry from its cwd,
     which is usually the root. `dist/plugin` therefore silenced the warning in
     a session that loads nothing from it. Claude Code normally writes the
     variable back normalized, so this is mostly unreachable, but the hook
     should not report a load Claude Code refused.
   - Fix: only an entry matching `/*` is resolved. A relative entry goes to the
     literal branch, and a relative spelling can never equal the absolute copy.
   - Test: `session-start does not resolve a relative entry`. It sets
     `my consumer/dist/plugin`, run from `$sandbox`. It was red against the
     committed code (silent).
   - **Status**: FIXED

### Minor Issues

1. **Two resolution idioms in one file**
   - Location: toolkit/dogfood.sh, `session_start` next to `physical_path`
   - Note: `session_start` resolved with a logical `cd` followed by `pwd -P`.
     `physical_path` resolves each name with `cd -P` and an absolute operand.
     The logical `cd` also handles `..` lexically before resolving, while
     `[[ -d ]]` and the kernel handle it physically.
   - Fix: covered by the Major 1 change. The file now has one idiom. The `..`
     semantics therefore change from logical to physical, and no test pins that
     either way (see Recommendations).
   - **Status**: FIXED

2. **An unenterable directory is skipped, not compared literally, and leaves a
   `cd` error**
   - Location: toolkit/dogfood.sh, `session_start`, `|| continue`
   - Note: the Interfaces line says a non-resolving entry is compared literally.
     The committed code dropped such an entry and left the `cd` error on stderr.
     This follows `no-stderr-suppression`'s preferred order: guard the expected
     failure away, and do not redirect it.
   - Fix: the guard is now `[[ "$entry" == /* && -d "$entry" && -x "$entry" ]]`.
     An unenterable directory takes the literal branch. `|| continue` stays only
     for a residual race, where the directory changes between the test and the
     walk, so the script still exits 0.
   - Test: `session-start passes over a directory it cannot enter`. It sets
     `$sandbox/sealed:$root/dist/plugin` with `sealed` at mode 000. It was red
     against the committed code (stderr held the `cd` error). The mode is
     restored before the assertions so cleanup can remove the directory. Run as
     root, the mode blocks nothing and the test cannot red. The test comment
     says so.
   - **Status**: FIXED

3. **Comment block out of step with the fixes**
   - Location: toolkit/dogfood.sh, the comment above `session_start`
   - Note: it said "an entry that is an existing directory is resolved with pwd
     -P". It now says "absolute" and "can be entered", names `physical_path`,
     and explains the relative and unenterable cases. The rest of the block was
     checked against the code and is accurate: whole-entry compare, unset warns,
     payload not read, the channels, and `jq --arg`.
   - **Status**: FIXED

## Fixes Applied

- toolkit/dogfood.sh `session_start`: the resolution guard is now
  `/* && -d && -x`, and resolution goes through `physical_path` with the
  `printf x` newline shield.
- toolkit/dogfood.sh: the comment block above `session_start` is restated to
  match.
- tests/dogfood-test.sh: three scenarios added after the symlink test:
  - trailing newline kept (warns);
  - relative entry (warns);
  - sealed neighbour (silent, empty stderr).

  Each was shown red against the committed SUT before the fix: 3 failures, all
  `FAIL:` assertions, no harness error.

## Mutated-SUT run

The mutation replaced `[[ "$entry" == "$copy" ]] && exit 0` in place with
`[[ "$entry" == "$copy" && -z "$rest" ]] && exit 0`, so only the last entry can
silence. This is the "last entry only" GREEN that the test review guarded
against. Result: 1 failure,
`session-start is silent on one entry of several prints nothing on stdout`. The
other two slice tests stayed green. That is expected, because each has a single
entry, which is also the last. The inverse replacement restored the line, which
was confirmed present exactly once.

## Final state

- `bash tests/dogfood-test.sh`: all dogfood scenarios passed (foreground).
- `shellcheck toolkit/dogfood.sh tests/dogfood-test.sh`: clean.

## Requirements Validation

| Requirement | Status | Evidence |
|---|---|---|
| exit 0 always, stdin not read | Satisfied | every probed warn/silent path rc 0; stdin never read |
| silent when some entry equals `<root>/dist/plugin` after `pwd -P` | Satisfied | several / trailing slash / symlink tests; newline test |
| otherwise one object | Satisfied | warn tests, including the new newline and relative cases |
| non-resolving entry compared literally, trailing slash stripped | Satisfied | literal branch; the unenterable dir now takes it (Minor 2) |
| no-jq static object | Not in scope | 1.3/4 |

## Positive Observations

- Splitting by parameter expansion on a value with a sentinel `:` appended keeps
  entries holding spaces intact, and handles the empty and unset cases without
  special code.
- `[[ -d ]]` guards the `cd`, as `no-stderr-suppression` prefers, instead of
  redirecting its stderr. The fix only tightens that guard.
- The compare stays exact-string on both sides, so the prefix, suffix and
  substring GREENs that 1.3/3 targets stay excluded.

## Recommendations

- **`..` semantics are unpinned.** Resolution is now physical, which matches
  `[[ -d ]]`, `pre_tool` and `realpath(3)`. If Claude Code collapses `..`
  lexically when it writes the variable back, the hook never sees one. This is
  unverified against the bundle, and no test pins either reading.
- **A `~`-prefixed entry** is accepted and expanded by Claude Code. Here it is
  compared literally and warns, the same as before the fix. Claude Code's
  written-back value is expected to carry the expanded path, but that is
  unverified.
- **An entry with a trailing newline** (as spelled, not as resolved) now warns
  whenever a `plugin<LF>` sibling exists. Claude Code trims entries before
  loading, so it would load the copy. This is reachable only if the hook sees an
  untrimmed value, which normalization should prevent.
