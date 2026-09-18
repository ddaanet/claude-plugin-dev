# Proof verdicts — Cluster B

The seven Cluster B verdicts from the `/edify:proof` pass, split out of
`proof-verdicts.md` for length and paired with the specs in
`cluster-b-test-suites.md`. The verdict table, the protocol and the auto-accept
caveat are in `proof-verdicts.md`.

## Item 5 — B1 — **revise**

Premise verified and worse than stated. Step order confirmed in the main flow:
`ensure_dist_tag` at line 285, `push_branch` at 286. So `block_push` +
`run minor` does create `dist-v0.2.0` locally before the push fails, and the
`--resume` returns at `note "dist tag $dist_tag: already created locally"`.
`git subtree split` never executes during the resume.

**Edit 1 — the existing comment is false, not merely weak.** It reads: "Split
from the tag, not HEAD: the dist tree must not carry later work, and would not
even see it here -- docs.md is outside toolkit/. What it proves is that the
split ran against the tagged commit at all." The split did not run against the
tagged commit; it did not run. The surviving assertion
`git show dist-v0.2.0:VERSION` reads a tag built during the *first* invocation,
where `HEAD` and the tag were the same commit. The comment is candid about one
limitation and wrong about the claim it retreats to — the failure
`craft:test-discipline` rates worse than an absent test, because an asserted
coverage claim is what stops the next reader from looking. B1 currently reads as
"add assertions"; it must also rewrite that comment, and saying so in the item
keeps it from being dropped as incidental.

**Edit 2 — note that `docs.md` becomes redundant.** Once the later work lands
inside `toolkit/`, the outside-`toolkit/` commit contributes no discrimination.
Either drop it or state why it stays, rather than leaving two commits where one
carries the property.

Fix mechanics otherwise check out. The dead-origin scenario does already do the
`git -C "$repo" tag -d dist-v0.2.0` deletion the fix reuses, and under the
`"$tag"` → `HEAD` mutation the split picks up the in-`toolkit/` file, so the
proposed assertions genuinely discriminate.

## Item 6 — B2 — **revise**

Premise fully verified. The scenario writes `.claude/handoff-task.md`
**untracked**, and `git diff --quiet HEAD -- .` sees only tracked paths, so
`assert_eq "$rc" 0` passes for a reason unrelated to the exclusion and would
keep passing with `':(exclude).claude'` deleted. `release-test.sh`'s
`stage_handoff_frame` already has the correct shape and already explains why in
its own comment — "Staged, not merely written, because `git diff HEAD` sees only
tracked paths — an untracked frame never reached the check in the first place."
One suite knows this and its sibling does not: `examine-evidence-drift` between
co-maintained surfaces.

My human partner's decision to build the submodule fixture is folded in and is
not reopened here.

**Edit 1 — the comment claims coverage for both halves.** The line above the
scenario reads "# .claude/ and memory/ are excluded from that check, the way
this repo needs." Only `.claude/` is attempted, vacuously; `memory` is never
constructed. Same failure class as B1 — the asserted coverage claim is what kept
the gap invisible. The item must say that comment is rewritten, not only that
assertions are added.

**Edit 2 — say where the submodule's upstream repo lives.** The fixture needs a
second repo for the gitlink to point at, and `new_sandbox` rebuilds `$repo` on
every call. The item does not say whether that upstream is created once outside
the sandbox or per-sandbox. It is the one detail an implementer cannot infer,
and getting it wrong yields a fixture that works in isolation and breaks as soon
as a scenario is inserted ahead of it.

Everything else holds: `-c protocol.file.allow=always` is required — confirmed
by probe and by the `git-protocol-file-allow` memory entry, since the child
*clone* reads the setting and fixture-repo config cannot supply it — the
`unset $(git rev-parse --local-env-vars)` at `:17` does make the submodule calls
safe, and dropping either exclusion goes red.

## Item 7 — B3 — **revise**

The drift claim is verified and exact. `self-release-test.sh` touches `$GH_LOG`
five times: the definition, the export, the truncation, and two *positive*
assertions ("happy: gh called", "resume: gh called"). It never asserts it empty.
`release-test.sh` reads `cat "$GH_LOG"` at 38 sites. The `new_sandbox`
truncation caveat also holds — the dirty-tree and `.claude` scenarios share one
sandbox, so the log must be read between the two runs rather than after both.

**Edit — the count and the cited range disagree.** "Nine" is exactly the
`=== preflight refusals ===` block: dirty tree, wrong branch, malformed VERSION,
zero-padded VERSION, hand-written bump, tag squatting, bad argument, bad option,
extra argument. But the item cites `:231-309`, which reaches back across the
`=== resume refusals ===` block, where "resume, no tag anywhere" carries the
identical defect — two `assert_contains` on hint and remedy, no `rc`, no tag
check, no `$GH_LOG`. It is a tenth instance, inside the quoted range and outside
the count.

Worth one clause in the same edit rather than an item of its own: "no dist tag:
names it" asserts `refute_tag v0.2.0` but no `rc` — partially under-asserted,
again inside the cited range.

Resolve it either way — narrow the range to the preflight block and say nine, or
keep the range and say ten. Leaving both is how the resume scenario gets missed:
an implementer works the block the count points at, while the citation silently
claims a scenario nobody touches.

## Item 8 — B4 — **revise**

Both scenarios verified as under-asserting. The version-sort one asserts `rc`,
that `v1.11.0` is named and that `v1.10.0`/`v1.9.0` are not. The
probe-before-drift one asserts `rc`, two message needles and two absence
needles. Neither checks tag absence, `$GH_LOG`, origin `main` or the
marketplace. The blanket rule at the executed `outline.md:172-173` is quoted
accurately — and that citation is into a frozen dated artifact, so it correctly
keeps its line numbers under C4's exception. The scenario immediately above the
two (`hand-advanced-lost-tag`) already applies all four properties, so the
target shape is three lines away.

**Edit — phrase the tag property as a set comparison, not a named refutation.**
"Bring both up to the shape the rest of that file uses" leaves tag-absence
ambiguous in precisely these two scenarios, because which tag the code would
create is the thing under test. Scenario 1 pushes `v1.9.0`, `v1.10.0`, `v1.11.0`
to origin and loses them locally while the manifest sits at `1.2.3`, so
`refute_tag v1.2.4` and `refute_tag v1.11.1` are both plausible readings and the
wrong pick yields an assertion that passes vacuously. Scenario 2 has the mirror
problem: origin already holds `v1.2.4`, so refuting that name tests the fixture
rather than the refusal.

State it as *the local tag set is unchanged from the fixture*. That is what the
refusal actually promises, it cannot pass vacuously, and it avoids having to
predict a bump the code never reaches.

## Item 9 — B5 — **revise**

Both gaps verified. `tagless_sysmsg="$(jq -r '.systemMessage' <<<"$guard_out")"`
does read the `$guard_out` left by the run thirty lines and two assertion blocks
earlier; Slice 3's comment explains the *purpose* of the byte-identity
comparison but never says the payload is stale, while the `$reason` reuse
immediately above it is explicitly documented. And Slice 4's `vnext` half does
omit `assert_no_escape_hatch`, which Slice 2 and the tagged case both call.

**Edit 1 — Slice 4 drops two assertions, not one.** The `vnext` half also omits
`assert_not_contains "$reason" "just release"`. The `vnext` fixture takes the
*same initial-release branch* as the no-tags case — the block asserts "never
been released" to prove exactly that — and the no-tags site's comment says the
no-recipe property is asserted "over the no-tags reason alone" only because the
steady-state message names the recipe legitimately. The `vnext` reason is not
steady-state, so the property applies and is simply unchecked. B5 names one
missing assertion where there are two.

**Edit 2 — flag the collision with C4.** The stale citations C4 repairs,
`release.sh:446-455` and `release.sh:456-460`, sit inside the very comment block
B5 edits. Two items rewriting the same twelve lines in separate commits will
conflict. The ordering rule belongs in the Dependencies section; carried to item
13 rather than duplicated here.

## Item 10 — B6 — **revise**

Premise confirmed: all three `assert_allow` sites — `Edit-unrelated`,
`unrelated-file`, `bsd-realpath-unrelated` — run against `$proj`, which is
deliberately not a repo.

**The named mutation cannot go red.** The mutation is "hoist the listing above
`version-guard.sh:80`", where line 80 is
`[[ -z "$proposed" || "$proposed" == "$current" ]] && exit 0`. Every outcome of
the listing block is absorbed into a variable by construction — the
`git tag --list` runs as an `if` condition setting `listing_failed` to 0 or 1,
with stderr redirected to `/dev/null`. Nothing exits non-zero, nothing reaches
stdout, nothing reaches stderr. So under the hoist, in `$proj` the listing
fails, sets `listing_failed=1`, and the early exit still fires — allow,
byte-identical; in `$git_tagged_proj` the listing succeeds and the early exit
still fires — allow, byte-identical. A new `assert_allow` stays green under the
mutation exactly as the existing three do. The property is about
*work ordering*, and ordering is not observable through the decision channel.

**Edit — keep the scenario, replace the mechanism.** Use a recording `git` stub
instead of a bare `assert_allow`: a `git` wrapper on `PATH` that appends its
arguments to a log and delegates to the real binary — the `guard_stub127_dir`
idiom already lives in this file — run the unrelated-field edit against
`$git_tagged_proj`, and assert the log holds no `tag --list`. That pins the
ordering property directly and does go red on the hoist. The git fixture is
still required for B6's own stated reason: against `$proj` the stub would record
nothing either way.

## Item 11 — B7 — **revise**

Divergence confirmed verbatim: `version-guard-test.sh` uses
`[[ "$1" != *"$2"* ]]`, the other suites use
`! printf '%s' "$1" | grep -q -- "$2"`. And `": pushed$"` genuinely depends on
BRE anchoring, so converging toward `grep` is the direction that keeps existing
needles working. My human partner's decision to converge now, and the
20-call-site scoping folded into the outline, stand.

**Edit 1 — distinguish the two risk directions; they are opposite.** For
`assert_contains`, BRE widening risks a **false pass** — silent, and precisely
the defect this item exists to prevent. For `assert_not_contains`, widening
makes the assertion *stricter*, so the risk is a **false failure** — loud, and
self-announcing on the first run. The nine positive needles need the careful
read; the eleven negative ones report themselves. "Re-check every needle under
BRE" spreads equal attention over both and understates where it matters.

**Edit 2 — converge the failure output, or say you are not.** The glob form
reports `"$3: expected to contain '$2', got '$1'"` with the haystack inline; the
grep form reports `"$3: output did not contain '$2'"` and prints the haystack in
a delimited stderr block. Swapping only the matcher leaves one suite with a
different diagnostic shape — the same "same name, different behaviour" complaint
one level down.

Recorded as *not* a conflict: the glob implementation's comment — "Match against
a specific extracted field … never the whole payload blob" — constrains what the
caller passes as the haystack, not the matcher. It survives the conversion
unchanged.
