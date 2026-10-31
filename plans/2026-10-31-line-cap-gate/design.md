# Design: a shipped size check in non-whitespace bytes

Plan-stage design, 2026-10-31. Frozen: it records what the work will build and
why, and is not revised once the work starts. The decisions below are my human
partner's. The evidence lives in three reports beside this file, cited rather
than copied: [survey](reports/survey.md) (calibration over 14 repositories),
[token-fit](reports/token-fit.md) (tokens against four size metrics, counted
with `edify tokens --model opus`) and [mechanics](reports/mechanics.md) (the
shipped check, the consumer survey, the propagation list). The originating
request is [the handoff brief](../2026-10-30-brief-ship-the-line-cap-gate.md).

Script behaviour is stated as contracts, not code, per `craft:plan-contracts`.

## Problem

The shared ddaanet rule caps any artifact a reader takes in at one go at 400
lines, and a `SKILL.md` hub at about 200. Three things are wrong with it.

- **It does not ship.** This repo holds the check as its own suite,
  `tests/line-cap-test.sh`, plus `tests/docs-test.sh` for `docs/`. Nothing under
  `toolkit/` carries it, so six consumers keep their own checker, no two with
  the same scope (mechanics §1), and seven have none. handoff's
  `tests/hook-test.bats` reached 3985 lines before anyone counted.
- **A line is not a unit of reading cost.** A line count is blind to line
  length: handoff's `docs/changelog.md` is 103 lines and 50995 non-whitespace
  bytes, about 26k tokens, and passes a 400-line cap by a wide margin.
- **A line count is honest only after a normalizing wrap.** Shipping a line gate
  would mean shipping a pinned rumdl with `reflow-mode = "normalize"`, run ahead
  of the check, into the eight consumers that have no Markdown formatter
  (mechanics §8), and it would still not cover code.

## Decisions

### D1. The metric is non-whitespace bytes

A file's size is its byte count after deleting `[ \t\n\r\f\v]`, computed under
`LC_ALL=C`. Nothing else is removed: NBSP and other multi-byte whitespace count.

**Against lines.** On 131 files from 14 repositories, a single proportional fit
to tokens gives a median absolute error of 13.3% for lines and 8.7% for nonws,
raw. The paired bootstrap puts nonws ahead in 99% of resamples, by 4.8 points
(interval −9.1 to −0.8). As the Read tool presents a file (`cat -n`), the gap
narrows to 2.2 points and is not clear of zero, because the line-number prefix
costs about 3.1 tokens a line, which lines see and nonws does not. Across file
types the ratio is steadier: nonws per token varies 1.24× between types against
1.39× for tokens per line, excluding the three json files. The files a line cap
misjudges worst are those with unusually long or short lines, which is the
gaming the rule bans by hand (token-fit, "Results").

**Against all bytes.** Bytes fit slightly better: 8.4% raw against 8.7%
(indistinguishable), and 7.2% against 9.5% as the Read tool presents a file,
where bytes win in 96% of resamples. That is stated, not explained away. Bytes
are rejected for two reasons the fit does not measure. They charge for
indentation, so a cap in bytes pushes nested code flatter. And they move when a
file is re-wrapped. Non-whitespace bytes move only by the characters a wrap adds
per new line (a `>` on a blockquote continuation, a comment leader, a `\`
continuation), which mechanics §8 bounds at 1–2 per line, 1–6% of a file. That
removes the requirement to run a reflow formatter ahead of the check: rumdl
stays for readability where a repo already runs it, and nowhere becomes a
precondition of the count.

**Against codepoints.** Codepoints differ from bytes by under 1% on English text
and by up to 2.8% on French prose (mechanics §8), and there the extra bytes
track extra tokens. Counting bytes needs no UTF-8 decoding in awk.

**Against words** (15.7% raw, worse than lines) and **a two-term fit** of nonws
plus lines (7.4% raw): the second fits best but makes the cap two numbers no
author can check in their head.

### D2. Two caps, fixed

- **20000** non-whitespace bytes for every counted file.
- **10000** for any file named `SKILL.md`, at any depth.

At 0.51 tokens per nonws byte raw, these are about 10k and 5k tokens on disk,
about 12k and 6k as the Read tool presents them (token-fit, "Measured").

The calibration is 400 lines at about 51 nonws per line: survey candidate G, the
smallest cap under which no file in this repo that passes 400 lines fails
(20500), rounded down to a round number. The hub cap is half: 200 lines at the
hub median of 45.9 nonws per line is about 9.2k (survey §6), and 10000 fails one
hub of 25 surveyed.

**The cost of rounding down** is that this repo's own `docs/design.md`, at 397
lines and 20429 non-whitespace bytes, fails and is split as part of this work
(below). The alternatives weighed in survey §4 trade more files flipping either
way: a pooled-median cap (14000) fails 60 files that pass today, 11 of them
here; the lock-inclusive no-regression cap (64000) admits 20 files that fail
today.

**Neither cap is configurable.** A need would be a reader measured to differ,
not a file that outgrew the cap; should one appear, it becomes a per-path cap
reviewed in `size.exempt`, never an environment variable (mechanics §6).

### D3. `docs/changelog/` is counted

A dated record is checked by the commit that writes it, while its author can
still split it, and it never changes afterwards, so the cap fires once and at
the right moment. No record fails today in any of the 14 repositories. The
changelog *index*, `docs/changelog.md`, grows by a bullet per change and fails
in gitlore, handoff and prohibitions. Its fix is a split by period, never an
exemption.

### D4. A shipped script, uncached, wired by hand

An executable `toolkit/check-size.sh`, wrapped by a one-line recipe in
`release.just` that nothing depends on:

```just
check-size:
    bash "{{toolkit_prefix}}/check-size.sh"
```

Consumers wire `precommit: check-refs check-size`, the shape `check-refs`
already has. The check runs uncached: it reads every file git does not ignore, a
set no consumer's sentinel hashes, so inside a narrower cached body a cached
pass would commit a file the check never read (mechanics §3). Running on every
call is what forces a single pass (D5's contract): on gitlore's 581 files, one
awk over the list took 0.23 s where a process per file took 9.2 s.

**Rejected:** a `gates.just` recipe (six consumers do not import it, and bash
inside a justfile string escapes `shellcheck`); a name carrying the unit
(`check-size` names the property, and survives a metric change); a `--tree` mode
(the dist tree is a subset of the source tree).

### D5. Cross-repo wording lands with the gate

The shared rule and the memory facts that restate it are reworded when the gate
ships, not before (Propagation, below). craft gets a brief. Other consumers
learn of the check from the migration note; no brief goes to them.

## The script's contract

**Inputs.** No arguments. The root is `git rev-parse --show-toplevel`. The
listing is `git ls-files -z -co --exclude-standard`, read from disk, never the
index.

**Counting.** One listing and one counting process for the whole tree. Counts
are aligned to the NUL-delimited list, not keyed by name, so a path holding a
newline cannot forge a result line. Empty files are dropped before the count,
since awk sees no record in them. With newline as the record separator, deleting
`[ \t\r\f\v]` per record and summing lengths equals
`LC_ALL=C tr -d ' \t\n\r\f\v' < FILE | wc -c`, which is the reference count the
fixture suites assert against.

**Scope.** Every listed path counts unless skipped, tested in this order:

1. symlinks;
2. anything not a regular file: a gitlink, a nested repo, a deleted tracked
   file, a sandbox char-device mask;
3. unreadable files, each with a stderr notice and a count in the sign-off;
4. binaries;
5. built-ins: `plugin-dev/`, root `plans/`, and `uv.lock` and
   `package-lock.json` at any depth;
6. `size.exempt` entries.

Untracked drafts and `docs/**` count, `docs/changelog/` included. Unreadable
files are skipped rather than failed because the known producer is the sandbox,
and a gate red under the Bash tool and green in the hook is worse than a hole
that names itself. Lock files are built in because a tool owns them and nobody
can split one; ghmem's `uv.lock` is 90900.

**Exemptions.** A root `size.exempt`, one entry per line:

```text
# Files over the size cap on purpose, and trees it does not govern.
tests/test_checkpoint_legacy.py  # deleted by the legacy pass, TODO.md
docs/superpowers  # frozen superpowers plans and specs
```

- The path runs to the first ` #`, trailing blanks trimmed; the reason after it
  is mandatory and non-empty. Comment lines, blank lines and `\r` are skipped.
- A path matches itself and every whole component below it, as in
  `dist.include`. No globs: a glob silently covers files written later.
- A **file entry** ratchets: it must name a listed file over its cap. A
  **directory entry** declares scope: it must hold a listed file, none of which
  need be over. Entries add to the built-ins and never replace them, unlike
  `refs.exempt`, which the manual states once.
- Refused, each with one line `size.exempt:<n>: <path> — <why>` and a failed
  run: an entry with no reason, an entry matching no listed file, a file entry
  within its cap, and a repeat of a built-in or of another entry.

Refusing stale entries is the ratchet: the commit that deletes or splits an
exempted file must drop its line, and a later regrowth is caught. A warning
would repeat until ignored. **Rejected** (mechanics §5): a reason on the comment
line above (deleting the entry orphans it), `path|reason` (`|` is legal in a
path), replace semantics, one file shared with `check-refs` (that list holds
frozen history, this one overages with an end), `.gitattributes`, and an inline
marker in the file.

**Report.** Failures go to stderr, one line each, in `LC_ALL=C` path order:

```text
oversized-file: <path>: <n> non-whitespace bytes > 20000
oversized-file: <path>: <n> non-whitespace bytes > 10000 (SKILL.md hub)
```

`<n>` is exact. One hint line follows: split along a seam, and do not shave
prose or docstrings to fit. It does not name `size.exempt`, because an agent
reads an advertised exemption as its next step. Any other failure prints
`check-size: <reason>` and exits 1; an empty listing is a failure, never a pass.

**Sign-off.** On success, one stdout line naming every check and its count:

```text
check-size: cap 20000 non-whitespace bytes: <n> files; hub cap 10000:
<h> SKILL.md; size.exempt: <e> entries, each with a reason and still needed;
skipped: <p> plans/plugin-dev/lockfiles, <b> binary, <l> symlinks,
<r> unreadable
```

(One physical line; wrapped here for the page.)

## Adoption

From `tmp/line-cap-survey/adoption-20k.txt`, which applies the lock-file skip
and counts `docs/changelog/`. "Lines" is the count over 400 lines today. A
`docs/superpowers` directory entry clears the frozen plans in candidature and
ghmem.

| repo              | lines | size | files over the size caps                |
| ----------------- | ----: | ---: | --------------------------------------- |
| candidature       |     7 |    5 | `DESIGN.md`; 4 `docs/superpowers` plans |
| claude-plugin-dev |     0 |    1 | `docs/design.md` (20429)                |
| cwd-safety        |     2 |    2 | `scripts/cwd-safety.py`, its test       |
| ghmem             |     7 |    3 | `docs/ghmem-decisions.md`; 2 plans      |
| gitlore           |     1 |    3 | `docs/changelog.md`, a node, a hub      |
| handoff           |     3 |    3 | `CLAUDE.md`, changelog index, a test    |
| prohibitions      |     3 |    2 | `docs/changelog.md`, `docs/design.md`   |
| sandbox-lies      |     0 |    1 | `docs/design.md` (20032)                |

craft, gitmoji, onekeys, plugin-craft, prompt-fzf and shell-gotchas have no file
over either cap. Per repo, the work on adoption:

- **candidature:** one directory entry, then split `DESIGN.md` (80450).
- **cwd-safety:** split both files, or exempt them with a reason.
- **ghmem:** one directory entry, then split `docs/ghmem-decisions.md`.
- **gitlore:** split the changelog index by period,
  `docs/references/index-composition.md`, and the `memory-writing` hub (12690
  against 10000).
- **handoff:** split the changelog index by period; exempt
  `tests/test_checkpoint_legacy.py` and `CLAUDE.md`, the two its `TODO.md`
  already names, each with that reason.
- **prohibitions:** split the changelog index by period and `docs/design.md`.
- **sandbox-lies:** split `docs/design.md`. Its 19424-byte fixture passes, so
  the fixtures directory entry mechanics §10 foresaw is not needed.

Retiring a consumer's own checker is optional. ghmem's, sandbox-lies's and
shell-gotchas's are standalone and retire whole; craft's `check-skills.py`,
gitlore's `check-docs-links.py` and cwd-safety's `check-docs` lose only their
size half.

## This repo's work

The toolkit passes its own check before it ships, and this repo keeps no
`size.exempt`: its suites are never exempted.

1. **Split `docs/design.md`**, in a commit of its own carrying only the move and
   the inbound references it forces (`split-commit-alone`). It must come in
   under 20000 with room for a new size-check section of about 1500, so the seam
   removes well over the 429-byte overage. The conclusions stay in the hub: they
   are what has to be true, and together they are the system overview, so moving
   them anywhere (a `docs/decisions.md`, or the head of each node) replaces the
   overview with a routing table. The seam runs inside the bullets instead. The
   hub states that a bullet is a conclusion and its node holds the argument, but
   many of the 67 bullets carry their argument after the conclusion: the
   mechanism, the bug, the "because". The longest, at about 450 bytes, is the
   `install.sh` bullet. That text is needed when the decision is changed, which
   is when its node is opened, so it moves to the node, merged with what the
   node already says. Each bullet keeps its conclusion and the invariant a
   reader must not break. This relocates argument; it is not shaving, and no
   conclusion is dropped or shortened past what it asserts.
2. **The script and recipe.** `toolkit/check-size.sh`, executable, to the
   contract above; the `check-size` recipe and a header line in `release.just`.
3. **Retire the two suites into fixture suites.** `tests/line-cap-test.sh` and
   `tests/docs-test.sh` are removed; their self-scan becomes the precommit call,
   and their fixtures move into three suites, one script under test each, each
   with its own harness:
   - `check-size-scope-test.sh`: each skip of the scope list, and paths holding
     a space or a newline;
   - `check-size-exempt-test.sh`: each refusal, a directory entry, additivity to
     the built-ins;
   - `check-size-report-test.sh`: line format, the hub cap, order, exact counts
     against the `tr | wc` reference, exit codes, the empty listing and the
     sign-off.

   Each fixture is over the cap exactly where only its own exclusion keeps it
   out, so every exclusion has a red. The report suite pins both caps as
   literals; the other two read them from the script.
4. **`justfile`.** `precommit` runs `bash toolkit/check-size.sh` inside the
   cached body, after `check-refs.sh --shipped toolkit`, since this repo's
   sentinel hashes `:/` minus `memory`. The script joins the `bash -n` and
   `shellcheck` lists, the suite lists swap the two retired suites for the three
   new ones, and the line-21 comment drops "line-cap". `_import-check` asserts
   that `just --dry-run check-size` prints exactly
   `bash "plugin-dev/check-size.sh"`. The `format-docs` doc comment (line 159)
   and its body comment (163–164) stop claiming the wrap makes a count
   meaningful: the wrap is for an 80-column read.
5. **`.rumdl.toml`** header: the same correction, naming no suite.
6. **`tests/dist-tree-test.sh`** adds `check-size.sh` and `manual/size-check.md`
   to the shipped list and an executable-bit block for the script.
7. **`tests/doc-sync-test.sh`** fails until `CLAUDE.md`'s Layout list has a
   bullet for each new shipped path.
8. **`CLAUDE.md`.** Layout bullets for `toolkit/check-size.sh` and
   `toolkit/manual/size-check.md`; line 104's "400-line cap" becomes "the size
   cap"; the suite list (189–193) names the three new suites in place of
   `docs-test.sh` and `line-cap-test.sh`; "No suite file passes 400 lines"
   (209–211) becomes "No suite file passes 20000 non-whitespace bytes", failed
   by `check-size.sh`; the changelog-wrap paragraph (319–326) keeps the wrap and
   replaces "would leave the line cap unmeasurable" with "would leave the
   longest records the only unwrapped prose in `docs/`".
9. **`docs/references/gates.md:108`** names "the line cap" among the checks once
   read from the index; it becomes "the size cap", a check that still reads from
   disk.
10. **Design record.** A node `docs/references/size-check.md` carries D1–D4's
    arguments; the hub gains the conclusion lines; a dated changelog record and
    its index bullet go with it.
11. **The manual.** A chapter `toolkit/manual/size-check.md`: the metric, the
    caps, the scope, `size.exempt` and its difference from `refs.exempt`, the
    report. `toolkit/README.md` gains a stub section and a Contents bullet.
12. **The migration note** `toolkit/migrations/vX.Y.Z.md`, for the release that
    ships the check, carrying the rollout below.

Two files here sit close under the cap: `docs/references/recovery.md` and the
changelog index, `docs/changelog.md`. Neither blocks the work; the index's split
by period comes due within a few releases.

### Rollout

Adoption blocks nothing by itself: `update.sh` edits nothing outside
`plugin-dev/`, and nothing depends on `check-size`. After
`just update-plugin-dev` and `just --list`, a consumer:

1. runs `just check-size` once, unwired, and reads the list;
2. splits each listed file, or exempts it with a reason, using a directory entry
   for a frozen or generated tree;
3. adds `check-size` to `precommit`'s dependencies;
4. commits apart from the subtree merge, with precommit green.

The note names the recipe, so a consumer recipe of that name is renamed first
(just refuses a recipe defined in both an import and the importer); lists the
checkers that can retire; and states the proof that it worked: `just check-size`
prints the sign-off, and `just precommit` passes. There is no seeding flag: a
reason cannot be generated, and a placeholder defeats the rule.

## Propagation

Changed when the gate ships, not before. Dated changelog records are not
revised. `memory/` is a gitlink into the shared store: these edits are made
there, in the session that ships the gate.

**`memory/ddaanet/shared-claude.md`, the "Code" bullet.** Replace it whole:

> **20000 non-whitespace bytes cap any artifact a reader takes in at one go** —
> source files, `references/` nodes, plans, design docs and PRs — and
> **10000 a `SKILL.md` hub**, which is paid on every invocation while a node is
> opt-in. That is about 400 and 200 wrapped lines of prose, and about 10k and 5k
> tokens. For design docs and implementation the cap is *hard*; for plans it is
> soft. It exists for context management, and a file that reaches it usually
> holds cohesive content to spin off — find that seam rather than arguing the
> overage. Never satisfy it quietly by shaving docstrings and prose: that is
> borrowing against the split, and a file parked at exactly its cap has stopped
> emitting the signal. Whitespace does not count, so re-wrapping neither games
> nor needs to precede the count; a 300-character line still fails review as
> unreadable. The toolkit's `check-size` enforces both caps, reporting
> `oversized-file: <path>: <n> non-whitespace bytes > <cap>`. The full argument
> ships in `craft:plan-contracts`.

**`memory/ddaanet/markdown-reflow-gate.md`.** Drop the body paragraph "A
line-count cap is honest only against `normalize` …" and replace it with: "A
size cap no longer depends on the wrap: the toolkit's `check-size` counts
non-whitespace bytes, which a reflow does not move." In the description, replace
"`reflow-mode = \"normalize\"` re-fills paragraphs and is what a line-count cap
is measured against, formatter check ahead of the line guard" with
"`reflow-mode = \"normalize\"` re-fills paragraphs, the only mode that converges
widths". The description is repeated verbatim in `memory/MEMORY.md` (line 29)
and `memory/ddaanet/MEMORY.md` (line 44); all three change together.

**`memory/ddaanet/split-commit-alone.md`.** Line 3, "a doc over its line cap"
becomes "a doc over its size cap"; line 11, "for a line cap or a seam" becomes
"for a size cap or a seam".

**craft** is read-only from here. It receives
`craft/inbox/2026-10-31-brief-size-cap-in-nonws-bytes.md`, which lists the
places in `skills/plan-contracts/` and `scripts/check-skills.py` (mechanics §2,
§11). gitlore's D55 rejects tokens as a metric because "lines are exact, free
and reproducible", which holds equally for non-whitespace bytes; it reaches
gitlore through the migration note like every other consumer.

## Open questions

1. **Binary detection.** `git ls-files -z --eol` marks a binary on disk
   `w/-text`, untracked files included (git 2.47), from the same listing;
   `grep -I` under `LC_ALL=C` is the alternative. Default: `--eol`, since it
   costs no second process. A fixture in the scope suite pins whichever ships.
2. **How far the bullets go back to conclusions.** Only as far as the overage
   plus the new section needs (about 2 KB of the decisions' 15.6 KB), or a full
   pass over all 67 bullets. Default: a full pass, done once, so the hub gains
   room for future decision groups and the next overage is not met by another
   partial trim.
