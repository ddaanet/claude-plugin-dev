# Item 1.1/6 test review

Verdict: two issues found in the RED diff, both fixed in
`tests/dogfood-test.sh`. The first two tests are still red on assertions against
the committed SUT. `toolkit/dogfood.sh` is unchanged (`git diff --quiet`
passes). Nothing staged or committed. `bash -n` and `shellcheck` are clean.
Suite: 431 lines, up from 416; the split decision still goes to the planner at
the end of Phase 1.

## Method

To test the tests against what slice 6 will become, I wrote a plausible GREEN in
scratch (`/tmp/claude/dogfood-build/s6/toolkit/candidate.sh`). It adds a
manifest check on `$root/.claude-plugin/plugin.json` and
`git -C "$root" check-ignore -q dist/plugin/` right after `root_dir`, each
printing one `dogfood:` line and exiting 1. The full suite is green against it.
I then mutated the candidate. The real SUT was touched only for check 1.

## Check 1: mechanical

- `refuses without a root manifest` and
  `refuses when dist/plugin is not ignored` both fail on their three assertions
  (exit code, stderr line, copy absent) against the committed SUT, as the RED
  report says.
- `a git failure stops sync before rsync`: I used a different mutation from
  RED's. In the real `toolkit/dogfood.sh` I replaced
  `git -C "$root" ls-files -z -o -i --exclude-standard --directory |` with
  `{ git -C "$root" ls-files -z -o -i --exclude-standard --directory || true; } |`,
  which swallows the git failure. The revised test goes red:

  ```
  === a git failure stops sync before rsync ===
  FAIL: a git failure: exit code is 0
  FAIL: a git failure: dist/ is not created: '…/my consumer/dist' exists
  ```

  I restored the file by the inverse exact-string replacement, and
  `git diff --quiet toolkit/dogfood.sh` succeeded. Unmutated, the test is green.

## Check 2: tests that pass for the wrong reason

### Fixed: the git-failure test goes vacuous once slice 6 lands

Removing `.git` makes the ignore check's own `git check-ignore` exit 128. That
check comes before `ls-files`, so it refuses before the ignore list is ever
built. The test's assertions (non-zero exit, no `dist/`) then hold whether or
not the `ls-files` failure is guarded. Proof: against the candidate with the
`|| true` mutation above, the original test printed
`all dogfood scenarios passed`.

The fix is a stub `git` placed first on PATH. It fails `ls-files` only, with
`git: stub failure` on stderr and exit 128, and passes every other call through
to the real git. The fixture keeps the manifest and the ignore rule, so the
failure lands after the refusal checks. A new assertion that stderr contains
`git: stub failure` proves the run actually reached `ls-files`, rather than
being stopped earlier by a refusal. Results against the candidate:

- As written: green.
- With `|| true`: red (exit 0, `dist` exists).
- With `mkdir` moved first: red.

This departs from the slice's wording (".git removed"). The wording's intent was
"a git failure stops sync before rsync", and after slice 6 `.git` removal can no
longer reach the code that intent names.

### Fixed: the not-ignored test's comment claimed coverage the test lacks

The comment said this test is where "the check must ask git about the directory
with its trailing slash". It is not: a check without the slash also refuses an
emptied `.gitignore`, so this test stays green under that mutation.

What does catch it is the first sync of every positive test (`/dist/plugin/`
ignored, no `dist/` yet). Against the candidate, with the slash dropped: 33
failures, starting with
`sync copies a tracked file exit code: expected '0', got '1'`. So the behaviour
the lead asked about is already pinned, and I rewrote the comment to say where.
The probe on git 2.47.3 agrees: with no directory, `check-ignore dist/plugin`
exits 1 and `check-ignore dist/plugin/` exits 0.

I also added a precondition to the same test. It fails if `dist/plugin/` is
still ignored after `.gitignore` is emptied. This machine has
`core.excludesFile = ~/.config/git/ignore`. It holds no `dist` pattern today,
but one would turn this test red with a misleading message. Under a
`GIT_CONFIG_GLOBAL` whose excludes file holds `dist/`, the guard reports
`not ignored: the fixture still ignores dist/plugin/`.

### Checked, no change needed

- **Manifest check on the cwd or on `CLAUDE_PROJECT_DIR`:** red across the
  positive tests. `run_dogfood` runs from `$sandbox` with `CLAUDE_PROJECT_DIR`
  at `$sandbox/elsewhere`, and neither holds a manifest.
- **Checks placed after `mkdir`:** red in both refusal tests
  (`the copy is not created`) and in the git-failure test.
- **The one-line stderr assertion:** `$(cat)` strips the trailing newline, so
  `*$'\n'*` catches a second line only. This is correct for the "one `dogfood:`
  line" contract.

### Residuals (not fixed)

- A check that greps `.gitignore` for `/dist/plugin/` instead of asking git
  would pass every test, because every positive fixture spells the rule exactly
  that way. The Interfaces line requires asking git. Closing this would need a
  positive test that ignores the copy some other way (for example `dist/` in
  `.git/info/exclude`). I judged that not worth the lines in an already over-cap
  suite; the lead may disagree.
- The manifest test asserts the relative `.claude-plugin/plugin.json` substring,
  not `<root>/…`, as the slice specifies. The wrong-root mutations are caught
  elsewhere, as noted above.
