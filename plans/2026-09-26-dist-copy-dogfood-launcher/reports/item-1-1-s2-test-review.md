# Item 1.1/2 test review

Scope: the uncommitted diff to `tests/dogfood-test.sh` (the two deletion tests)
and `reports/item-1-1-s2-red.md`. Verdict: **both tests discriminate; one minor
fix applied; one unpinned SUT behaviour flagged for the lead.**

## Check 1 — mutation reproduction

Baseline: SUT clean (`git diff --quiet toolkit/dogfood.sh`), suite green.

Mutations are exact-string replacements applied and inverted by
`/tmp/claude/dogfood-build/review/mut.py` (asserts exactly one occurrence each
way). After every restore, `git diff --quiet toolkit/dogfood.sh` passed. None
reuses the RED report's `--files-from` mutation.

| Mutation | Change to `sync_copy` | Result |
|---|---|---|
| m1 | `rsync -a --delete --delete-excluded` → `rsync -a` | A red, B red (absence only) |
| m2 | rsync step → `rm -rf` the copy + `git checkout-index -a -f --prefix=…/dist/plugin/` (copies the index, not the worktree) | **B red only**, A green |
| m3 | rsync step → `rm -rf` + `git ls-files -z \| xargs -0 cp --parents` | **B red only** (exit code, stderr), A green |
| m0 | drop `--delete` alone | survives (equivalent mutation, see below) |
| m4 | drop `--delete-excluded` alone | survives (unpinned, see Findings) |

Failing assertions, verbatim:

- m1 (for `a committed deletion propagates`):
  `FAIL: a committed deletion propagates: '…/my consumer/dist/plugin/skills/demo/extra.md' exists`
  plus
  `FAIL: a tracked file deleted in the worktree: the copy lacks it: '…/extra.md' exists`.
  2 failures.
- m2 (for `a tracked file deleted in the worktree does not fail sync`, absence):
  `FAIL: a tracked file deleted in the worktree: the copy lacks it: '…/extra.md' exists`.
  1 failure. A stays green, so the two tests are not redundant: B alone pins
  "the worktree, not the index, is the source".
- m3 (same test, exit code and stderr):
  `FAIL: a tracked file deleted in the worktree exit code: expected '0', got '123'`
  and
  `FAIL: a tracked file deleted in the worktree prints nothing on stderr: expected '', got 'cp: cannot stat 'skills/demo/extra.md': No such file or directory'`.
  2 failures.

Each named test reds on its own assertions, no other test reds under m1–m3, and
the red is never a setup error. After restore: `all dogfood scenarios passed`.

m0 survives because `--delete-excluded` implies `--delete` (rsync 3.5.0,
confirmed by the run). This is an equivalent mutation, not a test gap. The
explicit `--delete` in `toolkit/dogfood.sh` is redundant but harmless. SUT out
of scope, not touched.

## Check 2 — wrong-reason hunt

- **Vacuous absence:** not present. Both tests assert the file is present in the
  copy after the first sync, at the exact path later asserted absent.
- **Whole-copy wipe passing the absence:** guarded. The sibling `SKILL.md` in
  the same directory must survive, so a directory-level or full-copy removal
  reds.
- **B's fixture state:** guarded. After `rm`, B checks `git ls-files` still
  lists the file, so a fixture that accidentally unstaged it cannot turn B into
  a copy of A. m2 proves the index/worktree split is exercised.
- **A's `git rm`:** it removes both index and worktree entries. If it removed
  only the index, the file would stay as an untracked source file and A would
  red rather than pass vacuously. No guard needed.
- **stderr in B:** the fixture lives under `mktemp -d`, away from the sandbox's
  phantom dotfiles, so `assert_eq "$err" ""` cannot pick up a
  `skipping non-regular file` warning.
- **Minor asymmetry, fixed:** B did not assert the first sync's exit code, while
  A does. Added
  `assert_eq "$rc" "0" "a tracked file deleted in the worktree: first sync exit code"`.

## Check 3 — after the fix

`bash -n` and `shellcheck tests/dogfood-test.sh` are clean, the SUT is
unmodified, and the suite prints `all dogfood scenarios passed`. Only
`tests/dogfood-test.sh` is modified. Nothing staged or committed.

## Findings for the lead (not fixed: outside this slice's named tests)

- **`--delete-excluded` is unpinned (m4 survives the whole suite).** Outline
  decision 2 names the flag, and the SUT's comment says "a path that stops being
  source leaves the copy". But no test covers a file that is copied and then
  *becomes ignored* while it stays in the worktree. Under m4 it would linger in
  the copy forever. A candidate third deletion test:
  1. sync with a tracked or untracked `skills/demo/extra.md`;
  2. append `skills/demo/extra.md` to `.gitignore` (untrack it if it was
     tracked) and commit;
  3. sync again, then assert that the file is absent from the copy and
     `SKILL.md` stays.

  This needs a runbook decision (a slice 2 addition or a new slice), so it is
  not added here.

## Addition — `a file that becomes ignored leaves the copy`

Added at the lead's decision, which closes the m4 finding above. It sits after
the worktree-deletion test in `tests/dogfood-test.sh`. The test:

1. Makes a tracked `skills/demo/extra.md` and syncs. It asserts exit 0 and that
   the file is in the copy.
2. Runs `git rm --cached` on it, appends `/skills/demo/extra.md` to `.gitignore`
   and commits. Guards then assert the file is still a regular file in the
   worktree and that `git check-ignore -q` reports it ignored. So the only way
   out of the source set is the ignore list, never a worktree deletion that
   `--delete` alone would handle.
3. Syncs again. It asserts exit 0, the file is absent from the copy, and the
   sibling `SKILL.md` stays.

`bash -n` and `shellcheck` are clean. With the SUT clean, the suite prints
`all dogfood scenarios passed`.

Mutation proof (m4, `rsync -a --delete --delete-excluded` → `rsync -a --delete`,
applied and inverted by `/tmp/claude/dogfood-build/review/mut.py`):

- Suite exit 1, one failure, on the new test's own assertion:
  `FAIL: a file that becomes ignored leaves the copy: '…/my consumer/dist/plugin/skills/demo/extra.md' exists`
  (its first-sync, guard, exit-code and sibling assertions all passed).
- Restore by the inverse replacement: `git diff --quiet toolkit/dogfood.sh`
  passes, and the suite prints `all dogfood scenarios passed`.

m4 no longer survives. Only `tests/dogfood-test.sh` is modified; nothing staged
or committed.
