# Deliverable review — prose and config (Layer 1)

Scope: `docs/design.md`,
`docs/references/{release-flow,version-guard,recovery,self-release}.md`,
`docs/changelog.md` + the six `docs/changelog/2026-09-17-*.md` records,
`toolkit/README.md`, `toolkit/release.just` header, `CLAUDE.md`,
`toolkit/VERSION`, as of `HEAD` (`e229e1b`).

Verified against code, not prose, for: the four `resume_preflight` hint
branches, the lost-tags probe's ordering and refusal wording, the
`check-version.sh` initial-release hint, the `semver_tags` filter and both
`--sort=-v:refname` listings, the diverged-push-route loop, the hook's local tag
listing and both deny heredocs, `check-version.sh`'s missing-entry skip,
`toolkit/release.just`'s recipe doc comments, `tests/doc-sync-test.sh`'s actual
assertions, the `tests/` file list against `justfile`'s `precommit`, the
`docs/**` line counts and the `cap-ok` exemptions, the mounted consumers' tag
sets, and the pre-split `recovery.md` (`fc4d016~1`). Read-only for: the
changelog record bodies other than the first-release one, and
`docs/references/distribution.md`.

No test suite was run.

## Critical

None.

## Major

### M1 — `version-guard.md:44-48` claims a parity the hook does not have

**Axis: accuracy, completeness.**

> The predicate is the one `release_preflight` uses — no tag matching
> `^v[0-9]+\.[0-9]+\.[0-9]+$` — so the hook and the recipe cannot disagree about
> which state a repo is in.

The first clause is true; the conclusion is not. `version-guard.sh:124` lists
**local** tags only:

```sh
if listing="$(git -C "$project" tag --list 'v*' --sort=-v:refname 2>/dev/null)"; then
```

`release_preflight` runs the same local listing and then, when it comes back
empty, probes origin (`release.sh:377-403`) and refuses on any semver tag there.
So on a lost-tags clone the two *do* disagree: the recipe refuses with the
`git fetch --tags` hint (`release.sh:388-392`) while the hook takes the
initial-release branch and tells the agent

> Which version a plugin first ships as is the maintainer's call and their edit
> to make.

That is the permissive wording for a plugin that may already be published —
precisely the harm this same node cites at `version-guard.md:106-114` to justify
the restrictive fallback on a failed listing. The doc names one bound for the
listing (`:132-134`, a `CLAUDE_PROJECT_DIR` inside an enclosing repo) and not
this one, so a reader concludes the enclosing-repo case is the only way the
wording can be wrong, and a maintainer asking "does the hook need an origin
probe?" concludes from `:44-48` that the question is already settled.

`design.md:187` carries the weaker form ("on the same no-semver-tag predicate
`release_preflight` uses"), which is defensible; it is the `cannot disagree`
clause in the node that overstates.

What a reader would get wrong: that the hook is origin-aware, or that the two
predicates are the same predicate rather than the hook using the local half of
one. The fix is to drop the `cannot disagree` clause and state the bound
alongside the enclosing-repo one — the hook is local-only by design (a
`PreToolUse` hook must not make a network call), so this is a bound to record,
not a defect to close.

### M2 — `version-guard.sh:3-7` header contradicts the decision it implements

**Axis: consistency.** (Shipped file; belongs to the code reviewer's diff,
flagged here because the defect is the prose.)

```
# recipe owns version bumps: once a plugin has released, manual edits
# desync the manifest from the latest tag and only get caught at release
# time; before a first release there is no tag to desync from, but the
# recipe is still the only place a version is meant to change.
```

The last clause is false under this plan. On a first release the version
legitimately changes by the maintainer's hand edit, committed — which is what
the same file's own deny message says (`version-guard.sh:153-154`), what
`release.sh:476-479` instructs, and what `toolkit/README.md:181-186` and
`design.md:109-110` state as the decision. A maintainer reading the header
concludes a hand edit is never legitimate, which is the belief the whole plan
exists to correct. Outline line 126-127 asked for this header to be "restated
for both cases"; the initial-release half was added but its conclusion was
carried over unchanged from the steady-state case.

## Minor

### m1 — `design.md:186-192` absorbs the node's argument

**Axis: excess.** The hub's stated contract (`design.md:7-12`, `63-67`) is one
conclusion per decision, pointing at its node. The version-guard bullet's last
sentence is mechanism, not conclusion:

> Nothing computed after the deny is decided may fail: a hook exiting non-2 is a
> non-blocking error, so a crash there allows the edit it had just refused.

That argument is already at `version-guard.md:83-90`, at length. Same shape,
milder, at `design.md:135-140` (the push-route bullet enumerates all three
config keys and the `pushInsteadOf` bound, both of which `recovery.md:216-258`
argues in full). Every other bullet in the file states its conclusion and stops.
Nothing is wrong; the hub is growing back toward the 837-line state the
2026-09-02 split fixed, and this is the pass where that is cheap to arrest.

### m2 — partial tag loss is an unstated bound

**Axis: completeness.** The outline records it under Scope/OUT: "A clone holding
`v1.0.0` over origin's `v1.2.3` still reads as released. Pre-existing, unchanged
here." Confirmed in code — `release.sh:377` gates the origin probe on
`[ -z "$release_tag_list" ]`, so a non-empty-but-stale local list never reaches
it and goes to the drift check at `:520` against a `latest_tag` origin has moved
past.

Neither `recovery.md`'s "Why the lost-tags probe runs before the drift check"
(`:198-215`) nor `design.md`'s Limitations records it. The symmetric bound on
the adjacent check — `url.<base>.pushInsteadOf` — *is* recorded in both
(`recovery.md:246-258`, `design.md:139-140`), which makes the omission read as
coverage rather than as a bound. A reader concludes the origin probe closes the
lost-tags case generally. One sentence in `recovery.md:198-215` ("the probe
fires only on an empty local list; a partially-lost tag set still reads as
released") would close it.

### m3 — `toolkit/README.md:34` still says "the latest tag"

**Axis: consistency.** The version-guard bullet: "manual edits desync the
manifest from the latest tag and only get caught at release time." Sixty lines
later the Conventions bullet (`:174-186`) correctly says detection is by
`vX.Y.Z` tag, and `release-flow.md:14-17` draws the distinction explicitly ("The
newest *semver* tag and not simply the latest tag"). This is the only shipped
manual a consumer reads; a consumer with a `vnext` tag reads `:34` as saying it
counts. Outside the outline's literal scope for Item 3.5 (which named `:175-179`
only), but in the same file and the same sentence pattern the plan corrected
elsewhere. Same phrasing, same low stakes, at `recovery.md:15`, where it is a
historical clause describing pre-`check-version.sh` behaviour.

### m4 — `CLAUDE.md:73-76` carries a ragged wrap

**Axis: usability.** The `docs/references/*.md` bullet now reads:

```
- `docs/references/*.md` — one node per group of decisions
  (`distribution`, `release-flow`, `recovery`, `self-release`,
  `version-guard`), each
  holding the argument behind the hub's conclusions: ...
```

`just format-docs` runs rumdl over `docs/` and `plans/` only (`justfile:59-86`),
so `CLAUDE.md` is never reflowed by the gate and this will persist. Cosmetic;
noted because nothing else will catch it.

## Answers to the specific checks

**1. `release-flow.md` — the conjunct.** Rewritten in place, correctly. `:60-77`
states the old requirement in past tense, gives its original argument, then
supersedes it with the new reasoning: the conjunct "only ever protected a
lost-tags repo that *had* an entry", so it covered plugins already in the
marketplace and left a first-time publisher's lost-tags clone unguarded — and
that state is reachable because `check-version.sh` skips a missing entry
(verified, `check-version.sh:46-51`). The origin probe is stated as "strictly
stronger", and the consequence (`marketplace.json` no longer has to be
hand-written before a first release can be detected) is drawn.
**No trace of the old argument stands as current truth.** The three rejected
mechanisms are at `:105-129` with their reasons, all three:
guard-allows-the-edit, `--initial`, baseline tag. The `0.0.0` seeding rejection
survives at `:131-137`. Both listings' `--sort=-v:refname` is explained at
`:85-91`, including the `v1.10.0`/`v1.2.3`/`v1.9.0` lexicographic case —
verified against `release.sh:307` and `:338`.

**2. `version-guard.md`.** All four topics present: the message branch
(`:30-58`), no route to the proposed version (`:60-72`), only the agent channel
branches (`:74-81`), the listing can never turn a deny into an allow
(`:83-134`). All verified against `version-guard.sh:147-174`, `:124-145` and
`tests/version-guard-test.sh:326-390`; the claimed tests exist (the `$proposed`
grep at `:326-335`, the byte-identical `systemMessage` comparison at `:352-368`,
the `vnext`/`v1.2` fixture at `:371-381`). One overclaim — M1 above.

**3. `recovery.md`.** **The runbook is right and the outline is wrong.** The
code emits **four** hint branches (`release.sh:577`, `:585`, `:596`, `:603`);
`recovery.md:85-103` documents four, matching. Runbook Item 3.3 says "four
hints"; outline line 262 says "three". The outline's `:51-54` citation is wrong
on both counts — the pre-change `recovery.md` carried **one** hint there
(`just release <bump>`, verified at
`6550fb7~1:docs/references/recovery.md:51-54`). No document needs changing; the
outline is the defective baseline. The lost-tags and diverged-push-route
refusals join the list at `:193-196`; why the probe runs before the drift check
is at `:198-215` and matches `release.sh:358-403`; resume on a tagless clone is
at `:85-110`; `check-version.sh` on an initial release is at `:34-58` and
matches `release.sh:413-458` clause for clause, including the "no vX.Y.Z tag,
here or on origin" wording and the residual it deliberately does not deny.

**4. `design.md`.** Release-flow conclusion rewritten (`:105-110`), message
branch added to the version-guard conclusion (`:186-192`), plus three bullets
not in the outline's Item 3.4 (the origin probe, the push route, the resume
hint) and a whole new `self-release.md` group — all correct as conclusions. The
hub did absorb some argument: see m1.

**5. `changelog.md`.** One index line per record, six new, newest first, dates
consistent with the bodies. The first-release line says it outright and in bold:
"**detection semantics change: a marketplace entry no longer disqualifies a
first release.**" The record body
(`docs/changelog/2026-09-17-first-release-is-the-manifest-version.md`, 105
lines) is a write-time record in the right register — it names the plugin and
the vendored toolkit version that surfaced the gap, keeps the overturned
decision as a section of its own, and records what was rejected. Not revised
anywhere.

**6. `toolkit/README.md:174-186`.** All three required statements present:
detection by semver tag ("no `vX.Y.Z` tag exists here or on origin. The
marketplace entry plays no part"), the initial version coming from
`/plugin-dev:create-plugin`, and a different version being the maintainer's
**committed** edit with the reason (`.claude-plugin/` is not exempt from the
clean-tree check — verified against `release.sh` `clean_pathspecs`). See m3 for
the unrelated stale phrase earlier in the file.

**7. `toolkit/release.just:30-33`.** Two sentences, not one, naming the
predicate and saying the marketplace entry plays no part. Correct and no worse
for being two. **Recipe doc comments are all single-line**: the last comment
line above each of `release`, `resume-release`, `check-version` and
`update-plugin-dev` is one line (`:65`, `:70`, `:74`, `:78`); the multi-line
`quote()` comment at `:60-64` is separated from `release`'s doc line by nothing
but is not the last line, so `--list` still shows the right string. Signatures
unchanged.

**8. `CLAUDE.md` Layout vs reality.** Accurate. `toolkit/` holds exactly
`LICENSE README.md VERSION check-version.sh install.sh release.just release.sh update.sh version-guard.sh`;
the Layout list names all but `LICENSE`, which `doc-sync-test.sh:80-88` exempts
by name. `toolkit/migrations/` does not exist and the list describes it as
optional — both `doc-sync-test.sh` and `dist-tree-test.sh` carry the `vX.Y.Z.md`
pattern exemption, so adding one later needs no list edit. The new
`scripts/self-release.sh` bullet is accurate, the `docs/references/*.md` node
list now matches the five files on disk, and the eight `tests/` files named in
the Quality gate section match `ls tests/` and `justfile:9-18` exactly.

**What `doc-sync-test.sh` does NOT enforce**, and which this review therefore
checked by hand:

- Only backtick-quoted **`toolkit/...`** paths are compared against the tree
  (`:90-104`). Nothing checks the root-level bullets — `justfile`,
  `scripts/self-release.sh`, `README.md`, `docs/`, `plans/`, `pyproject.toml`,
  `.rumdl.toml`, `.envrc` — so a stale or missing one is invisible.
- Nothing checks the `tests/` file list in the Quality gate section against
  `tests/` or against `justfile`'s `precommit` body. That list just grew by two
  entries and a suite rename; a future rename will drift silently.
- Nothing checks the `docs/references/*.md` node enumeration.
- Nothing checks that a bullet's *description* still matches the file it names —
  only that the path exists.
- The README block check is one-directional (root ⊆ toolkit) and compares fenced
  blocks only, never prose.

**9. Cross-document consistency of the predicate.** Stated the same way in all
six places: `design.md:106-107`, `release-flow.md:56-58`, the changelog record
`:32-34`, `toolkit/README.md:178-180`, `toolkit/release.just:30-33`,
`toolkit/release.sh:14-16`. `version-guard.md:45` states it without the "locally
or on origin" qualifier, which is correct for the hook — but see M1 for what it
then concludes. Remaining "the latest tag" occurrences: `release-flow.md:15`
(deliberate contrast, correct), `recovery.md:15` and `toolkit/README.md:34`
(m3), `self-release.md:48` (correct — the self-release has no semver filter and
reads the literal latest tag).
**No `file:line` citations survive anywhere under `docs/`** — grepped for
`.sh:N`, `.just:N`, `justfile:N`, zero hits. All pointers resolve: `design.md` →
`references/self-release.md`, `self-release.md` → `distribution.md` and
`recovery.md`, `recovery.md` → `self-release.md` ×2, `release-flow.md` ↔
`version-guard.md`, and the two named-section pointers
(`"The clean-tree check excludes the agent's own working state"`,
`"First release publishes the manifest version as-is"`) both hit real headings.

**10. The 400-line cap.** Clean, with margin. `docs/references/recovery.md` 352,
`release-flow.md` 294, `distribution.md` 264, `design.md` 234,
`version-guard.md` 159, `changelog.md` 138, `self-release.md` 78; largest
changelog record 105. Nothing at or over the cap, and nothing parked at it. The
three `cap-ok` exemptions are all pre-existing (`2026-09-02` record, two 2026-07
and 2026-09 plans). `recovery.md` went 389 → 352 while absorbing 129 new lines,
so the split bought a real margin rather than a nominal one.

**11. The `recovery.md` → `self-release.md` split.** Nothing lost. Diffed
`fc4d016~1:docs/references/recovery.md` (389 lines) against both current files:
every paragraph of the old `### This repo's own release script` section survives
in `self-release.md` — the literal pathspecs and the "no second answer" argument
(`:27-35`), the `v0.4.1` incident and the drift/tag-collision analysis
(`:39-53`), the "consumer script needs no equivalent guard" paragraph
(`:64-69`), and the two-tags/`dist-` re-cut paragraph (`:71-78`) — all expanded
rather than trimmed. `recovery.md` keeps a forward pointer at `:170-173` and a
second at `:280-281`.

The one deletion is deliberate and is the point of the split: the old paragraph
arguing "`resume-release` exists as a convenience for consumers, who are more
numerous and less close to the code" and "Resuming it by hand is a tag and a
`gh release create`, which the toolkit's sole maintainer can do" — false as of
`43f348a`, which gave the self-release its own `resume-release`. The changelog
record for the split names exactly this. Its surviving half (folding the two
scripts together would make the toolkit consume its own consumer-shaped code) is
preserved in both files.

**12. Migration notes.** None needed, and the reasoning still holds.
`toolkit/migrations/` does not exist. Verified all five mounted consumers carry
only `vX.Y.Z` tags — `gitmoji` (8), `gitlore` (21), `cwd-safety` (8),
`shell-gotchas` (5), `handoff` (34); not one non-semver or non-`v` tag among
them, so none is in the residual state (released only under some other scheme,
*with* a marketplace entry) that the new detection would now republish over.
`plugin-craft`, named as a sixth consumer in the changelog record, is not
mounted here and was not checked, but the record says it was cut at `v0.1.0`.
`toolkit/VERSION` at `0.8.0` is consistent: `e3312f9 🔖 0.8.0` is the release
that shipped this change (a `minor` bump from 0.7.1, as the outline's
Dependencies section required), and it sits *after* the Phase 3 docs commit
`a70856a` in history. Four commits since are unreleased, which is ordinary.

## Document conformance table

| Outline requirement | Document | Status | Evidence |
| --- | --- | --- | --- |
| "the latest tag" → newest semver tag | `release-flow.md` | Covered | `:12-17`, with the `latest_tag`/`release_tags` mechanism; matches `release.sh:501` |
| Detection rewritten in place, tags only | `release-flow.md` | Covered | `:56-58` states it; `:60-77` supersedes the conjunct with new reasoning |
| Scaffold paragraph restated as Rule 1 | `release-flow.md` | Covered | `:36-47`, naming `/plugin-dev:create-plugin` and why the seed can't be fixed upstream |
| Three rejected mechanisms with reasons | `release-flow.md` | Covered | `:105-129` — guard-allows, `--initial`, baseline tag |
| `0.0.0` seeding rejection survives | `release-flow.md` | Covered | `:131-137`, unchanged in substance |
| Why both listings carry `--sort=-v:refname` | `release-flow.md` | Covered | `:85-91`; verified against `release.sh:307`, `:338` |
| Initial-release message branch | `version-guard.md` | Covered | `:30-58`; matches the heredoc at `version-guard.sh:148-158` |
| Why it names no recipe as a route to `$proposed` | `version-guard.md` | Covered | `:60-72`; the asserting test exists (`version-guard-test.sh:326-335`) |
| Why only the agent channel branches | `version-guard.md` | Covered | `:74-81`; test at `version-guard-test.sh:352-368` |
| Why the listing can never turn a deny into an allow | `version-guard.md` | Covered | `:83-134`; matches `version-guard.sh:107-145` |
| Same predicate as `release_preflight` | `version-guard.md` | **Partial** | `:44-48` — predicate claim true, "cannot disagree" false (M1) |
| No-tag refusal's hints | `recovery.md` | Covered | `:85-103`, four cases, matching `release.sh:577-611`; outline's "three" is wrong |
| Lost-tags + diverged-push-route refusals in the list | `recovery.md` | Covered | `:193-196` |
| Why the probe runs before the drift check | `recovery.md` | Covered | `:198-215` |
| Resume on a clone missing tags | `recovery.md` | Covered | `:85-110` |
| `check-version.sh` on an initial release (Decision 1 / FR-8) | `recovery.md` | Covered | `:34-58`; matches `release.sh:413-458` |
| Partial tag loss as a stated bound | `recovery.md` / `design.md` | **Missing** | m2 — recorded in the outline's Scope/OUT, in neither document |
| Release-flow conclusion rewritten | `design.md` | Covered | `:105-110` |
| Message branch added to version-guard conclusion | `design.md` | Covered | `:186-192` |
| One line per decision, argument in the node | `design.md` | **Partial** | m1 — `:190-192` and `:135-140` carry the node's argument |
| Index line per record, newest first | `changelog.md` | Covered | `:12-50`, six new entries |
| Index line says detection semantics change outright | `changelog.md` | Covered | `:43-50`, bolded, first clause |
| Conventions bullet: tag detection, scaffold source, committed edit | `toolkit/README.md` | Covered | `:174-186`, all three |
| Header sentence: predicate + marketplace plays no part | `toolkit/release.just` | Covered | `:30-33` (two sentences); recipe doc comments still single-line |
| Layout list matches `toolkit/`, root and `tests/` | `CLAUDE.md` | Covered | verified by hand; `doc-sync-test.sh` covers only the `toolkit/` paths |
| No migration note needed | `toolkit/migrations/` | Covered | directory absent; all five mounted consumers semver-tagged |
