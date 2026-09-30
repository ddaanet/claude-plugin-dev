# TDD audit follow-up: independent red proofs, attribution, symlink guard

**Scope**: tdd-audit.md V1, V2 and Critical recommendation 1, plus the "A
symlinked `dist/plugin`" finding and Recommendation in review-code.md. **Date**:
2026-10-01 **Mode**: review + fix

## Summary

Both tests that only a GREEN had proven now have independent mutation proofs,
made with mutations different from the GREEN's and the test review's. The
pre-tool test reds under three mutations, one per assertion. The launcher test
reds under a `.git`-walk root, but only because of its `git init` line (a
control run without that line stays green). A manifest-walk root, which is also
a plausible wrong implementation, passed the whole suite, so the fixture was
strengthened into a second viable consumer, and both mutants now red with the
wrong copy recorded. The runbook attribution is corrected line-neutrally. The
symlinked-`dist/plugin` guard is pinned by a new scenario, and three mutations
show that each of its assertions discriminates. `toolkit/dogfood.sh` and
`toolkit/bin/claude` are byte-identical to HEAD.

**Overall Assessment**: Ready

## Precommit, before any change

`just precommit` in the foreground: green on the first run, with no
intermittent. The last suite printed `all dogfood launcher scenarios passed`,
then `ok`.

## Method

Each mutation was one exact-string replacement made by a scratch helper
(`$TMPDIR/mut.py`) that refuses unless the old text matches exactly once. The
inverse replacement reverted it. After each revert:

- `git diff --quiet -- <file>` exited 0;
- a `grep -c` for the mutant text printed `0`.

The suite ran in place in the foreground (`bash tests/<suite>.sh`), and each
suite copies the SUT into its own sandbox fixture. The mutated `sync` therefore
never ran against this repo.

## Task A1: `pre-tool fails loudly on a payload jq cannot read`

The GREEN mutation (item-1-2-s5-green.md) was
`jq -j … 2>/dev/null && printf x)" || exit 0`, which silences stderr and
swallows the failure in one edit, and it redded both the exit and stderr
assertions together. The mutations below split that edit and add a third, so
each assertion gets a mutation of its own. All three edit line 98 of
`toolkit/dogfood.sh`, the `path="$(jq -j … && printf x)"` capture.

**M1: swallow the failure, keep jq's stderr.** Appended `|| exit 0`.

```text
FAIL: pre-tool fails loudly on a payload jq cannot read: exit code was 0
1 failure(s)
```

**M2: silence jq, keep the failure.** Inserted `2>/dev/null` before
`&& printf x`. errexit still ends the script non-zero.

```text
FAIL: pre-tool fails loudly on a payload jq cannot read shows jq's error: output did not contain 'jq: '
1 failure(s)
```

**M3: report the failure on stdout.** Appended
`|| { printf '%s\n' '{"systemMessage":"dogfood: unreadable payload"}'; exit 1; }`.
This is a plausible "loud" report that keeps the exit and jq's stderr.

```text
FAIL: pre-tool fails loudly on a payload jq cannot read prints nothing on stdout: expected '', got '{"systemMessage":"dogfood: unreadable payload"}'
1 failure(s)
```

In each case, `git diff --quiet -- toolkit/dogfood.sh` exited 0 after the
revert, and the mutant-text grep printed `0`. Green after the revert:
`all dogfood pre-tool scenarios passed`. The test was not changed.

## Task A2: `the shim exports the copy`, the `git init` discrimination

The GREEN report (item-2-1-s4-green.md) points at the test review's mutation, a
`git rev-parse --show-toplevel`-first hybrid run on a deleted scratch copy. I
used different mutations, applied in place to line 17 of `toolkit/bin/claude`,
the `root="$(cd -P -- "$here/../.." …)"` line.

**M-GIT: walk up from the launch directory to the nearest `.git`, falling back
to the shim's `../..`.**

```text
root="$(d="$PWD"; while [[ -n "$d" && ! -e "$d/.git" ]]; do d="${d%/*}"; done; if [[ -n "$d" ]]; then printf '%s' "$d"; else cd -P -- "$here/../.." && printf '%s' "$PWD"; fi && printf x)"
```

Against the suite as committed:

```text
FAIL: the shim exports the copy: expected '/tmp/claude-1000/tmp.wLz3GRyd3s/my consumer/dist/plugin', got '<stub did not record plugin_dirs>'
FAIL: session-start takes the copy the shim exported: expected '', got '{"systemMessage":"\u001b[0mdogfood: this session does not load …/my consumer/dist/plugin — …"}'
2 failure(s)
```

**Control:** the same mutant with only the `git init -q "$sandbox/elsewhere"`
line removed from the test printed `all dogfood launcher scenarios passed`. The
`git init` line is therefore what carries the discrimination. I restored the
line by the inverse replacement, and
`git diff --quiet -- tests/dogfood-launcher-test.sh` exited 0 before any
strengthening edit. The SUT revert was checked the same way.

**Gap found.** The committed fixture reds M-GIT only because the decoy root has
no manifest: sync refuses and the shim aborts before the exec. A root taken from
the nearest `.claude-plugin/plugin.json` above the launch directory (M-MAN, the
same walk keyed on the manifest) still falls back from a bare repo. Against the
committed test:

```text
all dogfood launcher scenarios passed
```

**Strengthening** (`tests/dogfood-launcher-test.sh`, the one scenario).
`$sandbox/elsewhere` is now a consumer that sync accepts:

- a git repo;
- `.claude-plugin/plugin.json` (`"name":"decoy"`);
- `.gitignore` with `/dist/plugin/`;
- `plugin-dev/dogfood.sh` vendored.

A root derived from the launch directory in any of these ways now syncs the
decoy and records its copy, instead of aborting on a refusal. A paired assertion
was added over the same fixture:
`the shim exports the copy: the launch directory's repo is not synced`
(`assert_absent "$sandbox/elsewhere/dist"`), which a correct shim satisfies and
every cwd-derived root breaks. The scenario comment now names the three
derivations it rules out. The existing assertion is unchanged.

Proof on the strengthened test. Each mutant was applied, run and reverted, with
`git diff --quiet -- toolkit/bin/claude` exiting 0 after each revert.

M-GIT:

```text
FAIL: the shim exports the copy: expected '/tmp/claude-1000/tmp.jBJSeeCcJ2/my consumer/dist/plugin', got '/tmp/claude-1000/tmp.jBJSeeCcJ2/elsewhere/dist/plugin'
FAIL: the shim exports the copy: the launch directory's repo is not synced: '/tmp/claude-1000/tmp.jBJSeeCcJ2/elsewhere/dist' exists
FAIL: session-start takes the copy the shim exported: expected '', got '{"systemMessage":"… does not load …/my consumer/dist/plugin — …"}'
3 failure(s)
```

M-MAN, which passed before the strengthening:

```text
FAIL: the shim exports the copy: expected '/tmp/claude-1000/tmp.i2zwWXXaDo/my consumer/dist/plugin', got '/tmp/claude-1000/tmp.i2zwWXXaDo/elsewhere/dist/plugin'
FAIL: the shim exports the copy: the launch directory's repo is not synced: '/tmp/claude-1000/tmp.i2zwWXXaDo/elsewhere/dist' exists
FAIL: session-start takes the copy the shim exported: expected '', got '{"systemMessage":"… does not load …/my consumer/dist/plugin — …"}'
3 failure(s)
```

Green against the unmutated shim, strengthened test:
`all dogfood launcher scenarios passed`. The strengthened scenario has had no
test-review dispatch beyond this one. Its reds are the two above, and the
`assert_absent` goes from green to red, a transition rather than a birth state.

## Task B: runbook attribution

`plans/2026-09-26-dist-copy-dogfood-launcher/runbook.md` line 172, in the Item
1.2 list entry 5, now reads
`` `pre-tool fails loudly on a payload jq cannot read` (in-session GREEN). ``.
It previously ended `(test review).`. The line grew from 73 to 78 bytes and
stayed one line. After `just format-docs`, `wc -l` is 399, unchanged and under
the 400 cap.

## Task C: a symlinked `dist/plugin` is refused and the root survives

New scenario in `tests/dogfood-sync-refusal-test.sh`, placed after
`a git failure stops sync before rsync`: the same exit-128 branch, reached by
real git. The fixture is `make_consumer`, then `mkdir dist` and
`ln -s .. dist/plugin` (the probed shape). The link comes after `commit_all`
because `/dist/plugin/` matches only directories and `add -A` would track it.

Probe before writing (sandbox, unmutated script): stderr
`fatal: pathspec 'dist/plugin/' is beyond a symbolic link`, rc 128, and `.git`
and the tracked files intact.

The scenario asserts:

1. the exit code is non-zero;
2. stdout is empty;
3. stderr contains `beyond a symbolic link`;
4. `.git/HEAD` is a regular file;
5. `git --git-dir="$consumer/.git" --work-tree="$consumer" diff-index --quiet HEAD --`
   passes, so no tracked file changed.

The explicit `--git-dir` stops git from finding a parent repo once `.git` is
gone. `diff-index` has no `--no-index` fallback. A first draft used
`git -C … diff --quiet HEAD`, which fell back to no-index mode under the mutant
and dumped git's usage text. That was fixed before the proofs below.

**C-M1: the git-error branch falls through.** Line 237 of `toolkit/dogfood.sh`,
`*) exit "$status" ;;`, became `*) ;;`. rsync then mirrors the root onto itself
inside the sandbox fixture.

```text
FAIL: a symlinked dist/plugin: exit code is 0
FAIL: a symlinked dist/plugin: the root's .git survives: '/tmp/claude-1000/tmp.7YRsRZd66Z/my consumer/.git/HEAD' is not a regular file
fatal: not a git repository: '/tmp/claude-1000/tmp.7YRsRZd66Z/my consumer/.git'
FAIL: a symlinked dist/plugin: the root's tracked files changed
3 failure(s)
```

The mutant deleted the fixture root's `.git`, which is the loss the scenario
exists to pin. Only this scenario redded.

**C-M2: silence the check.** Line 230 got `2>/dev/null` on `git check-ignore`.
This mutation isolates assertion 3, which C-M1 cannot red because git prints
before the branch.

```text
FAIL: a symlinked dist/plugin: git's diagnosis reaches stderr: output did not contain 'beyond a symbolic link'
1 failure(s)
```

**Probe, not a red: `check-ignore -q --no-index dist/plugin/`.** review-code.md
names `--no-index` as a change that might open the hole. On git 2.47.3 it does
not: git still refuses the pathspec beyond the link, and the suite stayed green.
The scenario would red the day a check stops going through a pathspec, which is
when review-code.md's explicit `-L` refusal becomes needed.

After each mutation, `git diff --quiet -- toolkit/dogfood.sh` exited 0 and the
mutant grep printed `0`. Green line:
`all dogfood sync refusal scenarios passed`. `toolkit/dogfood.sh` was not
changed. The `-L` refusal is left to my human partner.

Residual: assertion 5 reds under C-M1 only because `.git` is gone. No mutation
changed a tracked file while leaving `.git` in place, and rsync over the
identical tree has nothing to rewrite. It stands as a guard on the rest of the
root, and C-M1 is its evidence.

## Issues Found

### Critical Issues

None.

### Major Issues

1. **`the shim exports the copy` passed a manifest-walk root.**
   - Location: `tests/dogfood-launcher-test.sh`, the scenario's `elsewhere`
     fixture.
   - Problem: the decoy was a bare repo, so any launch-directory root that falls
     back when the decoy lacks a manifest passed the suite (M-MAN green).
   - Fix: made the decoy a viable consumer and paired an `assert_absent` on its
     `dist`.
   - **Status**: FIXED

2. **The exit-128 guard against a symlinked `dist/plugin` was unpinned.**
   - Location: `tests/dogfood-sync-refusal-test.sh`.
   - Problem: nothing in the suite reds if the git-error branch falls through,
     and that fall-through deletes the root's `.git`.
   - Fix: new scenario
     `a symlinked dist/plugin is refused and the root survives`.
   - **Status**: FIXED

### Minor Issues

1. **Runbook misattribution** (audit V1).
   - Location: runbook.md:172.
   - Fix: `(test review)` became `(in-session GREEN)`.
   - **Status**: FIXED

## Fixes Applied

- `tests/dogfood-launcher-test.sh`, `the shim exports the copy`: decoy consumer
  fixture, paired `assert_absent`, and a rewritten comment. 344 → 351 lines.
- `tests/dogfood-sync-refusal-test.sh`: new scenario. 221 → 244 lines.
- `plans/2026-09-26-dist-copy-dogfood-launcher/runbook.md:172`: attribution
  corrected. 399 → 399 lines.
- `tests/dogfood-pre-tool-test.sh`: unchanged, 384 lines.
- `toolkit/dogfood.sh`, `toolkit/bin/claude`: unchanged (`git diff --quiet`
  exits 0 on both).

## Final gate

`just format-docs`, then `just precommit` in the foreground: exit 0 on the first
run, with no intermittent. The checks that passed were `bash -n` and
`shellcheck` over the scripts and tests, and the checks below:

- the version-guard, check-version and release suites;
- `self-release.sh: ok`;
- the update-plugin-dev and install.sh suites;
- `dist tree ok (11 files, …)`;
- `docs ok (cap 400 lines, pointers resolve)`;
- `doc sync ok`;
- `citations ok`;
- the dogfood sync, sync refusal, pre-tool, session-start and launcher suites;
- the final `ok`.

After the gate, `git diff --quiet -- toolkit` exits 0. The tracked diff is the
runbook, `tests/dogfood-launcher-test.sh` and
`tests/dogfood-sync-refusal-test.sh`, plus this untracked report. Nothing was
committed.
