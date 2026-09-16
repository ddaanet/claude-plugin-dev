# Item 1.2, slice 1 — code review

Scope: `toolkit/release.sh` only (the implementation landed in `3794941`).
`tests/release-test.sh` and every other file are out of scope; the two report
corrections below are the ones the dispatch asked for by name.

Verdict: the implementation is behaviourally correct — the probe fires where the
runbook puts it, the capture rule holds at every new and touched call site, and
the `check-version.sh` path is provably unchanged. One load-bearing comment
stated a false fact about the shell and is fixed. Two comment gaps closed. One
real gap recorded for slice 3. Nothing committed.

## 1. The pipefail question — settled empirically, and the claim was wrong

**The dispatch's suspicion is correct.** Under `set -o pipefail` bash returns
the **rightmost non-zero** stage status, so a failing `ls-remote` followed by
zero-exit filters yields 128, not 0.

Probe, run against bash 5.2 / git 2.47.3, with the file's own `semver_tags`
definition:

```
set -o pipefail
fail128 | cat | cat                                         -> status=128
fail128 | cut -f2 | sed 's|^refs/tags/||' | semver_tags      -> status=128
set +o pipefail
fail128 | cut -f2 | sed 's|^refs/tags/||' | semver_tags      -> status=0
```

And against a real `git ls-remote` in a repo with no `origin` remote, using the
piped and the captured shapes side by side:

```
--- no origin remote, pipefail ON ---
piped:    refused, status 128
captured: refused, status 1
--- same, pipefail OFF ---
piped:    SUCCEEDED (fail-open) out=[]
captured: refused, status 1
```

So the GREEN report's sentence — "would still report the *pipeline* as
succeeding … every stage after a failed `ls-remote` here legitimately exits 0 on
empty input" — is false as written, and so was the same claim in the code
comment.

**The capture is still the right choice**, and the true reason is the second row
of that table. `semver_tags` deliberately absorbs a no-match grep's status 1, so
the filter tail is status-transparent; `pipefail` is therefore the *only* thing
that would carry a failed listing out of the piped form. That leaves the
function's safety resting on one word of the `set` line 250 lines further up,
with no local signal. The captured form holds either way.

**Fix applied** — `toolkit/release.sh`, `origin_release_tags`'s comment. The
false paragraph is replaced with the measured statement plus the true reason,
and it names the versions the measurement was made against so a later reader can
re-run it. It now says plainly that piping is *not wrong today*, which is the
honest framing; the old text implied the piped form was already broken.

**Report corrected too.** `item-1-2-s1-green.md`'s "Exit-status reasoning"
paragraph now carries a marked correction block quoting the false claim, the
measurement, and the surviving reason.

**Flagged, not fixed:** commit `3794941`'s message carries the same false
framing ("so a failed listing … refuses closed rather than reading as 'origin
has no tags either' under pipefail's last-nonzero-status semantics" — offered as
the *reason* capture is needed). Commit messages are not rewritten; the GREEN
report's correction block notes it explicitly so the record is not silently
wrong.

## 2. The GREEN report's slice-3 bullet — confirmed wrong, corrected

The runbook (`runbook.md`, Item 1.2, slice 3) says slice 3 is
*the origin listing is version-sorted* — the `v1.9.0`/`v1.10.0`/`v1.11.0`
fixture pinning `--sort=-v:refname`. `resume_preflight`'s no-tag refusal and its
hint ladder are Item 1.4. The GREEN report described the latter under the
former.

**Did the confusion shape the implementation? No.** `--sort=-v:refname` is
present on the `ls-remote` call, and the sort's reason (lexicographic refname
order is not version order) is in the function's code comment as the runbook's
interface clause requires. I verified the comment's example is true, not just
plausible:

```
git ls-remote --tags origin                (no --sort)  -> v1.10.0 v1.11.0 v1.2.3 v1.9.0
git ls-remote --tags --sort=-v:refname origin           -> v1.11.0 v1.10.0 v1.9.0 v1.2.3
```

The comment's "v1.10.0 sorts before v1.2.3 sorts before v1.9.0 as strings" is
exactly the first row. The same probe also confirms the `refs/tags/vX.Y.Z^{}`
peeled rows that annotated tags add are dropped by `semver_tags`'s anchored
pattern and never reach the hint.

The report's bullet is rewritten to describe slice 3 and to carry the gap in
section 3 below.

## 3. Which end of the listing is read — a real gap, slice 3's to close

**`sed -n '1p'` is correct** (the listing is newest-first) and
**nothing in the suite discriminates it today.** Measured, not read: mutating
`1p` to `$p` in-place and running the full suite gives
`all release scenarios passed`, zero failures. The file was restored from a
pre-mutation copy in the same shell invocation and
`git diff --stat toolkit/release.sh` was empty afterward.

This is the Item 1.1 bug class the dispatch named, and for the same structural
reason: no fixture in slice 1 puts two semver tags on origin, so "names the
newest" and "names the only one" are the same assertion.
**I did not widen slice 1's fixture.** Slice 3 closes it as specified — with the
sort in place its fixture makes `1p` = `v1.11.0` and `$p` = `v1.2.3`, so the
hint assertion separates them, and without the sort both ends are wrong tags.
Recorded as a gap that must not be allowed to lapse if slice 3 is ever rescoped.

**Fix applied** — the `origin_newest=` line had no comment at all, while the
structurally identical `latest_tag=` read 50 lines below carries the full
argument (newest-first contract, `sed` over `head -1` for the SIGPIPE reason,
why no status check is needed). The new line now states the same three facts and
points at that argument rather than restating it.

## 4. The capture rule — audited at every new and touched call site

| Site | Shape | Verdict |
|---|---|---|
| `origin_release_tags:258` | `listing=$(git ls-remote …) \|\| return 1` | correct — reads ls-remote's own status |
| `release_preflight:275` (moved) | `release_tag_list=$(release_tags) \|\| die …` | correct, unchanged by the move |
| `release_preflight:299` (new) | `origin_tag_list=$(origin_release_tags) \|\| die …` | correct — never `[ -n "$(…)" ]` |
| `release_preflight:307` (new) | `origin_newest=$(printf … \| sed -n '1p')` | no status needed; string is already captured and non-empty. Now says so. |
| first-release branch `:330` | tests the already-captured `$release_tag_list` | correct — no recompute, so no second unread status |
| `latest_tag:361` | `$(printf … \| sed …)` on the captured string | unchanged, correct |

No `[ -z "$(f)" ]` / `[ -n "$(f)" ]` shape survives anywhere on this path.

**Flagged, out of scope, not fixed:** three *pre-existing* sites take the shape
this slice's reasoning argues against —

```
toolkit/release.sh:438   remote_head=$(git ls-remote origin "refs/heads/$branch" | cut -f1)
toolkit/release.sh:466   remote_tag=$(git ls-remote origin "refs/tags/$tag" | cut -f1)
toolkit/release.sh:562   mp_remote_head=$(git -C "$MARKETPLACE_DIR" ls-remote origin "refs/heads/$mp_branch" | cut -f1)
```

Each is a bare `ls-remote | cut` capture. They are fail-*closed* today only
because `set -e` plus `pipefail` kills the script at the assignment — exactly
the dependency `origin_release_tags` was just written to avoid. With pipefail
off, each would set its variable to the empty string and fall through: `:438`
into an unnecessary push (benign), `:466` into skipping the "refusing to move a
published tag" guard (**not** benign). The restructuring did not move these
lines, so they are outside this slice; recorded here as a seam a later item
should take deliberately rather than by accident.

## 5. The restructuring — proved not to change the `check-version.sh` path

Two arguments, both run.

**By reading.** `toolkit/check-version.sh` is read-only end to end: `jq -r`
reads, `echo` to stdout/stderr, `exit 0|1`. It writes no file and mutates no
ref, so nothing it does can be observed by `release_tags` and nothing
`release_tags` does can be observed by it. The only ordering the old code could
have relied on is that `manifest_version` is assigned *after* `check-version.sh`
— still true, and `release_tag_list`'s capture does not read `manifest_version`.

**By probe.** The suite has *no* scenario where `check-version.sh` actually
fails — grep confirms every reference is a passing or a skipping case. So I
built the missing case directly, running the pre-commit `3794941^` release.sh
and the current one against the same fixture (marketplace entry at `9.9.9`,
manifest at `1.2.3`):

| Fixture | Old `release.sh` | New `release.sh` |
|---|---|---|
| drift + local tag present, `patch` | drift → hint → `error: fix the version drift above before releasing`, rc 1 | **byte-identical**, rc 1 |
| drift + genuinely virgin (no tag local or on origin) | same drift refusal, rc 1 | **byte-identical**, rc 1 |
| drift + local tag lost, origin still has it | drift refusal, rc 1 | fetch hint + `local release tags are missing …`, rc 1 |

Rows 1 and 2 are the regression check and they are clean: the drift refusal
fires at the same point, with the same three lines, in the same order, at the
same status. Row 3 is the intended change — the runbook's "before
`check-version.sh`" — and it is the one slice 4 will pin with a fixture where
the drift advice would be actively harmful.

Also confirmed: a failing `release_tags` now dies *before* `check-version.sh`
rather than after it. That reorders two diagnostics and loses no side effect
(check-version.sh has none), so it is a message-order change, not a behaviour
change. Noting it because it is the only observable consequence of the move that
the table above does not cover.

## 6. Whitespace safety

`cut -f2` splits on TAB; `git ls-remote` emits exactly `<oid><TAB><ref>`.
Verified rather than assumed that a ref name cannot carry whitespace:

```
git tag 'v1.2.3 x'          -> fatal: 'v1.2.3 x' is not a valid tag name.
git tag $'v1.2.3\tx'        -> fatal: ... is not a valid tag name.
git tag $'v1.2.3\nx'        -> fatal: ... is not a valid tag name.
git check-ref-format 'refs/tags/v1 2'    -> refused
git check-ref-format $'refs/tags/v1\t2'  -> refused
```

So the split is total for anything that can reach this code.
**Residual bound, now stated in the comment rather than implied away:** a line
with no TAB at all is passed through whole by `cut`; nothing `ls-remote` emits
has that shape, and `semver_tags`'s anchored `^v[0-9]+\.[0-9]+\.[0-9]+$` drops
it if one ever did. The same anchor is what drops the `^{}` peeled rows.

Every expansion on the path is quoted: `printf '%s\n' "$listing"`,
`printf '%s\n' "$origin_tag_list"`, `printf '      %s…' "$origin_newest"`, and
`"$origin_newest"` inside the `die` string.

## 7. Output channels and hint convention

- Both `printf` hint lines and `die` go to stderr
  (`die() { printf 'error: %s\n' "$*" >&2; exit 1; }`). Nothing is suppressed.
- `git ls-remote`'s own stderr is **not** redirected, so
  `fatal: 'origin' does not appear to be a git repository` reaches the user
  before the refusal. Right call — the refusal message says the listing failed,
  and git's line says why. Slice 5 should not add a `2>/dev/null` here.
- Indentation matches the file's convention exactly: `hint: ` opener, 6-space
  continuations aligning under it, one `printf … >&2` per physical line. Same
  shape as `:332-339` and `:317-320`.
- The `# shellcheck disable=SC2016` above the backticked hint line is
  **load-bearing, not cargo-culted** — verified by deleting every such disable
  in the file and re-running shellcheck: SC2016 fires on backticks inside single
  quotes, and the new line is among the 11 hits. The comment's wording
  ("backticks are literal markdown, not command substitution") is accurate.

## 8. Comment honesty sweep

Every comment the slice added or moved, checked against what the code does now:

| Comment | Verdict |
|---|---|
| `origin_release_tags` — "same contract as release_tags, read from origin" | true |
| `origin_release_tags` — the `--sort=-v:refname` reason | true, example verified against git 2.47.3 |
| `origin_release_tags` — the pipefail paragraph | **was false; rewritten** (§1) |
| `origin_release_tags` — new TAB/whitespace bound | new, measured (§6) |
| `release_preflight:270-274` — the `release_tags` capture rule, moved verbatim | still true at its new position; it argues about the capture, not about the ordering, so the move does not stale it |
| `release_preflight:278-282` — "before check-version.sh and so before any side effect" | true, and proved by §5 |
| `release_preflight:284-288` — "any semver tag, not only `v$manifest_version`" | true — the `if [ -n "$origin_tag_list" ]` tests the whole filtered listing |
| `release_preflight:290-296` — the `[ -n "$(…)" ]` capture-rule argument | true; unlike §1's claim, command substitution in `[ ]` genuinely discards status |
| `release_preflight:349-360` — the `latest_tag` comment | untouched and still accurate; the "computed once, after check-version.sh" fact it never asserted is not stale |

No comment asserts something the code no longer does, and nothing still-live was
deleted: the moved `release_tags` capture-rule block is present in full at its
new location (checked against `3794941`'s diff — 8 lines removed at the old
position, the same 8 added at the new one).

## 9. File length and the split seam

`toolkit/release.sh` is **619 lines** after this review: 543 before `3794941`,
602 at it, 619 now. My fixes are `+23 / -6`, every added line a comment. Past
the 400-line soft cap, as two prior reviews recorded.

**No change to the seam analysis, and I did not split.** If anything this slice
strengthens the prior reviews' reason to decline: `origin_release_tags` is the
third member of the `semver_tags` / `release_tags` cluster the earlier reviews
named as the candidate seam, but it is also the member with the tightest
coupling to `release_preflight`'s refusal — its comment and the caller's comment
are one argument split across two places, and moving half of it into a second
file would put the two halves in different files for a reader to reconcile. The
cost side is unchanged and still dominant: a second file is a new *shipped*
path, so `tests/dist-tree-test.sh`'s list and the CLAUDE.md Layout list both
have to move with it, and consumers vendoring the subtree pick up a new file
name they did not ask for. Still a recorded open decision for the Phase 1
boundary, still declined here.

Worth saying plainly for whoever takes that decision: the growth is
comment-dominated, not logic-dominated. `3794941` added 67 lines, 45 of them
comment; this review added 23, all 23 comment. So 68 of the 90 lines the slice
put into the file are argument rather than logic. A split that moved code away
from its arguments would not reduce what a reader takes in — it would double the
places they have to look.

## 10. Not implemented (flagged, per the dispatch)

- **Slice 2** — origin-tag *identity* (`new_sandbox "1.3.0"` over a published
  `v1.2.3`). The implementation already reads *any* semver tag on origin, so the
  behaviour is there; nothing pins it.
- **Slice 3** — the sort. Implemented; not pinned. See §3 for the measured gap.
- **Slice 4** — probe before the drift check. Implemented; §5's row 3 is the
  behaviour, and no fixture in the suite pins it.
- **Slice 5** — the failed-listing refusal. Implemented per the capture rule; no
  fixture breaks origin, so the message wording is unvalidated. One note for
  whoever takes it: do not suppress `ls-remote`'s stderr (§7).
- **Slice 6 / Item 1.4** — untouched. `check-version.sh`'s failure hint still
  offers `just resume-release` unconditionally; `resume_preflight` has no origin
  probe.

Nothing above was built.

## 11. UNFIXABLE / in-scope-unfixable

None. Every defect found in scope was fixed in this pass. The three pre-existing
`ls-remote | cut` captures in §4 are real but out of this slice's scope, not
unfixable.

## State on exit

- `toolkit/release.sh` — **modified, uncommitted.** `git diff --stat` shows
  `1 file changed, 23 insertions(+), 6 deletions(-)`, all of it the two comment
  fixes in §1/§6 and §3. No executable line changed: the only non-comment lines
  in the diff are context.
- `plans/…/reports/item-1-2-s1-green.md` — **modified, uncommitted.** Two marked
  corrections (§1, §2). Nothing else in it touched.
- `plans/…/reports/item-1-2-s1-code-review.md` — this file, new.
- Every mutation restored. `1p`→`$p` and the SC2016-strip probes were each
  applied and reverted inside a single shell invocation, and
  `git diff --stat toolkit/release.sh` was verified empty after each before the
  real fixes were applied.
- Three stray probe directories (`ppf/`, `sortprobe/`, `wsprobe/`) were created
  in the repo root by a probe whose `$TMPDIR` was unset in that shell, and
  **removed**; `git status --short` is clean of them.
- **Nothing committed.**
- `bash tests/release-test.sh` — green, `all release scenarios passed`.
- `just precommit` — green.
