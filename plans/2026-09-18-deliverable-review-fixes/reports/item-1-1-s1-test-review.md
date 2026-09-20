# Review: Item 1.1 slice 1 — RED-phase test review

**Scope**: `tests/release-test.sh`, the new
`=== pipefail-stripped release_tags failure refuses ===` scenario only, plus the
RED report `reports/item-1-1-s1-red.md`. **Date**: 2026-09-20 **Mode**: test
review + fix

## Summary

The slice-1 test is genuine evidence. Both of its assertions fail on assertion
mismatches against unchanged `toolkit/release.sh`, the failure is caused by the
defect M2 names (`release_tags`'s pipeline swallowing a failed
`git tag --list`), and the test passes under the GREEN fix — verified
empirically on a throwaway copy. One factual error in the new comment was found
and fixed; no assertion, fixture or stub change was needed.

**Overall Assessment**: Ready

## Mechanical first check

Re-run in the foreground:

```
cd /Users/david/code/claude-plugin-dev && bash tests/release-test.sh
```

Exit status 1. The only `FAIL:` lines in the whole run are the two the RED
report quotes, and they match it verbatim:

```
=== pipefail-stripped release_tags failure refuses ===
FAIL: pipefail-stripped release_tags failure refuses names release_preflight's die: output did not contain 'could not list this plugin's release tags'
  --- output ---
git: fatal: stub git failing tag --list
hint: origin already has release tags for this plugin — the newest is
      v1.2.3, missing from this clone. Run `git fetch --tags` to catch up,
      then run the same command again.
error: local release tags are missing — refusing to guess whether v1.2.3 was published
  --------------
FAIL: pipefail-stripped release_tags failure refuses did not take the lost-tags branch: output contained 'git fetch --tags'
  --- output ---
git: fatal: stub git failing tag --list
hint: origin already has release tags for this plugin — the newest is
      v1.2.3, missing from this clone. Run `git fetch --tags` to catch up,
      then run the same command again.
error: local release tags are missing — refusing to guess whether v1.2.3 was published
  --------------

2 failure(s)
```

Both are FAILED-on-assertion. Neither is an ERROR: the stub's own
`git: fatal: stub git failing tag --list` line proves the wrapper was reached
and the script ran to a real refusal, and there is no "command not found", no
bash syntax error and no missing-fixture noise anywhere in the output. No test
in this scenario PASSED vacuously — the one assertion that does pass
(`assert_eq "$rc" "1"`) is acknowledged in the RED report as passing
coincidentally, since the wrong branch also exits 1; it is not the assertion
carrying the proof.

The RED report's account is accurate as written.

## Wrong-reason hunting

Each checked item below was verified against the source, not inferred.

**The state of the world that fails this test.** A `release_tags` whose status
reaches `release_preflight` refuses at `release_preflight`'s `|| die`; one whose
status is absorbed by the pipe falls through to the lost-tags branch and emits
the `git fetch --tags` remedy. The fixture makes both branches reachable —
origin carries `v1.2.3` (`new_sandbox` pushes it), so the lost-tags branch has
real evidence to find rather than being an empty-fixture non-event. This is not
an "isolation fixture with nothing to leak": the decoy branch is live and the
test's job is to prove it is not taken.

**The stub fails `tag --list` only.** `$sandbox/git-wrapper/git` exits 1 for
`$1 = tag && $2 = --list` and `exec`s the resolved real binary for every other
invocation. Confirmed by consequence, not by reading alone: with the wrapper on
`PATH`, `common_preflight` and `origin_release_tags` (`git ls-remote`) both ran
to completion — the lost-tags hint naming `v1.2.3` could only be produced by a
successful `ls-remote` through the wrapper. The red is therefore not a
broken-stub artifact.

**The needle is `release_preflight`'s own `die`.** Read `toolkit/release.sh`:
inside `release_preflight`,
`release_tag_list=$(release_tags) || die "could not list this plugin's release tags — nothing was done"`.
That string occurs exactly once in the script and in no other symbol, so the
assertion cannot be satisfied by another path. It is also long enough not to be
a substring another line supplies.

**`git fetch --tags` is the lost-tags remedy and nothing else on this path.**
The script has four occurrences. One is in `release_preflight`'s lost-tags
branch (`Run \`git fetch --tags\` to catch
up`) — the one that appears in the RED output. Two are in `resume_preflight`'s hint ladder, unreachable in `patch` mode (`common_preflight;
if [ "$mode" = "release" ]; then release_preflight; …`). The fourth is prose
inside a comment and never printed. The negative assertion therefore
discriminates exactly the branch it claims to.

**The negative is paired with a positive.** `assert_not_contains` alone would
pass before the feature existed; it is paired with
`assert_contains "could not list this plugin's release tags"` over the same
fixture run, differing only in which branch the guard takes. Neither can be
satisfied by the other's state.

**The test is satisfiable by the GREEN fix.** Copied `toolkit/` and `tests/` to
a scratch directory, applied the runbook's capture-then-filter body
(`listing=$(git tag --list 'v*' --sort=-v:refname) || return 1`, then
`printf '%s\n' "$listing" | semver_tags`) there only, and ran the suite from the
copy:

```
=== pipefail-stripped release_tags failure refuses ===

all release scenarios passed
```

Exit 0. This rules out the class of wrong-reason red where the test fails for
something the GREEN implementation would not fix, and it also confirms the
assertions do not over-constrain the fix. The scratch copy was deleted;
`toolkit/release.sh` in the repo is untouched.

**The existing scenario is undisturbed.** The new block appends after the
`no-pipefail probe must not call gh` assertion and before the
`if (( failures > 0 ))` tally, opens with its own `new_sandbox "1.2.3"`, and
writes to a distinct copy name (`release-nopipefail-tags.sh`) and a distinct
variable (`nopipefail_tags`), so it shadows nothing the earlier scenario holds.
The earlier scenario printed no `FAIL:` line in the re-run, and neither did any
other scenario in the file — the rest of the suite behaves exactly as before.

**`PATH` is restored.** `run_in` runs under `set +e` and always returns, so
`export PATH="$saved_path"` is reached whatever the fixture does. No later
scenario exists, but the restore is correct regardless.

**Whitespace safety.** Every path the new shell touches is quoted:
`mkdir -p "$git_wrapper_dir"`, `chmod +x "$git_wrapper_dir/git"`,
`"$git_wrapper_dir:$PATH"`, `> "$nopipefail_tags"`. The emitted stub quotes both
`"$real_git"` and `"$@"`, so a git path or an argument containing spaces is
handled. Nothing splits on whitespace. The one residual — a git path containing
a quote, backslash or `$` would break the interpolated heredoc — is now stated
in the comment rather than left implied.

`shellcheck tests/release-test.sh` and `bash -n tests/release-test.sh` are both
clean.

## Issues Found

### Critical Issues

None.

### Major Issues

None.

### Minor Issues

1. **The new comment's ordering claim is false**
   - Location: `tests/release-test.sh`, the
     `=== pipefail-stripped release_tags failure refuses ===` comment block
   - Problem: it justified the delegating stub with "since release_preflight is
     the very first thing `patch` runs and nothing before it calls `git tag`".
     `release.sh`'s dispatch runs `common_preflight` first (`common_preflight` /
     `if [ "$mode" = "release" ]; then release_preflight`), and
     `common_preflight` makes git calls of its own. The conclusion survives —
     `release_tags` holds the script's only `git tag --list` — but the stated
     reason does not, and a comment that misdescribes the control flow is the
     kind that gets trusted later.
   - Fix: restate the justification on the true ground (only-occurrence, not
     first-thing-run), and record the two residuals the stub carries: the
     positional `$1`/`$2` match, and the interpolated `$real_git`.
   - **Status**: FIXED

## Fixes Applied

- `tests/release-test.sh`, comment above the
  `=== pipefail-stripped release_tags failure refuses ===` scenario — replaced
  the false "release_preflight is the very first thing `patch` runs"
  justification with the accurate one (`common_preflight` runs ahead and makes
  its own git calls; `release_tags` holds the script's only `git tag --list`),
  and stated the stub's two residual bounds: it matches `tag --list`
  positionally, which covers every form the script actually uses, and
  `$real_git` is interpolated, so a git path holding a quote, backslash or `$`
  would break the stub while a space is handled.

No assertion, needle, fixture or stub behaviour was changed. Re-run after the
fix reproduces the same two assertion failures, verbatim, and nothing else in
the suite fails.

## Requirements Validation

| Requirement | Status | Evidence |
|-------------|--------|----------|
| M2 (slice 1: with `pipefail` stripped and `git tag --list` failing, the release refuses with `release_preflight`'s `die` and does not take the lost-tags branch) | Satisfied by the test | `assert_contains "could not list this plugin's release tags"` pins the refusal to `release_preflight`'s own `die`; `assert_not_contains "git fetch --tags"` pins the lost-tags branch as not taken; both red today and green under the capture-then-filter fix |

**Gaps:** none for slice 1. Slice 2's `publishes nothing` test is deliberately
absent and out of scope.

## Positive Observations

- The stripped-copy idiom is reused rather than reinvented, and the copy gets
  its own filename and variable, so the two scenarios in the harness cannot
  interfere.
- `grep -qx 'set -eu'` guards the `sed` rewrite, so a future rename of the `set`
  line fails loudly instead of silently testing an unstripped copy.
- The delegating wrapper is the right shape: a blanket-failing `git` stub would
  have produced a red that says nothing about `release_tags`.
- The RED report is honest about `assert_eq "$rc" "1"` passing coincidentally,
  and says why the content assertions are the ones carrying the proof. That is
  exactly the distinction a RED report exists to record.

## Recommendations

None blocking. The GREEN dispatch should find these two assertions flip and the
rest of the suite unchanged; the scratch-copy run above already demonstrates
that outcome for the runbook's prescribed body.
