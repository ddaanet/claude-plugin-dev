# Cluster B — test suites

The seven test-suite items of the deliverable-review fix pass. Split out of
`outline.md`, which carries the scope, clusters A and C, the ordering rules and
the gate; read that first. Verdicts and their evidence are in
`proof-verdicts.md`.

Every item here is `craft:test-discipline`'s core move: make the fixture carry
the discrimination, so the assertion has something to be wrong about. Each names
the mutation that must go red.

### B1 — the dist split does not discriminate the tag from `HEAD` (Major 1)

`tests/self-release-test.sh:210-222`. `ensure_dist_tag` runs before
`push_branch`, so the `block_push` + `run minor` setup leaves `dist-v0.2.0`
already created locally; the `--resume` takes the short-circuit at
`self-release.sh:183-186` and `git subtree split` never runs. The happy path
(`:143-162`) splits when `HEAD` *is* the tagged commit, so it cannot
discriminate either. Nothing in the suite pins the tree of the ref every
consumer vendors.

**Change:** land the later work *inside* `toolkit/`, delete the local dist tag
before the resume — the dead-origin scenario at `:325` already does exactly this
— then assert `git show dist-v0.2.0:<later-file>` fails and
`git ls-tree --name-only dist-v0.2.0` omits it. The `docs.md` commit then
contributes no discrimination: drop it, or say why it stays.

**Rewrite the comment — it is false, not merely weak.** Its fallback claim,
"What it proves is that the split ran against the tagged commit at all", is
wrong: the split did not run. `ensure_dist_tag` precedes `push_branch` in the
main flow, so `block_push` + `run minor` leaves the local dist tag in place and
the resume returns at `already created locally`; the surviving assertion reads a
tag built in the *first* invocation, where `HEAD` and the tag coincided. A
comment asserting coverage the scenario lacks is what stops the next reader
looking.

**Mutation:** `scripts/self-release.sh:203` `"$tag"` → `HEAD`. Today the whole
suite stays green under it.

### B2 — the clean-check exemptions are untested (Major 3)

`tests/self-release-test.sh:267-271`. The handoff frame is written
**untracked**, and `self-release.sh:56` is
`git diff --quiet HEAD -- . ':(exclude).claude' ':(exclude)memory'`, which sees
tracked paths only. The `memory` half is never constructed at all.

**Change, `.claude/`:** adopt the commit-then-rewrite-and-stage shape of
`tests/release-test.sh:179-192` (`stage_handoff_frame`), whose comment already
documents why untracked does not reach the check. That one suite states the rule
while its sibling does not is `examine-evidence-drift` between co-maintained
surfaces.

**Rewrite the comment.** It reads "# .claude/ and memory/ are excluded from that
check, the way this repo needs" — claiming both halves are covered when only
`.claude/` is attempted, vacuously, and `memory` is never constructed. Same
false-coverage class as B1.

**Change, `memory`:** construct a gitlink resting off `HEAD`'s recorded sha —
the resting state gitlore leaves. This needs a real submodule in the fixture;
the suite already drops the leaked git environment at `:17`
(`unset $(git rev-parse --local-env-vars)`), so the submodule calls are safe
there.

**Probed end to end 2026-09-18 against git 2.47.3 — feasible and ~6 lines**, so
this is no longer the heaviest item in cluster B.
`-c protocol.file.allow=always` is **required**, not optional: a plain
`git submodule add <local-path>` fails with
`fatal: transport 'file' not allowed`, and the setting is read by the child
*clone*, so fixture-repo config cannot supply it. With it, the shape is: init a
`sub` repo with two empty commits, add it as `memory`, commit the gitlink at the
second, then `git -C memory checkout` the first.
**Say where that `sub` repo lives:** `new_sandbox` rebuilds `$repo` on every
call, so its upstream is either created once outside the sandbox or per-sandbox.
That is the one detail an implementer cannot infer, and the wrong choice yields
a fixture that works alone and breaks when a scenario is inserted ahead of it.
Both outcomes confirmed on that fixture — the exempted form
(`git diff --quiet HEAD -- . ':(exclude).claude' ':(exclude)memory'`) stays
clean, and dropping `':(exclude)memory'` reports dirty, so the mutation goes
genuinely red.

**Mutations:** drop `':(exclude).claude'` → red; drop `':(exclude)memory'` →
red. Both stay green today.

### B3 — ten refusals assert a message and nothing else (Major 4)

`tests/self-release-test.sh:231-309`. No exit status, no absence of a side
effect, and `$GH_LOG` is never asserted empty anywhere in the suite — so no
refusal is pinned as having happened before `gh` was reached. Measured: five
`$GH_LOG` mentions here — definition, export, truncation, two *positive*
assertions — against 38 `cat "$GH_LOG"` reads in `tests/release-test.sh`.

**Ten, not nine.** Nine is the `=== preflight refusals ===` block alone, but
`:231-309` also spans `=== resume refusals ===`, where "resume, no tag anywhere"
has the identical defect: hint and remedy needles, no `rc`, no tag check, no
`$GH_LOG`. Fix it with the rest, or the cited range silently claims a scenario
nobody touches. Same pass: "no dist tag: names it" asserts `refute_tag v0.2.0`
but no `rc`.

**Change:** add an `assert_gh_untouched` helper and apply `rc`, `$GH_LOG` empty
and tag-absence to all ten. Note `$GH_LOG` is truncated per `new_sandbox`
(`:104`), so the pair at `:262-271` sharing one sandbox needs the log read
between runs, not after both.

**Mutation:** make `common_preflight`'s dirty-tree branch print to stderr and
fall through instead of `die`. `:262-265`, `:273-276` and `:296-301` all stay
green today while the release proceeds.

### B4 — two `release-test.sh` refusals under-assert (Minor 3)

`tests/release-test.sh:935-947` and `:949-964` assert `rc` and message needles
but not tag absence, `$GH_LOG`, origin `main` or the marketplace, against the
blanket rule the executed `outline.md:172-173` states. Bring both up to the
shape the rest of that file uses — `hand-advanced-lost-tag`, three lines above,
already applies all four properties.

**Phrase the tag property as a set comparison, not a named refutation.** Which
tag the code would create is itself under test here, so naming one invites a
vacuous pass — scenario 1 leaves both `v1.2.4` and `v1.11.1` plausible, and
scenario 2's origin already holds `v1.2.4`. Assert instead that
**the local tag set is unchanged from the fixture**.

### B5 — two `version-guard-test.sh` gaps (Minors 4 and 6)

- `:355` — `tagless_sysmsg` reads the `guard_out` left by the run at `:315-317`,
  forty lines and two assertion blocks earlier, with no note saying so. The
  deliberate `$reason` reuse at `:324-332` *is* documented. Either re-invoke the
  hook or add the note; a scenario inserted between silently retargets a
  byte-identity comparison.
- `:374-381` — the `vnext` half of slice 4 omits **two** assertions, not one:
  `assert_no_escape_hatch`, which slice 2 (`:349`) and the tagged case (`:365`)
  both call, and `assert_not_contains "$reason" "just release"`. The second
  applies because the `vnext` fixture takes the *same initial-release branch* as
  the no-tags case — the block asserts "never been released" to prove it — and
  the no-tags site documents that property as asserted there alone only because
  the *steady-state* message names the recipe legitimately. The `vnext` reason
  is not steady-state. Add both.

### B6 — no allow scenario touches a git fixture (Minor 5)

Every `assert_allow` in `tests/version-guard-test.sh` runs against `$proj`,
which is deliberately not a repo. The executed `outline.md:130`'s property — the
tag listing runs only after the deny is established — is therefore unpinned.

**A bare `assert_allow` cannot pin it — the mutation would stay green.** The
listing block absorbs every outcome into a variable by construction, never exits
non-zero, writes nothing to stdout and suppresses stderr. So hoisting it above
`version-guard.sh:80`
(`[[ -z "$proposed" || "$proposed" == "$current" ]] && exit 0`) leaves both
fixtures allowing, byte-identical. The property is about *work ordering*, which
the decision channel cannot observe.

**Change:** add one allow scenario against a git fixture — an edit to
`plugin.json` that does not change `.version`, in `$git_tagged_proj` — driven by
a **recording `git` stub**: a wrapper on `PATH` that logs its arguments and
delegates to the real binary, the `guard_stub127_dir` idiom already in this
file. Assert the log holds no `tag --list`. The git fixture is still required:
against `$proj` the stub would record nothing either way.

**Mutation:** hoist the listing above `version-guard.sh:80`. Red against the
stub log; green against any assertion on the decision alone.

### B7 — `assert_contains` means two different things (Minor 8)

`tests/version-guard-test.sh:34-47` implements it as a literal glob
(`[[ "$1" != *"$2"* ]]`); `release-test.sh:30`, `self-release-test.sh:34` and
`update-plugin-dev-test.sh:32` use `grep -q --`, a BRE. Same name, same
signature, different semantics, in a repo that deliberately duplicates the
harness per file.

**Change:** move `version-guard-test.sh` to the `grep -q --` form. No needle
currently produces a false pass either way, but re-check every needle in that
file under BRE before landing — the dots in `1.2.3 -> 9.9.9` become any-char and
still match, which is the point to verify rather than assume.
`self-release-test.sh:207-208`'s `": pushed$"` anchors already depend on the
grep form, so this converges the four suites rather than diverging them further.

**Scope, counted 2026-09-18 — 20 call sites, not a 447-line rewrite.** Nine
`assert_contains` and eleven `assert_not_contains`, so the work is two helper
bodies plus a read-through of twenty needles. Across all twenty the only
BRE-live characters are the dots in `9.9.9` and in `settings.json`; both widen
to any-char and both still match, so no needle needs escaping. That is what
moved this from "record the divergence as a bound" to "converge now" — the
earlier framing costed it against the file's length rather than its call count.

**The two assertion kinds carry opposite risks.** BRE widening makes
`assert_contains` risk a **false pass** — silent, the defect this item prevents.
It makes `assert_not_contains` *stricter*, so the risk there is a
**false failure** — loud on the first run. Spend the careful read on the nine
positive needles; the eleven negative ones report themselves.

**Converge the failure output too**, or one suite keeps a different diagnostic
shape — the same complaint one level down. Not a conflict: the glob form's
comment constrains what the caller passes as the haystack, not the matcher, and
survives unchanged.
