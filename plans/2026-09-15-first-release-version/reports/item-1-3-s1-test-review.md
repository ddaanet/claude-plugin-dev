# Item 1.3, slice 1 — test review

Scope: `tests/release-test.sh` (the diverged-push-route scenario) and
`plans/2026-09-15-first-release-version/reports/item-1-3-s1-red.md`.
`toolkit/release.sh` was probed and restored; nothing committed.

**Verdict: fixed, still red for the right reasons.** Failures went 15 → 17: two
assertions that passed by accident now fail on their own merits.

## 1. The names-the-value experiment — a real hole, now closed

The RED report's defence of the assertion was **half right and half wrong**, and
the wrong half was the dangerous one.

### Right half: a key-only GREEN is caught for `pushurl`

Throwaway probe in `common_preflight`, before `[ -f "$manifest" ]`, refusing
correctly but naming only the key:

```sh
die "push route diverges from origin: $_pk is set; unset it or point it at origin"
```

Result: **all three** `names the value` assertions failed. The report's
reasoning holds — once `common_preflight` refuses before any side effect, `$out`
is exactly one line (the refusal), so the `To <url>` leak that makes the
assertion pass today is gone. Post-GREEN transcript, verbatim:

```
error: push route diverges from origin: remote.origin.pushurl is set; unset it or point it at origin
```

So **scoping the assertion to "the refusal line" gains nothing here** — unlike
Item 1.2 slice 6, the whole post-GREEN transcript *is* the refusal line. That
part of the Item 1.2 fix does not transfer.

### Wrong half: the needle `other` is matched by ordinary English

For `pushRemote` and `pushDefault` the config value was the literal string
`other`, and the assertion greps `$out` for it. `other` is a substring of
`another`. Second probe, same key-only refusal, with a wording no reviewer would
blink at:

```sh
die "$_pk is set, so this repo fetches from origin but pushes to another repository; unset it or point it at origin"
```

Result: **14 of 15 assertions passed.** Only `pushurl`'s value assertion failed.
A GREEN that names the key and never the value sails past both name-based
settings — exactly the Item 1.2 slice 6 defect class, arriving through the
fixture rather than through assertion scope.

### Fix applied

The redirect remote is renamed `other` → `pushtarget`, and its directory
`other repo.git` → `push-target repo.git` (hyphen, so the `pushurl` path is not
itself a match for the `pushtarget` needle). The needle is now a token no
English refusal message can contain. Re-ran the "another repository" probe
against the fixed fixture: **all three value assertions fail.** Hole closed.

The rationale is written into the scenario comment, including the empirical
before/after counts, so a later edit does not rename it back to something
prose-shaped.

`pushurl`'s value assertion still passes today, for the accidental reason the
RED report gave. That one is genuinely fine: the needle is a `mktemp` path with
a random suffix, which no message can produce by accident, and the probe proved
it discriminates post-GREEN.

## 2. Mechanical

`bash -n` and `shellcheck` on `tests/release-test.sh`: clean.

Full run (`TMPDIR=/tmp/claude-1000 bash tests/release-test.sh`), exit 1:

- 49 scenario headers, unchanged from the pre-fix run.
- **17 failures, every one inside the diverged-push-route block**
  (`grep '^FAIL' | grep -cv diverged-push-route` → 0).
- All are `assert_eq` / `assert_contains` failures. No ERROR line, no bash
  diagnostic, no `error:` outside a captured `$out`.
- Per setting, 6 of 6 assertions red for `pushRemote` and `pushDefault`, 5 of 6
  for `pushurl` (the value one, above).

No scenario outside the block moved: the pre-fix run had 15 failures, all in the
block; the post-fix run has 17, all in the block; the two new ones are the
`pushRemote` / `pushDefault` value assertions.

## 3. Numbered judgements

### 2. Would a too-eager refusal pass? — out of scope, by requirement

Yes, and that is the specified behaviour. `outline.md` decision 3 is explicit:

> **Decided:** `common_preflight` refuses when **any of the three is set**,
> before any side effect and on both `release` and `--resume`, naming the
> setting and its value.

Not "when it diverges". The SSH-vs-HTTPS `pushurl` pointing at the same
repository is refused, and the recovery the decision names — "unset it or point
it at origin" — covers that maintainer directly. The rejected alternative was an
untested accepted bound, not a narrower predicate.

Comparing URLs for repository identity is also not decidable in shell:
`git@github.com:o/p.git`, `https://github.com/o/p`, `ssh://git@github.com/o/p/`
and an `insteadOf` rewrite all denote one repository, and `ls-remote` on each to
compare ref sets is a network round-trip on the common path.
**No scenario should pin the distinction** — a scenario asserting "same-repo
pushurl is allowed" would contradict decision 3 and would have to be deleted by
the GREEN implementer.

Nothing in the suite stops a set-only refusal, and nothing should.

### 3. `branch.main.pushRemote` hardcodes `main` — a real gap, not fixture-fixable here

`release.sh` **does not** assume `main`. It derives it:

```
release.sh:148  main_branch=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' || echo "main")
release.sh:149  [ "$branch" = "$main_branch" ] || die "must be on $main_branch (currently $branch)"
```

`main` is only the fallback when `origin/HEAD` is unset. A `master`- or
`trunk`-default plugin is supported today, and a GREEN hardcoding
`branch.main.pushRemote` would leave it silently unprotected — the exact bug
decision 3 exists to prevent, on a repo shape the script otherwise handles.

The fixture cannot catch it: every repo in the suite is created by `git_init`
with `-b main` (`:70`, `:74`, and the bare repos at `:156-157`, `:870`), and no
scenario anywhere checks out a different branch. Widening means new fixture
surgery (rename the branch, re-point `origin/HEAD`, re-push) for one key.

**Recommendation — a code-review requirement on the GREEN, not a fourth loop
iteration.** `common_preflight` already computes `$branch` at `:144`, before any
side effect, so the correct key is free: place the push-route check after `:149`
and read `branch.$branch.pushRemote`. That is trivially checkable by eye, and
the placement still satisfies decision 3's "before any side effect". I did not
widen the fixture; the lead's instruction was to report unless it mattered, and
it matters in a way a review check settles more cheaply than a fixture does.

### 4. Status-1 absorption — unpinnable, and the comment was wrong about why

Confirmed by mutation. A probe GREEN reading the key as
`if git config --get "$_pk" >/dev/null; then` — which absorbs **every** non-zero
status, not only 1 — and naming both key and value, makes the entire suite pass:
`EXIT=0`, `all release scenarios passed`. The scenario cannot tell the two
disciplines apart, exactly as its comment conceded.

The proposed pin does not work either. I probed a corrupt config (an
`include.path` pointing at unparseable INI) on a real repo:

```
--- git config --get ---   fatal: bad config line 1 …   status=128
--- git symbolic-ref ---   fatal: bad config line 1 …   status=128
--- git status ---         fatal: bad config line 1 …   status=128
--- git diff HEAD ---      fatal: bad config line 1 …   status=128
```

A config git cannot parse breaks **every** git call, not just `git config`, so
the run refuses at `tree_is_clean` or `symbolic-ref` whatever the push-route
read does with the status. There is no fixture that makes `git config --get`
fail with a status other than 1 while leaving the rest of `release.sh` workable.
(Note also: the failure status is 128, not the `>=2` the scenario comment
guessed.)

**Judgement: nowhere.** Not slice 1, not slice 2 (`--resume`, same read, same
unobservability), not a later item. The discipline stays a code-review check on
the GREEN's absorption form. I rewrote the scenario's residual-bound comment to
say that and to record the 128-breaks-everything finding, so the next reader
does not spend the probe again.

### 5. Whitespace — genuinely exercised, nothing splits

The spaced path is exercised end to end, not merely stored. From the run against
unmodified `release.sh`, the `pushRemote` transcript:

```
To /tmp/claude-1000/tmp.IGhVBJolcw/push-target repo.git
 * [new branch]      main -> main
branch main: pushed
To /tmp/claude-1000/tmp.IGhVBJolcw/plugin-origin.git
 * [new tag]         v1.2.4 -> v1.2.4
```

The unqualified `git push` really reaches the spaced directory while the
qualified tag push does not — the divergence the item describes, observed, and
the space survives `git init --bare`, `git remote add`, `git config` and
`git push`.

Assertion side: `assert_contains` passes `"$2"` as a single `grep` argument and
`assert_eq` compares `"$1"` to `"$2"`; both are quoted throughout, so nothing
word-splits. `$other` is quoted at every use site. `value="$other"` carries the
space into the needle intact — verified by the probe failure message, which
printed the full spaced path as the needle it could not find.

BRE: I agree with the RED report's analysis. The path holds no `* [ ] ^ $ \`;
`.` as a wildcard can only widen a substring match, never produce a false
negative, and the haystack contains the literal path. `pushtarget` is
metacharacter-free.

### 6. Placement and loop hygiene — one hazard, fixed

Placement is correct: between `no-origin` and `non-semver v tags`, matching the
outline's ordering (`outline.md:196-202`).

No state leaks. `new_sandbox` runs first in every iteration and re-creates
`$sandbox`, `$plugin`, `$marketplace`, `$GH_LOG`, `$GH_RELEASES` and
`MARKETPLACE_DIR`; `$other` is re-derived from the fresh `$sandbox`, so the bare
repo is new each time. (`PATH` accretes one `$sandbox/bin` per `new_sandbox`,
but the newest is prepended and that is the harness's pre-existing behaviour
across all 49 scenarios, not something this block introduces.)

The one real hazard was the lead's: `key` and `value` were set **only** inside
the `case` arms, so an arm added later without setting them would silently reuse
the previous iteration's. Fixed with sentinels before the `case`:

```sh
key="NO-CASE-ARM-SET-key"
value="NO-CASE-ARM-SET-value"
```

Sentinels rather than `""` deliberately, with the reason in a comment: an empty
needle makes `grep -q -- ""` match anything, so `key=""` would convert a
stale-value bug into a silently passing assertion — strictly worse than the
hazard it was meant to close.

### 7. The `assert_eq` with embedded `&&`/`||` — correct, and it is the suite's idiom

```sh
assert_eq "$(git -C "$plugin" rev-parse --verify -q refs/tags/v1.2.4 >/dev/null && echo yes || echo no)" \
    "no" "diverged-push-route ($setting) created no v1.2.4 tag"
```

Both directions verified empirically in this run rather than by reading:

- tag present → `got 'yes'` (the RED and pre-fix runs, where `release.sh` runs
  to completion and tags).
- tag absent → assertion passes (the probe runs, where the refusal lands first).

It is safe under `set -e`: the `||` makes the list succeed either way, and the
substitution always emits a word, so `assert_eq` never receives an empty actual
by accident.

It is also the suite's established idiom for **this exact assertion** — the same
construct appears at `:236`, `:415`, `:430`. The suite does carry a terser form
for tag-absence (`assert_eq "$(git tag --list 'v*')" ""`, used at `:637`,
`:665`, `:751`, `:767`, `:792`, `:839`, `:850` and others), but that form is
used where *no* `v*` tag may exist at all, while the `rev-parse` form is used
where a specific tag is checked against a repo that may legitimately hold
others. This scenario is the latter case — the fixture keeps `v1.2.3`. Matching
`:415`/`:430` is right; switching would make this the only `v1.2.4`-specific
check written differently. **Left as is.**

## What changed in `tests/release-test.sh`

Three edits, all inside slice 1's scenario:

1. Redirect remote `other` → `pushtarget`, directory `other repo.git` →
   `push-target repo.git`, with a comment recording the `another`-contains-
   `other` finding and the before/after failure counts.
2. `key` / `value` sentinels before the `case`, with the reason empty strings
   would be worse.
3. Residual-bound comment rewritten: the status-1-vs-any distinction is
   unpinnable by any fixture (corrupt config → 128 from every git call), so it
   is a code-review check on the GREEN.

No existing scenario was weakened, skipped or rewritten. The `ls-remote | cut`
captures at `:438,466,562` were not touched.

## Guidance for the GREEN implementer

- Place the check in `common_preflight` **after** `:149` (the branch check) so
  `$branch` is available, and read `branch.$branch.pushRemote`, never
  `branch.main.pushRemote`. Still before any side effect, so decision 3 holds.
- The refusal message must name **both** the key and its value. Naming only the
  key now fails 3 assertions per setting; it used to fail 1.
- Absorb status 1 only:
  `v=$(git config --get "$key") || { [ "$?" -eq 1 ] || die …; }`, and recall
  `item-1-2-s6-code-review.md` §2 — `set -e` stays active inside the `|| { … }`
  group's body. No test can catch a violation here, so this is on code review.
- Avoid the words `another`, `other`, `otherwise` near the value if you also
  want the assertion to keep meaning what it says — the fixture now tolerates
  them, but the reason is worth knowing.

## State on exit

- `toolkit/release.sh` — **untouched.** Probed three times and restored from a
  byte copy each time; `sha256sum` is `8e51a37d…3aba532`, identical to the
  pre-review value, and `git status --short` shows it unmodified.
- Modified: `tests/release-test.sh` only. Untracked: this report and
  `item-1-3-s1-red.md`.
- **Nothing committed.**
- Suite re-run after the final restore: exit 1, 17 failures, all in slice 1's
  block.
- `bash -n` and `shellcheck` on `tests/release-test.sh`: clean.
- Slice 2 (`--resume`) not written. No implementation of the refusal landed.
