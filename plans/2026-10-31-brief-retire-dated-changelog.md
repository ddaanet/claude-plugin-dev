# Brief: retire the dated changelog in claude-plugin-dev

2026-10-31. Written by a survey session in this repo. A proposal, not a
decision: my human partner proposed the retirement; nothing below has been ruled
on, and no file, convention or skill was changed. The survey across the sibling
repos is `plans/2026-10-31-retire-changelog-survey.md`; the source of the
convention is craft's `design-doc-writing` skill, which gets its own brief
(`craft/inbox/2026-10-31-brief-retire-dated-changelog.md`).

## Proposal

Stop writing `docs/changelog/YYYY-MM-DD-slug.md` records and the
`docs/changelog.md` index. Keep the living design — `docs/design.md` and the
`docs/references/` nodes, present tense, rewritten in place. Commit messages and
`git log -- <path>` become the archaeology.

Why:

- **Records restate their commits.** 54 of the 61 records landed in the same
  commit as the change they describe, so `git show` on that commit already
  carries both the diff and the record text; six came from the `DESIGN.md` split
  and one was committed alone (both below).
- **The shared rule already says so.** A summary of a change points at the diff;
  it does not narrate it. A record is a second summary of the same diff.
- **Git covers archaeology.** Deleted records stay readable from history (see
  "Reaching a deleted record" below).
- **One less exemption.** The in-flight size check
  (`plans/2026-10-31-line-cap-gate/design.md`) has to argue for counting
  `docs/changelog/` (its D3); with no records, there is nothing to argue.

## Where git does not cover a record today

"Records restate their commits" is true of the diff, not of the reasoning. Of
the 61 record-adding commits, 30 have a subject line and no body. Sampled:

- `2026-10-18-self-release-probe-failure.md` is 30 lines: the incident (a
  sandbox blocking `github.com:22` read as missing tags), why the "safe
  direction" comment was wrong, and the three fixes. Its commit `80d9202` is one
  line. `docs/references/self-release.md:63` keeps one sentence of it.
- `2026-10-18-disk-checks.md` (37 lines) and `2026-10-19-toolkit-manual.md` (27
  lines) also sit on subject-only commits (`b82466b`, `7bc8eeb`).
- `2026-10-26-docs-test-drops-pointer-check.md` (24 lines) sits on `97d20e1`,
  whose body is one paragraph and does cover the why.
- `2026-09-20-deliverable-review-fixes.md` is the one record committed apart
  from its change (`a9484ef`, a record-only commit).
- Six records came from `c37f3cb`, the split of the old `DESIGN.md`; their
  reasoning predates their own commit and lives in `DESIGN.md`'s history.

Nothing is lost by deleting, since git keeps the files. What changes is that
going forward the reasoning has to land somewhere:
**the commit body carries the why of a design-significant change**, or the node
absorbs it. That is a commit-message convention, not just a deletion, and it is
the part to rule on.

## What happens to the 61 records

Deleted with the index, in one commit, since git keeps them. No archive
directory and no tag are proposed: either adds surface. If my human partner
wants one, a tag on the commit before the deletion makes the read shorter
(`git show <tag>:docs/changelog/<file>`); that is open question 3.

### Reaching a deleted record

After the deletion lands, from any shell:

```sh
repo=/Users/david/code/claude-plugin-dev
cd "$repo" && git log --format='%h %ad %s' --date=short -- docs/changelog/
p=docs/changelog/2026-10-18-self-release-probe-failure.md
cd "$repo" && git show "$(git rev-list -1 HEAD -- "$p")^:$p"
```

The second command worked when its output starts with
`# 2026-10-18 — Self-release: an unreadable origin refuses as itself`.

## Touch points: this repo's own convention

Retired with the records:

- `docs/changelog.md`, `docs/changelog/` (61 files): deleted.
- `CLAUDE.md` Layout bullet for `docs/changelog.md` (lines 145–146): deleted.
- `CLAUDE.md` Conventions bullet "Design and changelog are separate files with
  separate rules" (312–325): keeps the present-tense rule for the design and
  nodes; the record sentence becomes the commit-body rule; the format-docs wrap
  and grandfather sentences go.
- `CLAUDE.md` quality-gate list, `citation-test.sh`'s description (197):
  "outside `plans/` and `docs/changelog/`" becomes "outside `plans/`".
- `docs/design.md`: the "Design decisions" preamble (85–88), "the dated record
  of the reversal goes in the changelog", points at the commit instead; the
  `## History` section (393–397) is deleted or becomes one line naming
  `git log`. Line 4, "Not a changelog of features", can stay.
- `docs/references/limitations.md:49`: "ships no design doc or changelog" drops
  "or changelog".
- `README.md:207–208`: the `docs/changelog.md` bullet is deleted.
- `tests/citation-test.sh` (16–17, 81, 91, 105, 165): the `docs/changelog/`
  exemption guards nothing once the directory is gone, and goes.
- `tests/docs-test.sh` (8, 15) and `tests/line-cap-test.sh` (11, 70, 81, 103):
  the comments, the skip and the fixture record. Both suites are slated to be
  replaced by the size check, so these edits collide with that work; see
  sequencing below.
- `justfile` and `.rumdl.toml` name no changelog path: the `format-docs` recipe
  covers `docs/` whole. Nothing to change.
- `plans/**`: 70-odd files mention the changelog. Frozen; not edited.
- `toolkit/migrations/v0.12.0.md` (13, 26, 54, 61): a frozen per-release note;
  not edited.

## Touch points: shipped behaviour, which this retirement does not decide

`check-refs.sh` exempts `docs/changelog/` and `plans/` by default for every
consumer. Consumers that keep records (handoff with 93, gitlore with 124) rely
on it. Retiring this repo's own records does not justify changing it; it stays
unless every consumer retires, or a release drops it with a migration note
pointing at `refs.exempt`.

- `toolkit/check-refs.sh:32` (usage) and `:227`
  (`exempt=(docs/changelog plans)`).
- `toolkit/README.md:234`, `docs/design.md:271–273`,
  `docs/references/check-refs.md:68–71`, `CLAUDE.md:54`.
- `tests/check-refs-scan-test.sh` (7, 177–186) and
  `tests/check-refs-shipped-test.sh` (147–153), which use a `docs/changelog/`
  fixture as the exempt case.
- `docs/references/check-refs.md:111`, "a shipped changelog into `plans/`", is
  about consumers and stays either way.

## Readers outside this repo

- **plugin-craft** `skills/toolkit-release/SKILL.md:98–105` tells a consumer to
  read this repo's `docs/changelog.md` across a pull, because its pointer lines
  say when a release is breaking (`docs/changelog.md:255`, v0.4.0). With the
  index gone that section needs a replacement signal; its brief is
  `plugin-craft/inbox/2026-10-31-brief-retire-dated-changelog.md`.
- **The shared memory tier** carries a fact about this repo's changelog and two
  index lines pointing at it (paths in the survey). Reworded in the memory
  session that lands the retirement.
- **Every consumer's `plugin-dev/`** vendors `check-refs.sh` with the default;
  it changes only through a toolkit release.

## Knock-ons for the in-flight size-check design

`plans/2026-10-31-line-cap-gate/design.md`, not edited here:

- **Problem, line 25.** handoff's `docs/changelog.md` (103 lines, 50995
  non-whitespace bytes) is the motivating example. It stays true of its day, but
  if handoff retires its index the example names a deleted file.
- **D3 (95–101), "`docs/changelog/` is counted".** Moot here. It survives only
  for consumers that keep records; the index-split advice becomes "retire the
  index" wherever the retirement is accepted.
- **Scope, line 157:** "`docs/changelog/` included" can go.
- **Adoption (217–244).** The changelog-index rows for gitlore, handoff and
  prohibitions become retirements rather than splits by period; their counts
  drop by one each if accepted. A repo that keeps records as a frozen archive
  needs a `size.exempt` directory entry with a reason instead.
- **Implementation item 8 (305–306).** The changelog-wrap paragraph it rewords
  is deleted with the convention instead.
- **Item 10 (312–313).** No dated record and index bullet; the commit body
  carries the why.
- **321–322** (the index close under the cap) and **Propagation, 344** ("Dated
  changelog records are not revised"): moot.
- `reports/mechanics.md` and `reports/survey.md` are reports; not edited.
- The untracked input brief `plans/2026-10-30-brief-ship-the-line-cap-gate.md`
  (line 22) lists the exemption; input, not edited.

## Open questions, each with a default

1. **Is the commit body the new home of the why?** Default: yes, for a
   design-significant change; a self-contained fix keeps the one-line subject
   the shared rule allows.
2. **What signals a breaking toolkit release?** Default: a migration note is
   required for every breaking release and says so in its first line;
   `update.sh` already prints notes for the crossed range.
3. **Tag the last commit holding the records?** Default: no tag.
4. **Change `check-refs.sh`'s default?** Default: no, until the consumers have
   ruled.
5. **Sequencing against the size check.** Default: retire first, so the size
   check ships with no changelog clause and `docs-test.sh` / `line-cap-test.sh`
   are not edited twice.
