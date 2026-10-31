# Survey: retiring the dated changelog

2026-10-31. Survey for my human partner's proposal to retire dated write-time
records (`docs/changelog/YYYY-MM-DD-slug.md`) and their `docs/changelog.md`
index in favour of git history, keeping the living design. Proposals only: no
convention, file or skill was changed, and nothing was committed. Read-only git
commands only in the other repos; one brief per repo in its `inbox/`.

Briefs written:

- this repo: `plans/2026-10-31-brief-retire-dated-changelog.md`
- the main one, for the source of the convention:
  `/Users/david/code/craft/inbox/2026-10-31-brief-retire-dated-changelog.md`
- `/Users/david/code/<repo>/inbox/2026-10-31-brief-retire-dated-changelog.md`
  for cwd-safety, ghmem, gitlore, gitmoji, handoff, onekeys, plugin-craft,
  prohibitions, sandbox-lies and shell-gotchas.

## Per repo

Visibility is from `git remote get-url origin` plus `gh api`. "Records" are
dated files; "inline" is one file of dated sections. "Bodiless" counts commits
that add a record (or touch an inline changelog) with a subject line and no
body. No changelog anywhere is shipped: no `dist.include` lists one, and every
GitHub release is cut with `--generate-notes`, so no user-facing release notes
are in scope.

| repo | form | size | writers | readers | brief |
| --- | --- | --- | --- | --- | --- |
| claude-plugin-dev (public) | records + index | 61 records; index 268 lines | `CLAUDE.md` convention | own tests' exemptions; plugin-craft skill; shared tier | written |
| craft (public) | inline | 286 lines | `design-doc-writing` (source) | none | written (main) |
| candidature (public) | none | — | — | — | skipped: no changelog |
| cwd-safety (public) | records + index | 10 records; 45 lines | `CLAUDE.md`, design hub | none | written |
| ghmem (public) | index of pointers | 183 lines | design doc | none | written |
| gitlore (public) | records + index + archive | 124 records; 353 + 183 lines | `CLAUDE.md`, decisions index | link checker test, hygiene comment, 5 node citations | written |
| gitmoji (public) | records + index | 1 record; 11 lines | `CLAUDE.md` | none | written |
| handoff (public) | records + index | 93 records; 103 lines, ~50 KB | `CLAUDE.md` | ~127 links from nodes, code, tests, shipped skill | written (options, no default) |
| onekeys (public) | records + index | 2 records; 12 lines | `CLAUDE.md` | none | written |
| plugin-craft (public) | inline | 65 lines | design doc | its shipped skill reads cpd's index | written |
| prohibitions (public) | inline | 446 lines | `CLAUDE.md` | none | written |
| prompt-fzf (no origin) | none | — | — | — | skipped: no changelog; only vendored `plugin-dev/` mentions it |
| sandbox-lies (public) | inline + monthly archive | 222 + 231 lines | design hub, NFR-3 | none | written |
| shell-gotchas (public) | records + index | 51 records; 61 lines | `CLAUDE.md` | `check-size.sh`, `.rumdl.toml` exempt it | written |

prompt-fzf has no remote, so its visibility cannot be read; it is not counted as
public.

Every consumer's vendored `plugin-dev/check-refs.sh` exempts `docs/changelog/`
by default. That changes only through a toolkit release, and the
claude-plugin-dev brief keeps it out of this retirement.

## Checks that exempt `docs/changelog/`

- claude-plugin-dev, shipped: `toolkit/check-refs.sh:227`, the default
  `exempt=(docs/changelog plans)`, and its tests
  (`tests/check-refs-scan-test.sh`, `tests/check-refs-shipped-test.sh`). Kept
  unless every consumer retires.
- claude-plugin-dev, own: `tests/citation-test.sh`, `tests/line-cap-test.sh`;
  `tests/docs-test.sh` mentions it in comments only.
- shell-gotchas: `scripts/check-size.sh:24` and `.rumdl.toml:3–4`.
- gitlore: `tools/check-memory-hygiene.py:40` names it in a comment, but
  excludes all of `docs`; `tests/check_docs_links.bats:46` asserts records are
  scanned, the opposite of an exemption.

## Does git cover what the records hold?

The diff, yes; the reasoning, often not. In claude-plugin-dev 54 of 61 records
landed in the same commit as their change, so `git show` returns both; six came
from the `DESIGN.md` split (`c37f3cb`) and one,
`2026-09-20-deliverable-review-fixes.md`, was committed alone (`a9484ef`). The
other repos' "with their change" counts in the briefs are commits that also
touched files outside `docs/changelog*`, so a bulk split counts as one. But many
of those commits have no body:

| repo | record-adding commits | bodiless |
| --- | ---: | ---: |
| claude-plugin-dev | 61 | 30 |
| handoff | 93 | 20 |
| shell-gotchas | 51 | 15 |
| gitlore | 124 | 9 |
| cwd-safety | 10 | 0 |
| onekeys | 2 | 0 |
| gitmoji | 1 | 0 |

For the inline changelogs, commits touching the file: craft 9 of 17 bodiless,
plugin-craft 13 of 16, prohibitions 17 of 31, sandbox-lies 29 of 36.

Sampled records against their commits:

- claude-plugin-dev `2026-10-18-self-release-probe-failure.md`: 30 lines (the
  incident, why a comment's "safe direction" claim was wrong, three fixes) on
  the one-line commit `80d9202`. `docs/references/self-release.md:63` keeps one
  sentence of it.
- claude-plugin-dev `2026-10-18-disk-checks.md` (37 lines, `b82466b`) and
  `2026-10-19-toolkit-manual.md` (27 lines, `7bc8eeb`): bodiless commits.
- claude-plugin-dev `2026-10-26-docs-test-drops-pointer-check.md`: 24 lines on
  `97d20e1`, whose one-paragraph body does carry the why.
- gitlore `2026-09-20-lint-covers-the-untracked-files-its-hash-counts.md`: 24
  lines on a 5-line message.
- shell-gotchas `2026-10-30-size-gate-review-fixes.md`: 19 lines on a 3-line
  message.
- handoff `2026-07-17-task-frame-drops-transcript.md`: 67 lines; it came from
  `16f5fc1`, which moved 26 episodes of the old `DESIGN.md` verbatim, so its
  reasoning predates its own commit. claude-plugin-dev's `c37f3cb` did the same
  for six records.

Nothing is lost by deleting, since git keeps the files; the claude-plugin-dev
brief carries a verbatim command to read one back. What the proposal needs
besides the deletion is a rule for where the why goes from now on: the commit
body, or the node.

**handoff is the case git does not cover in practice.** Its nodes cite records
as the argument behind decisions (`docs/design/decisions.md` 36 links,
`rejected-alternatives.md` 35), code and tests cite them in comments, and the
shipped `skills/handoff/references/design.md` links GitHub URLs on `main` into
`docs/changelog/`. Deleting there breaks links, not just habit. Its brief offers
three options (fold then delete, freeze the archive, point at commits) without a
default. Its `CLAUDE.md` is mid-split by a live session.

## Other dependencies found

- **plugin-craft** `skills/toolkit-release/SKILL.md:98–105` tells consumers to
  read claude-plugin-dev's `docs/changelog.md` across a pull, for the pointer
  lines that mark a breaking release (`docs/changelog.md:255`, v0.4.0). The
  replacement signal is claude-plugin-dev's call.
- **gitlore** retires inverted decisions *into* a record
  (`docs/decisions.md:278`, `docs/design.md:318`, commit `dc3b1bb`). No
  replacement is named yet.
- **sandbox-lies** NFR-3 (`docs/design.md:187–189`) records a wall-time
  measurement in the changelog at each release.
- **craft** `design-doc-writing` makes the changelog one of "six sections";
  `directive-writing` and `plan-contracts` lean on it too.
- **The in-flight size check** (`plans/2026-10-31-line-cap-gate/design.md`): D3,
  the scope line, the adoption rows for gitlore, handoff and prohibitions,
  implementation items 8 and 10, and the propagation note all change; listed,
  not resolved, in the claude-plugin-dev brief.

## Shared memory tier

`memory/ddaanet/` lives in a private repository, so this lists identifiers and a
classification only.

| path:line | kind |
| --- | --- |
| `memory/ddaanet/claude-plugin-dev.md:36–41` | a fact about this repo's changelog; rewording needed |
| `memory/ddaanet/MEMORY.md:39` | index line for that fact; rewording needed |
| `memory/MEMORY.md:24` | the same index line at the root; rewording needed |
| `memory/ddaanet/shared-claude.md:133` | the "points at the diff" rule this proposal cites; no change |
| `memory/ddaanet/shared-claude.md:272` | the word used generically; no change |
| `memory/ddaanet/shared-claude.md:368` | the word used generically; no change |
| `memory/ddaanet/todo-tool-flag-gated.md:39` | an unrelated product changelog; no change |

## Open questions

Each brief carries its own with a default; these are the ones that cut across
repos.

1. **Does the retirement cover inline changelogs** (craft, plugin-craft,
   prohibitions, sandbox-lies) as well as dated records? Decided in craft.
   Default: yes.
2. **Where does the why go?** Default: the commit body for a design-significant
   change, the node when the design's reader needs it. It needs wording that
   squares with "points at the diff, does not narrate".
3. **What signals a breaking toolkit release** once claude-plugin-dev's index is
   gone? Default: a required migration note that says so.
4. **Does `check-refs.sh` keep its `docs/changelog` default?** Default: yes,
   until handoff and gitlore have ruled.
5. **handoff:** fold, freeze or point at commits. No default.
6. **Order against the size check.** Default: retire first, so the size check
   ships with no changelog clause.
