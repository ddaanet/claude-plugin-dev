# Phase 2 boundary checkpoint — Item 2.1, `tests/self-release-test.sh`

**Scope reviewed:** `git diff 1acd373..HEAD` restricted to
`tests/self-release-test.sh` (commit `c5a4196`) and the execution report
`reports/item-2-1.md` (commit `5a6cd7e`). Contract: `runbook-test-suites.md`,
Item 2.1 parts (a)–(d) and their four Mutation gates.

**Verdict: the contract is met in all four parts.** Every mutation gate was
re-run here rather than taken on the report's word, and every quoted piece of
evidence in `reports/item-2-1.md` reproduced verbatim. Four fixes applied, all
inside part (b)/(d)'s own new assertions; three of them turn an assertion that
could not fail into one that does. No UNFIXABLE findings.

## Per part

### (a) N7 — untracked leftovers on the happy path

Contract met. The check is the runbook's: `ls-files --others --exclude-standard`
captured and required empty, sitting beside the existing `diff --quiet HEAD`,
with a comment naming the blind spot and pointing at `stage_handoff_frame` in
`tests/release-test.sh` — which I read; the cross-reference is accurate and the
"opposite direction" framing is true (that helper documents an untracked path
never *reaching* a tracked-only check, this one documents an untracked path
never *failing* one).

The runbook's one open empirical question — whether the fixture already leaves
an untracked non-ignored path — is answered by the suite being green unmutated.
No fixture leftover; the assertion was not weakened.

**Mutation gate, re-run here** (stray file written in `bump_commit_tag`):

```
FAIL: happy: untracked leftovers left (MUTATION-STRAY.md)
1 self-release check(s) failed
```

Exactly one failure — the pre-existing `diff --quiet HEAD` stayed silent, which
is the gap the assertion closes. Matches the report.

**Changed:** nothing.

### (b) M1 — the dist split discriminates the tag's tree from `HEAD`'s

Contract met, and the literal instructions followed: the later work lands inside
`toolkit/` (`toolkit/later-work.md`), the `docs.md` commit is gone rather than
kept alongside, the local `dist-v0.2.0` is deleted before the resume, and both
new assertions are there (`git show dist-v0.2.0:later-work.md` must fail;
`ls-tree --name-only` must omit it). The unprefixed path in the `git show` is
right — the dist tree is `toolkit/`'s contents at its root.

The rewritten comment is true where the old one was false. It states that the
first invocation's split ran when `HEAD` and the tag coincided, which I verified
against `scripts/self-release.sh` (`bump_commit_tag` tags `HEAD`, then
`ensure_dist_tag` splits `$tag`), and it explains why the local tag deletion is
load-bearing rather than incidental.

**Mutation gate, re-run here** (`git subtree split … "$tag"` → `HEAD`):

```
FAIL: resume after work: dist tree carries later work
FAIL: resume after work: dist tree omits later file: output contained 'later-work'
```

Both new assertions red, nothing else in the file red. Matches the report.

**Changed — minor, applied:** the first assertion was written as
`git show … && fail "…"`. Under this file's `set -euo pipefail` that form is
safe only because of the AND-OR-list exemption (verified:
`set -e; false && echo boom; echo alive` prints `alive`) — a subtlety the rest
of the file does not rely on. Rewritten as the `if … then fail; fi` idiom the
ancestry fixture twenty lines up already uses. Same assertion, same label, no
set-`e` subtlety.

### (c) M3 — the `.claude` and `memory` exemptions actually constructed

Contract met, including every literal the runbook singles out:

- `stage_claude_frame` is the commit-then-rewrite-and-stage shape of
  `stage_handoff_frame`, line for line.
- `stage_memory_gitlink` carries `-c protocol.file.allow=always`, placed before
  `-C` on the parent `git`, which is where it has to be: the child clone reads
  it from its own environment.
- The `sub` upstream is built inside `$sandbox`, per scenario, and the comment
  states the reason the runbook gave (`new_sandbox` rebuilds `$repo`, so a
  shared upstream leaks state across scenario boundaries).
- The gitlink rests off `HEAD`'s recorded sha — two empty commits, add at the
  second, check the submodule out at the first.
- The false comment is gone; the replacement says the exclusions can only be
  proven by constructing real diffs under both paths, which is what the fixture
  now does.

**Fixture contract, verified independently of the report** by the two mutations.
Dropping `':(exclude).claude'`:

```
FAIL: .claude/ and memory/ are exempted from the clean check: expected '0', got '1'
```

Dropping `':(exclude)memory'`: the same line. Each half goes red
*on its own mutation*, which is the proof the runbook asked for — a fixture that
constructed only one of the two paths would leave the other mutation green. Both
stay green unmutated. The contract stated for git 2.47.3 (clean with both
excludes, dirty with either dropped) holds here.

The executor's unanticipated ordering finding is real and the fix is right:
`stage_memory_gitlink`'s `git commit -qm "memory gitlink"` commits the whole
index, so staging the `.claude` frame first would fold it into `HEAD` and
re-vacuate the `.claude` half. Called in the order memory-then-claude, the
staged `.claude` diff is genuinely uncommitted when `run minor` executes —
confirmed by the `.claude` mutation still going red.

**Changed:** nothing.

### (d) M4 — ten refusals assert status, side-effect absence and `gh`

Contract met on the count and the shape. `assert_gh_untouched <label>` exists
with the between-runs caveat in its comment; the nine
`=== preflight refusals ===` scenarios and "resume, no tag anywhere" all carry
`rc`, a tag refutation and a `gh` assertion; "no dist tag: names it" got its
missing `rc` in the same pass, as instructed. The three scenarios sharing one
sandbox (bad argument, bad option, extra argument) read `$GH_LOG` between runs,
not after all three.

**Changed — three assertions strengthened.** Each was green under every mutation
available to it, i.e. could not fail:

1. `tag squatting` — see adjudication 1 below: `assert_contains` on the log
   replaced by `assert_eq` on the whole log.
2. `malformed VERSION` — `refute_tag v0.2.0` → `refute_tag v0.3.0`. `'0.2'`
   reads as `maj=0 min=2 pat=''`, so a minor bump escaping the shape guard tags
   **v0.3.0**; v0.2.0 is a tag no path in the script creates from this fixture.
   Comment added, mirroring the treatment the executor already gave
   `hand-written bump` (which correctly names v0.3.0).
3. `resume, no tag anywhere` — `refute_tag v0.2.0` → `refute_tag v0.1.0`.
   `--resume` never performs a bump, so v0.2.0 is not a tag this scenario's code
   path could produce under any defeat; v0.1.0 is the version the resume is
   about and the tag the fixture deliberately deleted from both places. Neither
   name is falsifiable by a current path (only `bump_commit_tag` tags, and
   resume never calls it) — this scenario's real side-effect pin is its
   `assert_gh_untouched`, which *is* falsifiable, shown below. The rename is for
   truthfulness, not power.

Evidence that 1 and 2 are now discriminating rather than decorative, under the
mutation named in adjudication 2 — both lines are new, neither appeared before
the fix:

```
FAIL: malformed VERSION: tag v0.3.0 should not exist
FAIL: tag squatting: gh reached only for the prior-release check: expected 'release view v0.1.0', got 'release view v0.1.0
```

One further weak assertion I deliberately left: `zero-padded VERSION`'s
`refute_tag v0.2.0`. With `0.08.0` a defeated shape guard crashes in
`$((08 + 1))` before any tagging, so **no** tag name is falsifiable there.
Renaming it would trade one unfalsifiable name for another; left as the cheap
belt-and-braces the runbook asked for, noted here rather than churned.

## Adjudication 1 — tag squatting cannot assert `gh` untouched

**Confirmed, and the substitution is sound — after the strengthening above.**

The ordering claim holds against the source: `release_preflight` runs the drift
check, then `require_prior_release_published`, whose `gh release view "$prior"`
succeeds on this fixture's properly published v0.1.0, and only then the
`tag $t already exists` loop fires. `$GH_LOG` is legitimately non-empty.
`assert_gh_untouched` there would be an assertion of something false, and the
executor was right to refuse to force it.

**But the replacement as committed weakened the property.** M4 exists to pin
that a refusal's `gh` side effects are fully accounted for.
`assert_contains "$(cat "$GH_LOG")" "release view v0.1.0"` accounts for one call
and is silent about every other line in the log — a `release create` logged
after the read would satisfy it. Demonstrated: under the `die`-defanging
mutation the squatting scenario's log grows to three lines including
`release create v0.2.0`, and the committed assertion stayed **green**.

Fixed by pinning the whole log instead of a needle in it:

```
assert_eq "$(cat "$GH_LOG")" "release view v0.1.0" \
    "tag squatting: gh reached only for the prior-release check"
```

The stub logs one `"$*"` line per invocation, so equality is exact and the
scenario now asserts what `assert_gh_untouched` asserts everywhere else: nothing
but that one read-only call reached `gh`. It goes red under the mutation (quoted
above) and green unmutated. The comment was extended to say why the whole log,
not a needle.

**Verdict: the executor's finding is correct and its direction is right; the
form it landed in was a weakening, now repaired in place.**

## Adjudication 2 — "three refusal scenarios must go red"; only one did

**The executor's count is correct. The gate as written is genuinely
under-powered, and I am naming the mutation it should have been.**

Re-running the runbook's mutation (`common_preflight`'s dirty-tree branch prints
to stderr and falls through) reproduces the report exactly:

```
FAIL: dirty tree: exit status: expected '1', got '0'
FAIL: dirty tree: tag v0.2.0 should not exist
FAIL: dirty tree: gh was touched (release view v0.1.0
3 self-release check(s) failed
```

One scenario, three assertions. The executor's empirical method (instrumenting
every `common_preflight` invocation and reading which trees were dirty) is the
right way to establish that, and reporting the miscount instead of manufacturing
two more dirty-tree scenarios was the right call.

**Why it is nonetheless under-powered.** That mutation defeats one guard, so it
can only exercise the assertions of the one refusal that guard produces. It
proves the three assertion *forms* discriminate; it says nothing about the other
nine scenarios' twenty-seven new assertions, and two of them were in fact
incapable of failing (adjudication 1, and `malformed VERSION`) while the gate
reported success.

**The mutation the gate needed**, which I ran here:

> In `scripts/self-release.sh`, defang `die` itself —
> `die() { printf 'error: %s\n' "$1" >&2; return 0; }` — so every refusal prints
> and falls through instead of exiting.

Under it, **41** checks fail, covering nine of the ten refusals on their new
assertions: `rc` goes red in all ten; the tag refutation in `dirty tree`,
`wrong branch`, `hand-written bump`, `tag squatting`, `extra argument` (and,
after my fix, `malformed VERSION`); `assert_gh_untouched` in `dirty tree`,
`wrong branch`, `malformed VERSION`, `hand-written bump`, `bad argument`,
`bad option`, `extra argument` and `resume, no tag anywhere`. One mutation, one
run, and it is what surfaced the two vacuous assertions the runbook's gate let
through. `zero-padded VERSION` is the only refusal it cannot reach, for the
`$((08))` reason above.

This is an escalation, not a fix: the runbook's Mutation-gate text for part (d)
is closed and dated, and it is the *gate specification* that is weak, not the
delivered code — which now passes the stronger gate.
**Recommendation for Phase 3:** where an item sweeps a property across N
scenarios, its mutation gate should defeat the refusal mechanism shared by all N
(here, `die`), not one guard among them. Items 3.1 and 3.2 are both sweeps of
this shape.

## Mutation-gate evidence assessment

Every block quoted in `reports/item-2-1.md` reproduced here from the source
mutation, character for character in parts (a), (b) and (d), and semantically in
(c) (same single failing line under each of the two mutations). No quoted output
is attributed to an assertion that does not produce it. Labels in the quoted
failures match the labels in the committed file.

No mutation rode into the commit: `git show c5a4196 --stat` touches
`tests/self-release-test.sh` only, and `scripts/self-release.sh` is untouched
across the phase diff. Every mutation I applied during this review was reverted
and verified with `git diff --quiet -- scripts/self-release.sh`; the tree holds
no mutation now.

## UNFIXABLE

None. The one escalation (adjudication 2) is a defect in a closed runbook's gate
specification, not an unfixable defect in the deliverable.

## Files modified

- `/Users/david/code/claude-plugin-dev/tests/self-release-test.sh` — four edits:
  `assert_eq` on the whole `$GH_LOG` for tag squatting (+comment);
  `refute_tag v0.3.0` for malformed VERSION (+comment); `refute_tag v0.1.0` for
  resume-no-tag (+comment); the `git show … && fail` rewritten as
  `if … then fail; fi`.

Nothing else. Left untouched and uncommitted, as instructed:
`.claude/handoff-task.md`, `.claude/handoff-todo.md`.

## Verification after the fixes

- `bash tests/self-release-test.sh` → `self-release.sh: ok`
- `shellcheck tests/self-release-test.sh` → clean
- `just precommit` → green, all eight suites (`ok` on the final line)
- `git status --short` → only `M tests/self-release-test.sh` beyond the two
  pre-existing staged handoff files. No commit made.
