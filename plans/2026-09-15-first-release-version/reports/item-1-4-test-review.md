# Item 1.4 — test review (all four slices)

Verdict: **the five scenarios as delivered did NOT pin the ladder's shape.** Two
distinct wrong ladders pass all five. Both are now closed by two added
scenarios. Suite is at **13 failures**, all assertion failures, none `ERROR`,
none outside Item 1.4's scenarios.

## 1. Ladder shape — measured, not read

Method: the intended ladder was written as a throwaway patch to
`resume_preflight` (`toolkit/release.sh:500-512`), applied, the whole suite run,
and `release.sh` restored from a byte copy each time —
`git diff --stat -- toolkit/release.sh` verified empty after every one of the 13
runs.

The intended ladder probed (variant A), for reference:

```bash
origin_tag_list=$(origin_release_tags) || origin_tag_list=""
release_tag_list=$(release_tags)       || release_tag_list=""
if   printf '%s\n' "$origin_tag_list" | grep -qx -- "$tag"; then  # 1 fetch + resume-release
elif [ -n "$origin_tag_list" ];                            then  # 2 fetch + release <bump>
elif [ -z "$release_tag_list" ];                           then  # 3 just release
else                                                             # 4 just release <bump>
```

### As delivered (five scenarios)

| # | Implementation | Failures | Caught? |
|---|---|---|---|
| A | Intended ladder (origin-first, membership test, 4 branches) | 0 | — (correct) |
| B | Branch order permuted: `-n origin` tested **before** `origin has v$V` | 2 (slice 2) | yes |
| **C** | **Local-tags-present branch tested FIRST, origin consulted after** | **0** | **NO — gap** |
| D | 3 branches: one origin branch, always `just release <bump>` | 2 (slice 2) | yes |
| E | 3 branches: one origin branch, always `just resume-release` | 1 (slice 3) | yes |
| F | Local branches collapsed → always `<bump>` | 3 (slices 1, 4b) | yes |
| G | Probe failure fatal (copies `release_preflight`'s fail-closed `die`) | 3 (slice 4b) | yes |
| H1 | `origin_tag_list=$(origin_release_tags)` with status unread (errexit kills the run) | 2 (slice 4b) | yes |
| H2 | Bare substitution in test context: `[ -n "$(origin_release_tags)" ]` | 0 | no — see §1.3 |
| **I** | **`[ "$origin_newest" = "$tag" ]` instead of membership in the listing** | **0** | **NO — gap** |
| J | Local branches collapsed → always no-arg `just release` | 1 (slice 4a) | yes |
| K | Hint always names `git fetch --tags` in its header | 1 (slice 4a) | yes |

The dispatch's "empty-origin branch merged with the failed-probe branch"
permutation **is** variant A: the outline requires a failed listing to fall
through to the local hints, so merging them is the correct shape, and G/H1 are
the two ways of not merging them. Both are caught.

### Gap C — origin evidence must outrank local tags

In all five delivered scenarios, `release_tags` is empty **whenever** origin
carries any evidence, so "check local first" and "check origin first" are
indistinguishable. A ladder that answers `just release <bump>` the moment the
clone has any tag of its own — while origin holds `v$V` itself — passes the
whole suite. That advises starting a fresh release over the exact tag origin
already published.

### Gap I — membership, not newest

Origin's listing is one tag long in every delivered scenario, so `contains v$V`
and `newest is v$V` are the same predicate. `release_preflight` already reads
`origin_newest=$(… | sed -n '1p')` at `:362`, so a GREEN implementer copying the
neighbouring idiom lands on I by default. With origin holding `v1.3.0` above
`v1.2.3` and `$V = 1.2.3`, I advises a bump release over a `v1.2.3` origin
demonstrably has.

### Scenarios added (`tests/release-test.sh:478-517`)

- `resume: origin's copy of v$V outranks a local tag this clone still has` —
  `new_sandbox "1.2.3"`, an extra local `v1.1.0` kept, `lose_tag "$plugin"`.
  `release_tags` non-empty, origin holds `v1.2.3 == $V`. Closes C (C now fails 3
  assertions; A unaffected).
- `resume: v$V among origin's tags counts even when a newer tag sorts above it`
  — `new_sandbox "1.2.3"`, `v1.3.0` created, pushed, then dropped locally, then
  `v1.2.3` dropped locally. Origin listing is `v1.3.0, v1.2.3`; `$V = 1.2.3`.
  Closes I (I now fails 2 assertions; A unaffected).

Both are genuinely red today (3 failures each: no `git fetch --tags`, no
`just resume-release`, and `just release <bump>` present). Post-addition matrix:
A 0, B 6, C 3, D 6, E 1, F 3, G 3, H1 2, H2 0, I 2, J 1, K 1.

**Note for GREEN:** these two scenarios constrain more than the runbook's four
literal slices — they pin branch *order* (origin before local) and the
*predicate* (membership, not newest). Both follow from the runbook's own wording
("picks its hint from one `origin_release_tags` listing"; slice 2 is titled
"`v$V` on origin"), but they are stated here for the first time.

### 1.3 H2 — the bare substitution slice 4b does not catch

Slice 4b catches the **assignment** form (H1): an unread
`origin_tag_list=$(origin_release_tags)` dies under errexit before `die` ever
prints, and 4b reports it as two failures including the missing `no tag …`
message — exactly the "changed output entirely" signature the RED report
predicted.

It does **not** catch the **test-context** form,
`[ -n "$(origin_release_tags)" ]`. That form does not trip errexit (the status
is consumed by `[`), and it fails *open* — a broken listing reads as empty,
which routes to the local hints, which is precisely what the intended ladder
does on a failed probe. H2 is therefore
**behaviourally indistinguishable from A at the output level**: no assertion
over stdout/stderr/exit code can separate them. The only observable difference
is that H2 issues up to three `git ls-remote` calls where the outline specifies
one, and detecting that would need a `git` interceptor on the fixture `PATH` —
disproportionate, and it would sit in front of every git call in the suite. This
is **UNFIXABLE at the test level**; it belongs to the Item 1.4 code review,
which should check that the listing is read into a variable exactly once.

## 2. The substring defence

Tested directly, driving the suite's own `assert_contains`/`assert_not_contains`
bodies over hand-made candidate messages:

| Candidate hint text | `'just release`'` present | `"just release <bump>"` absent | slice 1 verdict |
|---|---|---|---|
| ``run `just release <bump>` instead.`` | no | no | FAIL (both) |
| ``run `just release` instead.`` | yes | yes | PASS |
| ``run `just release patch` instead.`` | no | yes | FAIL |
| ``run `just release  <bump>` instead.`` (two spaces) | no | yes | FAIL |
| ``run `just release now` instead.`` | no | yes | FAIL |
| ``run `just release` or `just release <bump>`.`` | yes | no | FAIL |

The needles are the **right** contract, not a coincidence — but the weight sits
on the positive one.
`'just release`'` pins the closing backtick of the inline-code span, so it rejects every variant that puts anything at all after the word `release` inside the span: the bump form, `patch`, two spaces, a trailing word. That is the actual requirement ("the hint names `just
release` with no bump argument"), stated as the shape of the span rather than as
a ban on one phrase. The negative needle earns its place on exactly one case the
positive one passes: a message naming **both** forms.

Residual, bounded: where `assert_not_contains "$out" "just release <bump>"`
stands without a positive no-arg needle beside it — slice 2 and the two added
scenarios — it bans a *phrase*, not a *form*. A hint reading
``…then `just resume-release` — or `just release patch` to start fresh`` would
satisfy it. I did not tighten this (e.g. to a `"just release "` trailing-space
needle): those three scenarios each carry a positive `just resume-release`
assertion, so the escape requires a hint that gives two contradictory remedies
at once, and an over-tight needle would constrain the GREEN implementer's
wording by a rule nothing states.

## 3. Slice 4a — 0-of-5 red, pure guard: it discriminates

Proven by two mutations that **only** 4a catches, each producing exactly one
failure across the whole suite, and that failure being 4a's:

- **J** — local branches collapsed to the no-arg form (`release_tags` never
  consulted): `FAIL: local-tag-survives resume hint names the bump form`. Slices
  1, 2, 3, 4b all still pass.
- **K** — the hint's header always names `git fetch --tags` (a plausible
  "mention the remedy up front" wording):
  `FAIL: local-tag-survives resume hint must not advise a fetch — origin has no evidence to fetch`.
  Everything else still passes; no other scenario asserts the *absence* of the
  fetch remedy.

4a is the suite's only guard on branch 4's existence and on the fetch remedy
being conditional. It earns its place.

## 4. Slice 2's in-place rewrite

Before (one hint assertion):

```bash
assert_contains "$out" "run \`just release <bump>\` instead" "no-tag resume hint"
```

After (three):

```bash
assert_contains "$out" "git fetch --tags" "no-tag resume hint names the fetch remedy"
assert_contains "$out" "just resume-release" "no-tag resume hint names resume-release, not a fresh release"
assert_not_contains "$out" "just release <bump>" "no-tag resume hint must not advise the bump form"
```

- Fixture untouched (`new_sandbox "1.2.3"` + local-only `git tag -d v1.2.3`), as
  the RED report states. Verified by diff.
- Nothing else depended on the removed assertion: `grep -n 'just release <bump>`
  instead'` over `tests/release-test.sh` returns no other hit, and the label `"no-tag
  resume hint"` was unique to this line.
- Not weakened: the scenario went from 1 hint assertion to 3, and `rc`, the
  `no tag v1.2.3 …` message and the `gh`-not-called guard are all unchanged.
- `<bump>` coverage genuinely re-established: slice 3
  (`other-origin-tag resume hint names the bump form`) and slice 4a
  (`local-tag-survives resume hint names the bump form`) both assert it
  positively, and measurement confirms each is load-bearing — E fails only on
  slice 3's, J fails only on slice 4a's.

## 5. Branch-selection claims — verified by instrumentation

Variant A was re-run with a marker appended to a side log at each of the four
branch bodies. Exactly **seven** hint emissions were recorded across the whole
suite, in scenario order — confirming both the branch each fixture selects and
that no other scenario in the file reaches `resume_preflight`'s no-tag path:

| Scenario | `$V` | Branch measured | RED report claim | Match |
|---|---|---|---|---|
| slice 1, virgin | 0.1.0 | 3 (no local tags) | 3rd | yes |
| slice 2, `v$V` on origin | 1.2.3 | 1 (origin has `v$V`) | 1st | yes |
| slice 3, other semver on origin | 1.3.0 | 2 (origin, other semver) | 2nd | yes |
| slice 4a, local tag kept | 1.2.4 | 4 (local tags present) | 4th | yes |
| slice 4b, no origin remote | 1.2.3 | 3, via a **failed** probe | 3rd, failed probe | yes |
| added: origin outranks local | 1.2.3 | 1 | — | — |
| added: newer tag above `v$V` | 1.2.3 | 1 | — | — |

Every RED-report branch claim holds. No fixture reaches its hint via the wrong
branch. Slice 4b's probe really does fail rather than return empty — G and H1
both break on 4b and on nothing else, which is only possible if
`origin_release_tags` returns non-zero there.

## 6. Whitespace safety

Reviewed all seven fixtures: every `$plugin`, `$out`, `$GH_LOG`, `$marketplace`
and `lose_tag` argument is double-quoted; no unquoted command substitution; the
`jq`/`mv` temp-file pairs quote both operands. No splitting on whitespace
anywhere in the added or rewritten blocks.

Measured, not read: the full suite re-run with
`TMPDIR="/tmp/claude-1000/i14/space dir"`, so every `mktemp -d` sandbox path —
and therefore every plugin repo, bare origin, marketplace repo, `gh` stub and
`PATH` entry — contains a space. Result:
**the same 13 failures, byte for byte, nothing else.**

## 7. Mechanical

- Suite before my additions: 7 failures, all assertion `FAIL`, none `ERROR`, all
  inside Item 1.4's five scenarios — matches the RED report exactly.
- After: 13 failures (7 + 3 + 3), same properties.
- The three long-standing protected scenarios pass in every run:
  `release: common_preflight refuses a diverged push route`,
  `resume: common_preflight refuses a diverged push route`,
  `release: the dirty-path report keeps a spaced path in one piece`. So do all
  ~50 other scenarios.
- `bash -n tests/release-test.sh` and `shellcheck tests/release-test.sh`: clean.

## State on exit

- `toolkit/release.sh`: **byte-identical to `f5d7521`** —
  `git diff --stat HEAD -- toolkit/release.sh` is empty. All 13 ladder probes
  were applied and restored from a copy; the restore was verified after each.
- Nothing committed. `git status --porcelain` shows `M tests/release-test.sh`
  and the untracked `plans/.../reports/item-1-4-red.md` (plus this file).
- Only `tests/release-test.sh` modified. No pre-existing scenario weakened,
  skipped or renamed; the `pushtarget`/`push-target` fixture and the
  `ls-remote | cut` captures at `:438,466,562` untouched.
- Scratch under `/tmp/claude-1000/i14/` cleaned of sandboxes; nothing left in
  the repo root.
