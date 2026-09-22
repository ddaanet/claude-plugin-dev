# Item 3.5 — execution report

New `tests/citation-test.sh`, wired into `justfile`'s `precommit` and into
`CLAUDE.md`'s Quality gate suite list; the stale/accurate `<script>.sh:<line>`
citations it finds converted to enclosing-symbol-plus-fragment form.

## The honest red is three hits, not five — a documented, pre-existing fact

Before writing anything, a whole-tree scan for the target pattern (excluding
`plans/` and `docs/changelog/`) found:

```
tests/version-guard-test.sh:17:# GIT_DIR would redirect them at this repo instead. See release-test.sh:8-13.
tests/version-guard-test.sh:365:# released (release.sh:446-455) and a bare `just release` publishes $current
tests/version-guard-test.sh:366:# rather than $proposed (release.sh:456-460), so in THIS branch every mention
```

Three, not the item's five. This is not a new discrepancy: it is exactly the
consequence recorded in
`plans/2026-09-18-deliverable-review-fixes/reports/phase-1-corrector.md`
("Consequence for Item 3.5: its citation gate will now find **three** stale
citations, not five"). The Phase-1 boundary-checkpoint corrector, dispatched
after Items 1.1–1.3 and before this item, found and converted two of the five
citations as part of its own review-and-fix pass:

- `toolkit/release.sh`'s `release.sh:780-785` citation (for "`release_preflight`
  never runs on resume") — converted to "the mode dispatch at the foot of this
  file takes the `else resume_preflight` branch".
- `tests/release-test.sh`'s `release.sh:138` citation (for the dirty-tree
  refusal preceding `release_preflight`) — converted to "its own
  `tree_is_clean "."` guard".

Both conversions are visible in `git blame` on commit `73d46daa` ("🐛 Phase 1 —
boundary checkpoint fixes"), and both target files sit outside `plans/`, so
neither touched a frozen dated artifact.

**The check built against the unconverted tree therefore reports exactly the
three hits above, not five — confirmed by running `tests/citation-test.sh`'s
core `check_citations` function before any conversion in this item.** This is
the item's honest red, adjusted for work that had already landed by the time
this item ran. It is not a defect in production code, nor a contradiction the
runbook did not anticipate — the corrector's own report states the consequence
in advance. Proceeded on that basis rather than blocking.

## The check: `tests/citation-test.sh`

New file, in `tests/docs-test.sh`'s shape (header states scope and residual
bound; a checker function; a self-fixture; a real-repo run; a sign-off line
naming what passed) with its own copy of the six-line assertion harness (`fail`,
`assert_contains`, `assert_not_contains`) every suite here carries.

- **Pattern:** `([[:alnum:]_./-]+\.(sh|just)|justfile):[0-9]+` — matches
  `<name>.sh:<digits>`, `<name>.just:<digits>` and `justfile:<digits>`.
- **`check_citations(root)`** walks `git -C "$root" ls-files -z` (NUL-delimited
  throughout — see "NUL-delimited handling" below), skips `plans/*` and
  `docs/changelog/*`, and `grep -noE`s every remaining tracked file for the
  pattern. Each hit prints a block: `citation-not-allowed: <file>:<line>`, the
  matched text, and a fixed multi-line `convention:` paragraph that states the
  replacement form, why line numbers rot, and the
  `plans/`/`docs/changelog/`/`.md` exemptions — the message is the convention's
  only standing home, so every hit carries it in full rather than pointing
  elsewhere.
- **Residual bound**, stated in the header: a citation *into* a `.md` file is
  not one of the three forbidden target forms and is never flagged, because an
  extension alone cannot tell a living document from a frozen one —
  `tests/version-guard-test.sh`'s `outline.md:118-121` stays exactly as it is.
- **Does not flag itself.** `$citation_pattern` is a regex, never a literal
  matching instance. Every sample the self-fixture plants
  (`probe_name`/`probe_ext`/`probe_line` → `printf`) and every assertion needle
  that would otherwise spell out a match (`tracked.sh:2`) is instead assembled
  from variables at runtime
  (`expected_hit="citation-not-allowed: tracked.${probe_ext}:2"`), so no
  matching substring appears literally in this file's own tracked source.
  Verified directly:
  `grep -noE '([[:alnum:]_./-]+\.(sh|just)|justfile):[0-9]+' tests/citation-test.sh`
  returns no hits.
- **Self-fixture**
  (`=== citation gate: self-fixture discriminates tracked from plans/ ===`):
  builds a throwaway repo with one planted citation in a tracked script
  (`tracked.sh`) and the identical citation in a script under `plans/`
  (`plans/tracked.sh`), and asserts `check_citations` reports the first, not the
  second, and exits non-zero. Runs on every invocation of the suite, not once by
  hand.
- **The real-repo run** (`=== citation gate: this repo ===`) is the actual gate:
  `check_citations "$repo_root"`; any hit fails the suite.

## The five conversions (three landed here, two already landed)

### 1. `tests/version-guard-test.sh:17` — leaked-git-environment citation, stale

Before:

```
# GIT_DIR would redirect them at this repo instead. See release-test.sh:8-13.
```

After:

```
# GIT_DIR would redirect them at this repo instead. See
# `tests/release-test.sh`'s own header comment, just above its own
# `unset $(git rev-parse --local-env-vars)` line, for the same explanation.
```

### 2 and 3. `tests/version-guard-test.sh:365-366` — two stale `release.sh` citations

Before:

```
# released (release.sh:446-455) and a bare `just release` publishes $current
# rather than $proposed (release.sh:456-460), so in THIS branch every mention
```

After (re-located by symbol against current `toolkit/release.sh`: both sites sit
inside `release_preflight`, the never-released bump refusal and the
first-release no-bump-argument branch respectively):

```
# released (`release.sh`'s `release_preflight`, the
# `die "'$bump_arg' bump refused: this plugin has never been released"`
# branch) and a bare `just release` publishes $current rather than $proposed
# (`release_preflight`'s first-release branch, `V="$manifest_version"` with
# no bump), so in THIS branch every mention
```

Re-located by reading `toolkit/release.sh`'s `release_preflight` directly (lines
~479–500 at the current commit): the `die` at the never-released bump-refusal
site, and the `V="$manifest_version"` / no-bump publish path immediately below
it.

### 4. `toolkit/release.sh` — `release.sh:780-785` for the resume mode dispatch

Already converted by the Phase-1 boundary-checkpoint corrector (`73d46daa`),
before this item ran. Current text: "the mode dispatch at the foot of this file
takes the `else resume_preflight` branch". Confirmed unchanged and citation-free
by `tests/citation-test.sh`'s real-repo run.

### 5. `tests/release-test.sh` — `release.sh:138` for the dirty-tree refusal

Also already converted by the same corrector pass. Current text: "its own
`tree_is_clean "."` guard — before `release_preflight` runs". Confirmed
unchanged and citation-free.

## Mutation gate

After the conversion was green, re-added one `<script>.sh:<line>` citation to a
comment in `toolkit/release.sh` (the `bump_marketplace` jq-parse note):

```diff
     # script with a raw parse error instead of a `die`.
+    # script with a raw parse error instead of a `die`. See release.sh:254
+    # for the mode dispatch mentioned above.
```

`bash tests/citation-test.sh` under the mutation:

```
=== citation gate: self-fixture discriminates tracked from plans/ ===
=== citation gate: this repo ===
citation-not-allowed: toolkit/release.sh:258
  found: release.sh:254
  convention: cite the enclosing symbol plus a short quoted fragment of
    the cited line, not a line number -- e.g. "release.sh, the mode
    dispatch in main, the --resume branch". A line number rots silently
    the moment either file is next edited, landing a reader on different
    real code with no error raised. Frozen dated artifacts under plans/
    and docs/changelog/ are exempt; a target in a .md file is not one of
    the forbidden forms, since an extension alone cannot tell a living
    document from a frozen one.
FAIL: citation gate: the citation(s) above must be converted to enclosing-symbol form

1 citation assertion(s) failed
```

The real-repo half went red, naming `toolkit/release.sh:258`. The self-fixture
half (`=== citation gate: self-fixture discriminates tracked from plans/ ===`)
printed no `FAIL` line — it stayed green, exactly as the runbook specifies.
Reverted:

```
$ git diff --quiet -- toolkit/release.sh && echo CLEAN
CLEAN
```

`bash tests/citation-test.sh` after the revert closed green again
(`citations ok …`).

## Additive falsifiability

Three assertions land in this suite: the self-fixture's positive
(`tracked.<ext>:<line>` reported), the self-fixture's negative
(`plans/tracked.<ext>` not reported), and the real-repo assertion. The mutation
gate above discharges the real-repo assertion directly. The self-fixture's
positive half is discharged by the self-fixture's own design — it is the failing
path, exercised on every run, per the task note. The negative
(`plans/`-exclusion) half needed a deliberate, separate defeat, since neither
the mutation gate nor the self-fixture's ordinary pass discriminates it on its
own:

Copied the suite to a scratch path and removed the `plans/*` arm from the
exclusion `case`:

```diff
-        plans/* | docs/changelog/*) continue ;;
+        docs/changelog/*) continue ;;
```

Ran the broken copy:

```
=== citation gate: self-fixture discriminates tracked from plans/ ===
FAIL: self-fixture: does not report the plans/-excluded planted citation: output contained 'plans/tracked.sh'
  --- output ---
citation-not-allowed: plans/tracked.sh:2
  found: probe.sh:7
  convention: cite the enclosing symbol plus a short quoted fragment of
  ...
citation-not-allowed: tracked.sh:2
  found: probe.sh:7
  ...
```

The `plans/`-exclusion assertion went red, naming `plans/tracked.sh:2` exactly
as the broken exclusion left it visible. Discarded the scratch copy; the
committed suite is unmodified.

## NUL-delimited handling and residual bound

`check_citations` reads `git -C "$root" ls-files -z` through
`while IFS= read -r -d '' rel`, so a tracked path holding whitespace is still
one path. Per-file matches are read from
`grep -noE ... | while IFS=: read -r lineno rest`, which is `grep`'s own
`\n`-per-match output, not filenames — no whitespace hazard there. Residual
bound, stated in the function's own comment: a matched *line's content*
containing an embedded NUL byte would still mis-split under `read`; no tracked
file in this repo does, and the per-file NUL-delimited walk over `ls-files` is
the guarantee actually being claimed, not full-content byte safety.

## `bash tests/doc-sync-test.sh` after the `CLAUDE.md` edit

```
=== the root README's install/update commands appear in the toolkit README ===
=== CLAUDE.md's Layout list matches toolkit/ ===

doc sync ok (5 shared command blocks, Layout matches toolkit/)
```

The `CLAUDE.md` edit added one backticked token, `` `citation-test.sh` `` (no
`toolkit/` prefix, not split across a line break), so the Layout-list check is
unaffected.

## `just precommit` — nine suites, green

Ran in the foreground (both a bare `just precommit` and the one the pre-commit
hook ran during `git commit`). Suite invocation lines from the final run, in
order:

```
bash tests/version-guard-test.sh
bash tests/check-version-test.sh
bash tests/release-test.sh
bash tests/self-release-test.sh
bash tests/update-plugin-dev-test.sh
bash tests/dist-tree-test.sh
bash tests/docs-test.sh
bash tests/doc-sync-test.sh
bash tests/citation-test.sh
ok
```

Nine suites (the eight prior plus `citation-test.sh`), closing `ok`. This item's
own sign-off line, present in that run:

```
=== citation gate: self-fixture discriminates tracked from plans/ ===
=== citation gate: this repo ===

citations ok (self-fixture discriminates tracked from plans/, no <script>.sh:<line> citation in tracked files outside plans/ and docs/changelog/)
```

`tests/release-test.sh` passed cleanly in this run (no intermittent failure
observed; not investigated further per the runbook's Scope/OUT note on the
unreproduced 2026-09-17 failure).

## Commit

```
$ git commit -m "test: Item 3.5 — a gate check refuses line-number citations into living source" -- tests/citation-test.sh justfile CLAUDE.md toolkit/release.sh tests/version-guard-test.sh tests/release-test.sh
[main 9ba5dd5] ✅ Item 3.5 — a gate check refuses line-number citations into living source
 4 files changed, 158 insertions(+), 8 deletions(-)
 create mode 100644 tests/citation-test.sh
```

Commit hash `9ba5dd5abdd3904fa856ebd0a0316dfbe8b4183c`, subject "✅ Item 3.5 — a
gate check refuses line-number citations into living source" (the commit-msg
hook's emoji prefix; the message passed to `git commit` was the plain "test: …"
line from the runbook). `toolkit/release.sh` and `tests/release-test.sh` carried
no diff at commit time (the mutation had already been reverted and confirmed
with `git diff --quiet`), so they are absent from the file list even though
named in the pathspec — as expected.

```
$ git show --stat HEAD
commit 9ba5dd5abdd3904fa856ebd0a0316dfbe8b4183c
Author: David Allouche <david@ddaa.net>
Date:   Sun Sep 20 21:28:47 2026 +0200

    ✅ Item 3.5 — a gate check refuses line-number citations into living source

 CLAUDE.md                   |   6 +-
 justfile                    |   3 +-
 tests/citation-test.sh      | 142 ++++++++++++++++++++++++++++++++++++++++++++
 tests/version-guard-test.sh |  15 +++--
 4 files changed, 158 insertions(+), 8 deletions(-)
```

`.claude/` appears nowhere in that stat. `git status --short` afterward still
shows `.claude/handoff-task.md` and `.claude/handoff-todo.md` as modified,
untouched by this item, exactly as found at the start. No `memory` gitlink
change appeared in `git status --short` (`grep -i memory` matched nothing), so
no `git add memory` was needed.

## Files touched

- `/Users/david/code/claude-plugin-dev/tests/citation-test.sh` (new)
- `/Users/david/code/claude-plugin-dev/justfile`
- `/Users/david/code/claude-plugin-dev/CLAUDE.md`
- `/Users/david/code/claude-plugin-dev/tests/version-guard-test.sh`
- `/Users/david/code/claude-plugin-dev/toolkit/release.sh` (mutation gate only;
  reverted, no net diff)
- `/Users/david/code/claude-plugin-dev/tests/release-test.sh` (no change needed;
  its one citation was already converted by the Phase-1 corrector)

## Erratum — 2026-09-22

**Wrong line:** the section heading "### 1. `tests/version-guard-test.sh:17` —
leaked-git-environment citation, stale". That citation —
`See release-test.sh:8-13`, in `tests/version-guard-test.sh`'s header — was
**not stale**. It was accurate when written and still accurate when this item
converted it, so the heading's label is wrong; the body of the section, which
shows the before/after text without claiming staleness, is not.

**Correct statement:** the citation was introduced by commit `e229e1b` ("✅ one
script under test per suite file"). At that commit, `tests/release-test.sh`
lines 8–13 are exactly the leaked-git-environment comment block, ending on line
13 with `unset $(git rev-parse --local-env-vars)`. At `9ba5dd5^` — the tree this
item converted — the same six lines still hold the same block. Measured
2026-09-22 with `git show e229e1b:tests/release-test.sh | sed -n '8,13p'` and
the same read at `9ba5dd5^`. The runbook's premise for calling it stale
(`runbook-test-suites.md`, Item 3.5: "off by one at each end — it takes in
`set -euo pipefail` and stops short of the `unset` line") does not hold at
either commit. It was converted anyway, correctly: the check allows no second
convention, stale or not.

**Where the accurate wording is.** This report's own opening line already says
"the stale/accurate `<script>.sh:<line>` citations it finds", and
`docs/changelog/2026-09-20-deliverable-review-fixes.md` ("Citing a script by
line number is now refused, by a check") records the same mix rather than
calling all five stale. `reports/phase-4-corrector.md` notes the heading
discrepancy in its verification table and left it standing because `plans/` is
frozen; this erratum is the record it pointed at, appended rather than applied
in place.

**Residual, not corrected here.** The changelog entry's count — "Four of the
five" — inherits the runbook's label for this citation. Counting only the
citations measured to have drifted, three of the five were stale: the
`release.sh:780-785`, `:446-455` and `:456-460` citations. The other two were
accurate at their introducing commits (`release.sh:138`, written in `cfb4bc2`,
lands on `tree_is_clean "."` there). The changelog is a dated record and is not
revised; the number is noted here instead.
