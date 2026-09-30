# Review: Item 2.2/2 test review — a re-run is a no-op

**Scope**: uncommitted diff to `tests/update-plugin-dev-test.sh` (the re-run
block at the end of the scenario
`install.sh: wires into an existing settings.json without replacing it`), and
the RED report `reports/item-2-2-s2-red.md`. `toolkit/install.sh` was touched
only by the temporary mutations below, each restored. **Date**: 2026-09-30
**Mode**: review + fix

## Summary

The slice adds a second `install.sh` run with no ref after the first install,
and checks exit 0, byte-identical `settings.json` (`cmp -s` against a copy made
just before), and the `already installed, nothing to do` report. The behaviour
already exists (slice 1's GREEN), so the RED report proves it by mutation. The
assertions discriminate. Two minor fixes were applied: the before-copy now sits
outside the consumer repo, and the labels now carry the slice name.

**Overall Assessment**: Ready

## Mechanical check: mutation proof reproduced

The RED report's mutation (`length > 0` -> `length > 99` in `add_hook`) was not
reused. I ran two mutations of my own, each an exact-string replacement that
occurs once in `toolkit/install.sh`, each restored by the inverse replacement:

1. **Presence never detected** — `select(.command == $cmd)]` ->
   `select(.command == $cmd + "x")]`. The re-run appends duplicates.

       FAIL: a re-run is a no-op: settings.json changed
       FAIL: a re-run is a no-op: report: output did not contain 'already installed, nothing to do'
       2 failure(s)

   Both slice assertions are red on their own assertion.

2. **The file is rewritten with identical bytes but reported as changed**:
   `if [ -f "$settings" ] && cmp -s "$settings" "$tmp"; then` ->
   `if false && cmp -s "$settings" "$tmp"; then`. The write always happens and
   `changed` always gets the settings line.

       FAIL: a re-run is a no-op: report: output did not contain 'already installed, nothing to do'
       1 failure(s)

   The report assertion catches this case on its own, and `cmp` correctly stays
   green because the bytes are identical. This answers the dispatch's question:
   a re-run that rewrites the file identically but still says "installed" does
   go red.

Restore verified after each mutation: `grep -cF '$cmd + "x"'` and
`grep -cF 'if false && cmp'` both 0, `git diff --stat toolkit/install.sh` empty,
and the suite green (`update-plugin-dev scenarios passed`).

## Wrong-reason hunting

- **Does the second run reach step 3?** Yes. `plugin-dev/` exists and no ref is
  given, so step 1 is skipped entirely, including the `git diff --quiet HEAD`
  dirty-tree check and `git subtree`. Step 2 finds the import line. Step 3 runs
  `add_hook` three times and the `cmp` gate. The message is printed from only
  one place, the end of the script, when `changed` is empty. Every earlier exit
  prints an error and exits 1, which `rc == 0` rules out. Mutation 1 changes
  only step 3 and reds the report, which proves the run reaches step 3.
- **Does `cmp` compare the right files?** Yes. The copy is taken after the first
  install and immediately before the re-run, from the same `$settings_json` path
  the re-run writes. It is not satisfied by the fixture's starting state: the
  starting state differs from the post-install state, and mutation 1 reds it.
- **Is the report assertion discriminating?** Yes.
  `already installed, nothing to do` and `installed.` are printed by mutually
  exclusive branches, and the needle has no BRE metacharacters. Mutation 2 shows
  it reds by itself.
- **Could the untracked before-copy in the consumer repo change `install.sh`'s
  path?** Not today: the only dirty-tree check (`git diff --quiet HEAD`) is
  inside step 1, which a re-run skips, and it ignores untracked files anyway.
  The scenario also ends straight after, and the next one calls `new_sandbox`.
  Still, it was an untracked file inside the tree under test, and it would
  couple the fixture to any future porcelain-style check. Moved it (Minor 1).
- **Exit-0 assertion**: this checks that the run itself succeeded, not the
  slice's behaviour. The RED report says so. It stays.

## Issues Found

### Critical Issues

None.

### Major Issues

None.

### Minor Issues

1. **Before-copy written into the consumer repo**
   - Location: tests/update-plugin-dev-test.sh, re-run block
     (`cp "$settings_json" "$consumer/settings.before"`)
   - Note: the copy was an untracked file inside the git tree that the run under
     test operates on. The re-run happened to be unaffected, but the fixture
     should not differ from the first run's tree for a reason unrelated to the
     slice. Moved to `$sandbox/settings.before`, which is outside the consumer
     and cleaned up with the sandbox, with a one-line comment giving the reason.
   - **Status**: FIXED

2. **Assertion labels did not carry the slice name**
   - Location: same block, the three assertion labels
   - Note: the runbook names the slice `a re-run is a no-op`, and slice 1's
     labels use their slice names verbatim. The new labels
     (`a second install exits 0`, `a re-run changed settings.json`,
     `a re-run reports nothing to do`) could not be traced back to the slice by
     grep. Relabelled to `a re-run is a no-op: exit code`,
     `a re-run is a no-op: settings.json changed`, and
     `a re-run is a no-op: report`.
   - **Status**: FIXED

## Fixes Applied

- tests/update-plugin-dev-test.sh, re-run block: before-copy moved from
  `$consumer/settings.before` to `$sandbox/settings.before`, with a comment
  giving the reason. The `cmp` operand is updated to match.
- tests/update-plugin-dev-test.sh, re-run block: the three labels are prefixed
  with the slice name `a re-run is a no-op`.

Net addition to the file is +1 line (the comment). The block is still 9 lines.

## Per-test result after fixes

- Unmutated SUT: suite green, `update-plugin-dev scenarios passed`.
  `shellcheck tests/update-plugin-dev-test.sh` is clean.
- Mutation 1: `settings.json changed` and `report` both red.
- Mutation 2: `report` red; `settings.json changed` green, as intended because
  the bytes are identical.

## Requirements Validation

| Requirement | Status | Evidence |
|-------------|--------|----------|
| Slice 2: second install leaves `settings.json` byte-identical (`cmp`) | Satisfied | `cmp -s "$sandbox/settings.before" "$settings_json"`; reds under mutation 1 |
| Slice 2: prints `already installed, nothing to do` | Satisfied | `assert_contains "$out" ...`; reds under mutations 1 and 2 |

## Positive Observations

- The re-run takes no ref, which matches the documented re-run form and skips
  step 1 cleanly without depending on the "ignoring ref" warning path.
- The RED report is honest that the exit-0 assertion is not discriminating.

## Recommendations

- Slice 4 builds on "slice 2's re-run". The before-copy is now at
  `$sandbox/settings.before`, so slice 4 can reuse that location for its own
  `cmp` rather than adding another file to the consumer.
