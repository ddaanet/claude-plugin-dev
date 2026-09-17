# Item 1.3, slice 2 — test review

Verdict: **the scenario is sound and discriminating.** One assertion added
(wrong-reason hardening), two comment blocks added recording measurements the
scenario's correctness rests on. No existing scenario touched.
`toolkit/release.sh` is byte-identical to `4d24126`.

One factual correction to the RED report, measured: under mutation 2 (full
removal) **17 of slice 1's 18 assertions fail, not 18.** The survivor is
`diverged-push-route (pushurl) names the value`, and why it survives is the
substance of §4 below.

## 1. Mutation re-runs

`toolkit/release.sh` backed up to `/tmp/claude-1000/s2rev/release.sh.orig`
before any probe; `sha256sum`
`cd91ac53725cac7541062792364679a3ca387e3580bf042ccccdf3815e4a0b36`, matching the
RED report's recorded hash. Restored with `cp` after each mutation and checked
with `diff` (not just the hash) plus `git diff --stat -- toolkit/release.sh`.

Baseline, unmodified: `TMPDIR=/tmp/claude-1000 bash tests/release-test.sh` →
exit 0, 50 scenario headers, `all release scenarios passed`. ~39s per run.

### Mutation 1 — move the loop `common_preflight` → `release_preflight`

Applied exactly as the RED report describes: the comment block and the
`local push_key push_values push_value` / `for … done` block removed from
`common_preflight`, the loop (without the comment) re-inserted as the first
statement of `release_preflight` after its own `local` line. `diff` against the
backup shows only that move — nothing else in the file changes.

Result: exit 1, **exactly 4 FAIL lines, all in the new scenario** (pre-edit);
slice 1's three release-mode settings, 18 assertions, all green. Re-run after my
edit: **5 FAIL lines**, the four plus the new `names the refusal`. Confirms the
added assertion is not decorative — it fails under the slice's own target
mutation.

### Mutation 2 — delete the loop entirely

Result: exit 1, **21 FAIL lines**: all 4 of the new scenario, plus 17 of slice
1's 18. The RED report says "all 18"; the one that passes is

```
diverged-push-route (pushurl) names the value
```

Cause in §4.

### Mutation 3 (mine) — whitespace

`while IFS= read -r push_value; do … done <<<"$push_values"` replaced with
`for push_value in $push_values; do … done` — the classic split-on-whitespace
defect, and the one the surrounding comment in `release.sh` claims the
one-value-per-line printing exists to prevent.

Result: exit 1, **exactly 2 FAIL lines**, both `names the value` —
`diverged-push-route (pushurl)` and `resume diverged-push-route`. §7.

## 2. Is the fixture's "healthy" claim true? — not vacuous

Verified by experiment rather than by inheriting the neighbouring scenario's
claim. Same fixture, **without** the diverged route, `--resume`:

```
resume rc=0
GH_LOG=[release view v1.2.4]
out: branch main: already pushed / github tag v1.2.4: already pushed /
     github release v1.2.4: already created / marketplace: already at 1.2.4 /
     release v1.2.4 is already complete (nothing to do)
```

So `--resume` on this fixture does call `gh` when it is allowed to get that far.
`$GH_LOG` empty in the new scenario is therefore caused by the refusal, not by
resume having nothing to do. The comment's argument holds as written.

The refusal's own output, captured verbatim from the scenario's fixture:

```
hint: remote.origin.pushurl is set to:
        /tmp/claude-1000/tmp.5YvJNfv1Ch/push-target repo.git
      unset it (git config --unset-all remote.origin.pushurl) or point it at
      origin, then run the same command again.
error: push route diverges from origin: remote.origin.pushurl is set
```

## 3. The setup assertion — belongs, and is load-bearing

`assert_eq "$rc" "0" "resume-push-route setup release exit code"` is the only
thing pinning the fixture the scenario's comment claims. Measured, not reasoned:
a sandbox whose setup release dies at `gh release create` (stub patched to fail)
gives setup `rc=1`, and the resumed run still produces

```
resume rc=1 / names-the-setting PASS / names-the-value PASS / GH_LOG empty
```

— all four behaviour assertions pass on a fixture that is not a completed
release at all. That is because the push-route check is the first thing
`common_preflight` does after the clean-tree and branch checks, so *any* fixture
with `pushurl` set produces that output. Without the setup assertion the
scenario would silently degrade into testing a different fixture.

Should it abort more loudly instead? No. `run_in` deliberately absorbs the
status, so `set -e` cannot fire; promoting it to a hard `exit 1` would kill the
remaining scenarios and lose the rest of the run's information. A `FAIL` line
whose label literally contains `setup` is comprehensible — a later change
breaking the setup prints `FAIL: resume-push-route setup release exit code`
first, above the consequential failures. The existing "resume: no-op on a
healthy repo" scenario carries the identical assertion, so this also matches the
suite's idiom.

Recorded in a comment beside the assertion, with the probe result, so the next
reader does not have to re-derive why a setup line is asserted.

## 4. Wrong-reason hunting — one real contamination, fixed

`$other` is a filesystem path, and
**a successful `git push` through a `pushurl` echoes `To <path>` onto stderr**,
which `run_in` folds into `$out`. Measured directly:

```
To /tmp/claude-1000/tmp.6jFk4ZUMgL/push-target repo.git
 * [new branch]      main -> main
To /tmp/claude-1000/tmp.6jFk4ZUMgL/push-target repo.git
 * [new tag]         v1.2.3 -> v1.2.3
```

So `assert_contains "$out" "$other"` can be satisfied by the very push the check
exists to prevent. That is not hypothetical: it is exactly why slice 1's
`diverged-push-route (pushurl) names the value` survives mutation 2 — the
release succeeded, pushed to the wrong repo, and git's own output supplied the
needle. Slice 1's review made the needle for `pushRemote`/`pushDefault`
(`pushtarget`) a token no English refusal could contain; the `pushurl` needle is
the one case where the *toolchain*, not the refusal, can emit it.

Could all four assertions pass with the check absent? Not in this fixture:
nothing but the refusal prints `remote.origin.pushurl`, so "names the setting"
still anchors it, and any un-refused resume that reaches `push_tag` also reaches
`create_github_release` and dirties `$GH_LOG`. The scenario is therefore not
vacuous today. But the anchor is a single string that a future resume-specific
guard could plausibly also emit, and the value assertion would not notice.

**Fix applied** — a fifth assertion pinning the refusal's own reason:

```sh
assert_contains "$out" "push route diverges from origin" "resume diverged-push-route names the refusal"
```

It fails under mutation 1 (the un-refused resume output contains no such
string), so it discriminates on its own, and it closes the "refused for some
other reason that happens to name the key" path.

Slice 1's `pushurl` value assertion has the same contamination and is
**out of scope here** (existing scenario, already committed). Flagging it for
the orchestrator: it is not urgent — slice 1's `created no v1.2.4 tag` and
`marketplace untouched` assertions catch the un-refused release — but the RED
report's "all 18 red" claim should not be carried forward as fact.

Other candidates probed and cleared: the refusal is not `resume_preflight`'s
no-tag guard (that fixture has `v1.2.4`, and its message is different and absent
from `$out`); it is not the clean-tree or branch guard (`$out` shows the
push-route `die` verbatim).

## 5. Nothing pins that the two modes share one refusal

Correct — and nothing would notice. A future edit that duplicated the loop into
`release_preflight` and `resume_preflight` instead of keeping it in
`common_preflight` passes both slice 1 and slice 2 unchanged, and the two copies
could then drift in wording, in key order, or in which of the three settings
each checks.

Does it matter? Mildly, and it is not fixable at this layer. "The check lives in
one function" is a structural property; a black-box end-to-end suite can only
observe behaviour, and duplicated-but-still-correct behaviour is not a defect a
test should fail. The contract the runbook states — refusal in both modes,
before any side effect — stays pinned under duplication. What is lost is the
single-source-of-truth guarantee on the message, and the suite asserts only
substrings of it (`remote.origin.pushurl`, the value, and now
`push route diverges from origin`), never the recovery line
(`unset it (git config --unset-all …)`), in either mode. So drift in the
recovery advice is invisible in both slices equally.

Deliberately not built: asserting the recovery line here would pin it in resume
mode only, which is worse than pinning it nowhere — it would read as a message
contract that release mode does not honour. If the message is worth pinning it
should be pinned in both, which is a slice-1 change and out of scope.

## 6. Item 1.3 completeness

Contract: `common_preflight` refuses a diverged push route, before any side
effect, in both modes, for all three settings.

Covered: release mode × `pushurl`/`pushRemote`/`pushDefault` (exit 1, key,
value, no `v1.2.4` tag, no `gh`, marketplace untouched); resume mode × `pushurl`
(exit 1, key, value, refusal reason, no `gh`).

Not pinned by the two slices together:

1. **Resume mode for `pushRemote` and `pushDefault`.** Only `pushurl` is
   exercised through `--resume`. A regression that mode-scoped a single key
   (rather than moving the whole loop) would go unseen. Low risk — the loop is
   one body over three keys — and the runbook specified `pushurl` singular, so
   this is a deliberate gap, not an oversight.
2. **"Before any side effect" in resume mode is asserted only through
   `$GH_LOG`.** Slice 1 additionally pins "no `v1.2.4` tag" and "marketplace
   untouched"; slice 2 pins neither, and nothing checks the push-target bare
   repo received nothing. I measured it — after the refusal the push-target has
   0 refs — but did **not** add the assertion: it cannot fail under any mutation
   reachable from this fixture, because the fixture's release is already
   complete, so `push_branch`/`push_tag` probe `origin` (fetch URL, not
   redirected by `pushurl`), see everything already pushed, and return without
   pushing. A non-discriminating assertion here would be decoration. Closing
   this properly needs a *resume-with-work* fixture (a release that stopped
   after the tag) plus the diverged route, asserting the push-target stays
   empty. That is the strongest missing coverage for this item and is beyond
   slice 2's stated shape.
3. **Ordering within `common_preflight`.** Moving the loop below the
   `MARKETPLACE_DIR` block would pass both slices. Harmless — neither is a side
   effect — but unpinned.
4. **Non-`main` default branch.** `branch.$branch.pushRemote` is only exercised
   with `branch = main`; the `$branch` interpolation the comment calls
   load-bearing is not tested on a `master`/`trunk` fixture in either mode. Out
   of the runbook's scope for Item 1.3.

Nothing here blocks Item 1.3 being called complete against its stated contract.

## 7. Whitespace — genuinely exercised

Not a nit and not judged by reading. Mutation 3 replaced the `while IFS= read`
loop with `for push_value in $push_values`, and the suite went red with
**exactly two** failures, both `names the value`:

```
FAIL: diverged-push-route (pushurl) names the value: output did not contain '/tmp/claude-1000/tmp.QHTSNUGvav/push-target repo.git'
FAIL: resume diverged-push-route names the value: output did not contain '/tmp/claude-1000/tmp.7i4C6FY0Cd/push-target repo.git'
```

So the spaced `push-target repo.git` path is load-bearing in the new scenario: a
word-splitting regression in `release.sh`'s value printing is caught by slice 2
as well as slice 1. The path is quoted at every hop (`git init`, `git config`,
`assert_contains`), and the refusal prints it intact on one line. Residual,
unchanged from slice 1 and not worth closing: `assert_contains` reads the needle
as a BRE, so the `.` in the `mktemp` component is a wildcard — it can only make
the match looser, never split it.

## Changes applied to `tests/release-test.sh`

- Added
  `assert_contains "$out" "push route diverges from origin" "resume diverged-push-route names the refusal"`
  with a comment recording the `To <path>` measurement that motivates it.
- Added a comment above the setup assertion recording the broken-setup probe
  that proves it load-bearing.

No existing scenario weakened, skipped or rewritten. The `pushtarget` /
`push-target repo.git` fixture names are untouched, as are the `ls-remote | cut`
captures.

Post-edit: `bash -n` clean, `shellcheck` clean, full suite exit 0, 50 scenario
headers, `all release scenarios passed`.

## State on exit

- `toolkit/release.sh` — **untouched.** Three mutations applied and restored;
  final `diff` against `/tmp/claude-1000/s2rev/release.sh.orig` empty,
  `sha256sum` `cd91ac53725cac7541062792364679a3ca387e3580bf042ccccdf3815e4a0b36`
  (identical to the pre-review hash), `git diff --stat -- toolkit/release.sh`
  silent.
- Modified: `tests/release-test.sh` only.
- **Nothing committed. Nothing staged.**
- All scratch under `/tmp/claude-1000/s2rev/` (backup, mutated copies, run logs,
  a trimmed probe harness symlinking the repo's `toolkit/`). Nothing left in the
  repo root; `$TMPDIR` was unset and set explicitly per run.
