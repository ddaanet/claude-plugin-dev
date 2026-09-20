# Runbook — Phases 2 and 3: test-suite discrimination

The six `general` items of the deliverable-review fix pass, split out of
`runbook.md` for length. That file carries the requirements mapping, Phase 1,
Phase 4 and the gate, and states the phase-typing deviation these items execute;
read it first. The design is `cluster-b-test-suites.md`, and the evidence behind
it is `proof-verdicts-cluster-b.md`.

**Why `general` and not `tdd`, the argument the hub states as a conclusion.**
Each item here strengthens a fixture whose new assertions pass against
*unchanged* production code, so a `tdd` dispatch's RED step would have nothing
to fail on and would manufacture a fake red. The discrimination is proven
instead by applying the item's named **Mutation gate** — the edit, the assertion
that must fail under it, the revert — which the executor runs and reports before
committing. No commit carries a mutation.

**A gate report quotes its evidence; "gate passed" is not a report.** `general`
gives up the separate RED-phase review a `tdd` item gets, so the agent that
wrote an assertion is also the one that says it can fail. For every gate below,
the item's report quotes the failing assertion's output line under the mutation,
and the suite's closing green line after the revert. A reviewer can check quoted
output against the assertion's label; it cannot check a bare claim. Decided at
`/proof`, 2026-09-19, as the condition for keeping the `general` typing.

## Phase 2: `tests/self-release-test.sh` (type: general)

One file, **one item in four lettered parts**. They were four items until the
consolidation pass. `outline.md` Dependencies rule 5 asks for one agent per file
rather than one per item, and `/orchestrate` composes one dispatch per *item*
and names it `item-N-M` — so four items meant four fresh agents, each
re-orienting in the same 336-line suite. One item is the only shape that
delivers rule 5.

Each part keeps its own requirement, its own change and its own
**Mutation gate**, stated separately — the gates are the correctness criterion
of this phase and none is merged into another. The item's single commit carries
no mutation: each part reverts its own before the next part begins.

**One commit for the four parts**, since `/orchestrate` commits once per general
item. Git-history granularity is what the consolidation traded for the single
agent; review granularity is unaffected, because the phase-boundary corrector
reads the whole phase diff either way.

**Run the parts in the order given.** Part (c) rewrites one of the ten refusals
part (d) then sweeps — three of the overlaps `outline.md` Dependencies names sit
inside this item, and (c) before (d) is the one that matters: a sweep landing
first has its new assertions rewritten out from under it, and nothing fails when
that happens.

- **Item 2.1:** `tests/self-release-test.sh` — four fixtures that currently
  cannot fail.
  - Requirements: N7 (a), M1 (b), M3 (c), M4 (d)
  - Depends on: Item 1.3 — serialization (same file), and consumption: 1.3's
    `Also update:` rewrites the dist-tag-squatting scenario's comment, and that
    scenario is one of the ten part (d) sweeps.
  - Model: sonnet
  - **(a) N7 — the happy path's `tree left dirty` check sees untracked
    leftovers.** The check is
    `git -C "$repo" diff --quiet HEAD || fail "happy: tree left dirty"`, which
    reads tracked paths only. Extend it to also assert no untracked path
    survives the release — `git -C "$repo" ls-files --others --exclude-standard`
    empty — and note in the comment why `diff --quiet HEAD` alone is
    insufficient, the way `stage_handoff_frame` in `tests/release-test.sh`
    already documents it.
  - **(a) Not in the outline, kept at `/proof`:** carried from review finding
    N7, which no outline item claims. The proof gate of 2026-09-19 kept it; it
    is in scope and not an open choice at execution time. One thing the gate did
    not establish: whether the happy-path fixture already leaves an untracked,
    non-ignored path. If the new assertion fails against *unchanged* code, that
    is a fixture leftover to clean up and report, not a reason to weaken the
    assertion.
  - **(a) Mutation gate:** make `bump_commit_tag` in `scripts/self-release.sh`
    leave a stray untracked file in the repo root. The new assertion must fail;
    the existing `diff --quiet HEAD` must not. Revert before part (b).
  - **(b) M1 — the dist-split scenario discriminates the tag's tree from
    `HEAD`'s.** `ensure_dist_tag` runs before `push_branch`, so the `block_push`
    + `run minor` setup leaves `dist-v0.2.0` already created locally and the
    `--resume` short-circuits at `already created locally` — `git subtree split`
    never runs. Land the later work *inside* `toolkit/`, delete the local dist
    tag before the resume (the dead-origin scenario later in the file already
    does exactly this), then assert `git show dist-v0.2.0:<later-file>` fails
    and `git ls-tree --name-only dist-v0.2.0` omits it. The `docs.md` commit
    then contributes no discrimination: **drop it.**
  - **(b) Rewrite the comment** — it is false, not merely weak. Its fallback
    claim, "What it proves is that the split ran against the tagged commit at
    all", is wrong: the split did not run, and the surviving assertion reads a
    tag built in the *first* invocation, where `HEAD` and the tag coincided.
  - **(b) Mutation gate:** `scripts/self-release.sh`'s `git subtree split`
    argument `"$tag"` → `HEAD`. The new `git show`/`ls-tree` assertions must
    fail; today the whole suite stays green under it. Revert before part (c).
  - **(c) M3 — the clean-check exemptions are actually constructed.** For
    `.claude/`: the frame is written **untracked**, and `common_preflight`'s
    check is
    `git diff --quiet HEAD -- . ':(exclude).claude' ':(exclude)memory'`, which
    sees tracked paths only — so the scenario is vacuous. Adopt the
    commit-then-rewrite-and-stage shape of `stage_handoff_frame` in
    `tests/release-test.sh`, whose comment already documents why untracked does
    not reach the check. Part (b)'s scenario is the resume-after-later-work
    block and this one is inside `=== preflight refusals ===`; they do not
    overlap.
  - **(c) `memory`:** construct a gitlink resting off `HEAD`'s recorded sha —
    the resting state gitlore leaves. Init a `sub` repo with two empty commits,
    `git -c protocol.file.allow=always submodule add` it as `memory`, commit the
    gitlink at the second, then `git -C memory checkout` the first.
    `-c protocol.file.allow=always` is **required**, not optional: a plain
    `submodule add <local-path>` fails with
    `fatal: transport 'file' not allowed`, and the setting is read by the child
    *clone*, so fixture-repo config cannot supply it. The suite drops the leaked
    git environment near its top (`unset $(git rev-parse --local-env-vars)`), so
    the submodule calls are safe there.
  - **(c) The `sub` upstream is built per-sandbox, inside `$sandbox`**, not once
    outside it. `new_sandbox` rebuilds `$repo` on every call, so a shared
    upstream leaves state crossing scenario boundaries — a fixture that works
    alone and breaks when a scenario is inserted ahead of it. State that reason
    in the fixture's comment.
  - **(c) Rewrite the comment.** It currently reads "`.claude/` and `memory/`
    are excluded from that check, the way this repo needs" — claiming both
    halves are covered when only `.claude/` is attempted, vacuously, and
    `memory` is never constructed at all.
  - **(c) The fixture's contract**, confirmed on the 2026-09-18 probe against
    git 2.47.3: the `memory` fixture leaves
    `git diff --quiet HEAD -- . ':(exclude).claude' ':(exclude)memory'` clean
    and the same command without `':(exclude)memory'` dirty.
  - **(c) Mutation gate:** drop `':(exclude).claude'` → the `.claude` half must
    go red; drop `':(exclude)memory'` → the `memory` half must go red. Both stay
    green today. Revert both before part (d).
  - **(d) M4 — all ten refusals assert status, side-effect absence and `gh`
    untouched.** Add an `assert_gh_untouched <label>` helper — fails unless
    `$(cat "$GH_LOG")` is empty, called after each refusal and before the next
    `run` — and apply `rc`, `$GH_LOG` empty and tag absence to all ten refusals.
    **Ten, not nine**: the `=== preflight refusals ===` block is nine, and
    `=== resume refusals ===` carries "resume, no tag anywhere" with the
    identical defect — hint and remedy needles, no `rc`, no tag check, no
    `$GH_LOG`. In the same pass, "no dist tag: names it" asserts
    `refute_tag v0.2.0` but no `rc`. `$GH_LOG` is truncated per `new_sandbox`,
    so the pair that shares one sandbox needs the log read *between* runs, not
    after both. Part (c)'s rewritten scenario is one of the ten, and so is the
    squatting refusal Item 1.3's comment update targets.
  - **(d) Mutation gate:** make `common_preflight`'s dirty-tree branch print to
    stderr and fall through instead of `die`. Three refusal scenarios must go
    red; all three stay green today while the release proceeds. Revert before
    committing.

## Phase 3: two suites and the citation gate (type: general)

Item 3.1 is on a different file from 3.2–3.4 and is independent of them. Items
3.2–3.4 are strictly sequential on `tests/version-guard-test.sh`. Item 3.5 runs
last in the phase: it edits comments in both suites and in `toolkit/release.sh`.

- **Item 3.1:** `tests/release-test.sh` — two refusals assert the four
  properties the rest of the file asserts.
  - Requirements: N3
  - Depends on: Item 1.2 (serialization — same file)
  - Model: sonnet
  - Change: the two scenarios assert `rc` and message needles but not tag
    absence, `$GH_LOG`, origin `main` or the marketplace. Bring both up to the
    shape `hand-advanced-lost-tag` three lines above already uses.
    **Phrase the tag property as a set comparison, not a named refutation** —
    which tag the code would create is itself under test, so naming one invites
    a vacuous pass: scenario 1 leaves both `v1.2.4` and `v1.11.1` plausible, and
    scenario 2's origin already holds `v1.2.4`. Assert that the local tag set is
    unchanged from the fixture.
  - Mutation gate: make the refusal these two scenarios exercise `note` and fall
    through instead of `die`. Both must go red on the new properties. Revert
    before committing.

- **Item 3.2:** `tests/version-guard-test.sh` — the stale `guard_out` read and
  the `vnext` half's two missing assertions.
  - Requirements: N4, N6
  - Model: sonnet
  - Change, N4: `tagless_sysmsg` reads the `guard_out` left by a run forty lines
    and two assertion blocks earlier, with no note saying so — unlike the
    deliberate `$reason` reuse just above it, which *is* documented.
    **Re-invoke the hook** against `$git_proj` immediately before capturing
    `tagless_sysmsg`, and say in the comment that the capture is deliberately
    fresh. The outline offered "re-invoke or add the note"; this runbook takes
    re-invoke, because a note only discloses the hazard while a fresh run
    removes it, and the cost is one more hook invocation. A scenario inserted
    between would otherwise silently retarget a byte-identity comparison.
    Re-invoke was confirmed at `/proof`, 2026-09-19.
    **Say in the comment why the two neighbours differ** — the `$reason` reuse
    stays a documented reuse because its run is adjacent, while this capture is
    fresh because its run was forty lines away — or a later reader "fixes" one
    to match the other.
  - Change, N6: the `vnext` half of slice 4 omits **two** assertions, not one.
    Add `assert_no_escape_hatch "$reason" "version-guard vnext-tags reason"`,
    which slice 2 and the tagged case both call, and
    `assert_not_contains "$reason" "just release"`. The second applies because
    the `vnext` fixture takes the *same initial-release branch* as the no-tags
    case — the block asserts "never been released" to prove it — and the no-tags
    site documents that property as asserted there alone only because the
    *steady-state* message names the recipe legitimately. A `vnext` reason is
    not steady-state.
  - Also update: the no-tags site's comment, which states the no-recipe property
    is "Asserted over the no-tags reason alone: the steady-state message names
    the recipe legitimately". Adding the `vnext` assertion falsifies that
    sentence; per `commit-bundling` the comment rides with the change.
  - Mutation gate, N4, **in two steps** — no single edit can turn this red,
    because `assert_eq "$tagged_sysmsg" "$tagless_sysmsg"` asserts the two
    notices *equal*, so a stale read of any other deny compares equal too. Step
    1: insert a `run_guard` of an **allow** scenario just above the new
    re-invocation; the suite must stay green, which shows the fresh capture is
    insulated. Step 2: with that insertion still in place, delete the
    re-invocation; the `assert_eq` must go red, `tagless_sysmsg` having read the
    allow run's absent `.systemMessage`. Revert both before the N6 gate.
  - Mutation gate, N6: add an escape-hatch sentence to the initial-release deny
    reason in `toolkit/version-guard.sh`. The new `assert_no_escape_hatch` on
    the `vnext` case must go red; it stays green today. Revert before
    committing.
  - Interfaces:
    - two new call sites in the `vnext` block:
      `assert_no_escape_hatch "$reason" "version-guard vnext-tags reason"` and
      `assert_not_contains "$reason" "just release" "<label>"` — consumed by
      Item 3.4's matcher conversion.

- **Item 3.3:** `tests/version-guard-test.sh` — one allow scenario against a git
  fixture, driven by a recording `git` stub.
  - Requirements: N5
  - Depends on: Item 3.2 (serialization — same file)
  - Model: sonnet
  - Change: every `assert_allow` runs against `$proj`, which is deliberately not
    a repo, so the property "the tag listing runs only after the deny is
    established" is unpinned. **A bare `assert_allow` cannot pin it** — the
    listing block absorbs every outcome into a variable, never exits non-zero,
    writes nothing to stdout and suppresses stderr, so hoisting it above the
    `[[ -z "$proposed" || "$proposed" == "$current" ]] && exit 0` early return
    leaves both fixtures allowing, byte-identical. The property is about work
    ordering, which the decision channel cannot observe. Add one allow scenario
    in `$git_tagged_proj` — an edit to `plugin.json` that does not change
    `.version` — with a **recording** `git` wrapper first on `PATH` that appends
    its arguments to a log and `exec`s the real binary, the `guard_stub127_dir`
    idiom already in this file. Assert the log holds no `tag --list`. The git
    fixture is required: against `$proj` the stub would record nothing either
    way.
  - Mutation gate: hoist the tag-listing block above that early return in
    `toolkit/version-guard.sh`. The log assertion must go red; any assertion on
    the decision alone stays green. Revert before committing.
  - Interfaces:
    - the recording stub's log path, exported to the scenario, holding one line
      per `git` invocation — consumed by Item 3.4 only as further needles to
      re-read under BRE.

- **Item 3.4:** `tests/version-guard-test.sh` — `assert_contains` and
  `assert_not_contains` converge on the `grep -q --` form.
  - Requirements: N8
  - Depends on: Items 3.2 and 3.3 — **runs last on this file.** It converts
    every assertion call site, while 3.2 and 3.3 each *add* call sites. In any
    other order the new assertions land in the pre-conversion glob form and this
    item's BRE re-check silently skips them.
  - Model: sonnet
  - Change: this file implements both helpers as a literal glob
    (`[[ "$1" != *"$2"* ]]`) while `release-test.sh`, `self-release-test.sh` and
    `update-plugin-dev-test.sh` use `grep -q --`, a BRE — same name, same
    signature, different semantics, in a repo that deliberately duplicates the
    harness per file. Move both bodies to `grep -q --`, and converge the failure
    output too, or one suite keeps a different diagnostic shape. The glob form's
    comment constrains what the caller passes as the *haystack*, not the
    matcher, and survives unchanged.
  - Scope: **18 call sites** before 3.2's and 3.3's additions — eight
    `assert_contains` and ten `assert_not_contains`, three of them inside
    `assert_no_escape_hatch`'s body. The outline's "20 … nine and eleven"
    counted the two helper *definitions* as sites; the outline is a frozen dated
    artifact and is not corrected there, so this line is the count to work from.
  - Re-read every needle before landing, on **two** axes, and include the
    needles 3.2 and 3.3 added:
    - **BRE-live characters.** Across the pre-existing eighteen the only ones
      are the dots in `9.9.9` and in `settings.json`; both widen to any-char and
      both still match, so no needle needs escaping — verify rather than assume.
    - **Newline spans.** The glob form matches across newlines; `grep` matches
      within a line. No current needle spans one — `assert_no_escape_hatch`'s
      long needle is deliberately cut at the deny reason's line break — but a
      needle that did would change meaning silently under the new form.
    **The two kinds carry opposite risks, and the two axes invert them.** Under
    BRE widening `assert_contains` risks a silent **false pass** and
    `assert_not_contains` only a **false failure**, loud on the first run. Under
    the newline change it is the other way: `assert_contains` fails loudly,
    `assert_not_contains` passes silently. So the careful read covers the
    positive needles for BRE characters and *every* needle for line breaks.
  - Mutation gate: no production mutation applies — the gate is the suite
    itself. Run it before and after conversion and confirm the same set of
    scenarios passes, and that a deliberately weakened positive needle (one
    extra character) fails under the new form.
  - Interfaces:
    - `assert_contains <haystack> <needle> <label>` — `grep -q --`, BRE
      semantics, matching the other three suites.
    - `assert_not_contains <haystack> <needle> <label>` — same matcher, negated.

- **Item 3.5:** new `tests/citation-test.sh`, `justfile`, `CLAUDE.md`,
  `toolkit/release.sh`, `tests/version-guard-test.sh`, `tests/release-test.sh` —
  a gate check that refuses line-number citations into living source, and the
  five citations it finds converted to unambiguous line context.
  - Requirements: N9
  - Depends on: Items 1.1, 1.2, 3.1, 3.2, 3.4 — 3.2 is `outline.md`'s line-level
    overlap B5 ↔ C4 (two stale `version-guard-test.sh` citations sit inside the
    comment block 3.2 edits), named here rather than left to transitivity
    through 3.4. 3.4's "runs last" is about assertion call sites; this item
    touches comments only in that file.
  - Model: sonnet
  - **Was Item 4.6, an inline prose item, until `/proof` on 2026-09-19.** The
    proof gate decided the convention is enforced by a check rather than by a
    `CLAUDE.md` Conventions bullet: a bullet duplicating a rule proposed
    upstream rots silently once upstream ships it, since nothing here learns of
    that, while a check is not prose and cannot become a duplicate. A check is
    code, so the item moved to a `general` phase and the conversion came with it
    — the check going green is the conversion's completion criterion.
  - **Order: the check first, then the conversion.** Written against the
    unconverted tree the check must report exactly the five hits below — quote
    that output in the report; it is this item's honest red. Then convert until
    it is green.
  - Change, the check: `tests/citation-test.sh`, in the shape of
    `tests/docs-test.sh` — a checker suite with its own copy of the harness,
    signing off with the checks that passed. Over `git ls-files -z`, excluding
    `plans/` and `docs/changelog/`, fail on any `<name>.sh:<digits>`,
    `<name>.just:<digits>` or `justfile:<digits>`. The failure line names file
    and line and **carries the convention**: cite the enclosing symbol plus a
    short quoted fragment, not a line number. The message is the convention's
    only standing home, so it must be enough to act on alone.
  - **The check must not flag itself.** Its pattern and message describe the
    forbidden form; build any literal sample at runtime rather than exempting
    the file, so the suite stays inside its own coverage.
  - **Self-fixture, so the failing path is tested on every run and not once by
    hand.** Run the check function against a throwaway git repo holding one
    planted citation in a tracked script and one under `plans/`: it must report
    the first and not the second. Then run it against this repo.
  - **Residual bound, stated in the suite's header:** citations into `.md` files
    are not checked, because an extension cannot tell a living document from a
    frozen one — `tests/version-guard-test.sh`'s `outline.md:118-121` cites an
    executed outline and is correct forever. Leave that one standing.
  - Wire it in: add the suite to `justfile`'s `precommit` recipe, in both the
    `bash -n` line and the run list, and to the suite list in `CLAUDE.md`'s
    Quality gate paragraph. **No `CLAUDE.md` Conventions bullet.**
  - Change, the conversion — five citations, four stale. Each stale one lands on
    *different real code*, so a reader who follows it gets a confident wrong
    answer rather than an error:
    - `release.sh`'s comment citing `:780-785` for "release_preflight never runs
      on resume" — that range is the marketplace commit-gate rollback.
      **Stale.**
    - `version-guard-test.sh`'s comment citing `release.sh:446-455` for a bump
      argument refused on an unreleased plugin — that range is the version-drift
      refusal. **Stale.**
    - the same comment citing `release.sh:456-460` for a bare `just release`
      publishing `$current` — that range is a `die` plus the resume hint.
      **Stale.**
    - `version-guard-test.sh`'s header comment, "See release-test.sh:8-13", for
      the leaked-git-environment explanation — off by one at each end: it takes
      in `set -euo pipefail` and stops short of the `unset` line. **Stale.**
      Found at `/proof`; the earlier sweep missed it.
    - `release-test.sh`'s comment citing `release.sh:138` for the dirty-tree
      refusal preceding `release_preflight`. **Accurate at `8d3fbf5`** — convert
      it too; the check allows no second convention.
  - Replacement form: the enclosing symbol plus a short quoted fragment of the
    cited line — "`release.sh`, the mode dispatch in `main`, the `--resume`
    branch" — not a bare function name, which loses precision in a long
    function. **Re-locate each target by symbol**: Items 1.1 and 1.2 have moved
    `release.sh` and Items 3.2–3.4 have moved `version-guard-test.sh`.
  - Recorded upstream, no follow-up held here: a brief at
    `../edify/inbox/brief-cite-line-context-not-line-numbers.md` proposes the
    same convention for `/design` and `/runbook`. Dropping it was the end of
    this repo's involvement.
  - Mutation gate: after the conversion is green, put one `<script>.sh:<line>`
    citation back into a comment in `toolkit/release.sh`. The real-repo check
    must go red naming that file and line; the self-fixture half must stay
    green. Revert before committing.
