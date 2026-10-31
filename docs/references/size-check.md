# The size check

Why `check-size.sh` caps a file in non-whitespace bytes, why the two caps are
fixed at 20000 and 10000, why dated changelog records are counted, why it ships
as an uncached script a consumer wires by hand, and how `size.exempt` lets a
file stay over on purpose. The reference check it is wired beside is argued in
[check-refs.md](check-refs.md); the gate cache it deliberately stays outside is
in [gates.md](gates.md). The conclusions these arguments support are listed in
[../design.md](../design.md).

The evidence lives in three plan-stage reports, cited by section rather than
copied: [the survey](../../plans/2026-10-31-line-cap-gate/reports/survey.md)
(calibration over 14 repositories),
[token-fit](../../plans/2026-10-31-line-cap-gate/reports/token-fit.md) (tokens
against four size metrics, counted with `edify tokens --model opus`) and
[mechanics](../../plans/2026-10-31-line-cap-gate/reports/mechanics.md) (the
consumer survey, scope, exemptions and rollout). The frozen
[plan-stage design](../../plans/2026-10-31-line-cap-gate/design.md) is the
record of how the decisions were reached.

## Why a size check ships at all

The shared rule caps any artifact a reader takes in at one go, and a `SKILL.md`
hub at half that. Before the check this repo held the cap as its own suites, and
nothing under `toolkit/` carried it. Six consumers kept their own checker, no
two with the same scope, and seven had none; one test file reached 3985 lines
before anyone counted. A rule that every repo restates and few enforce is the
drift this toolkit exists to remove, so the check is shipped.

## The metric: non-whitespace bytes

A file's size is its byte count after deleting space, tab, newline, carriage
return, form feed and vertical tab, computed under `LC_ALL=C`. Nothing else is
removed: a no-break space and other multi-byte whitespace count.

**Against lines.** A line is not a unit of reading cost. A changelog index of
103 lines held about 51000 non-whitespace bytes, some 26k tokens, and passed a
400-line cap by a wide margin. A line count is also honest only after a
normalizing wrap, so a line cap would have to ship a pinned formatter ahead of
the check, into consumers that have no Markdown formatter, and it still would
not cover code. On 131 files from 14 repositories, a single proportional fit to
tokens has a median absolute error of 13.3% for lines and 8.7% for
non-whitespace bytes, raw. The paired bootstrap puts non-whitespace bytes ahead
in 99% of resamples, by 4.8 points (interval -9.1 to -0.8). As the Read tool
presents a file (`cat -n`) the gap narrows to 2.2 points and is not clear of
zero, because the line-number prefix costs about 3.1 tokens a line, which lines
see and the byte count does not. Across file types the ratio is steadier:
non-whitespace bytes per token vary 1.24 times between types against 1.39 for
tokens per line, excluding the three JSON files. The files a line cap misjudges
worst are those with unusually long or short lines, which is the gaming the rule
bans by hand (token-fit, "Results").

**Against all bytes.** Bytes fit slightly better: 8.4% raw against 8.7%, which
is indistinguishable, and 7.2% against 9.5% as the Read tool presents a file,
where bytes win in 96% of resamples. That is a loss for the chosen metric and is
not explained away. Bytes are rejected for two reasons the fit does not measure.
They charge for indentation, so a cap in bytes pushes nested code flatter. And
they move when a file is re-wrapped. Non-whitespace bytes move only by the
characters a wrap adds per new line (a `>` on a blockquote continuation, a
comment leader, a `\` continuation), 1 to 2 per line and 1 to 6% of a file
(mechanics §8). That removes any need to run a reflow formatter ahead of the
check: rumdl stays for readability where a repo already runs it, and is nowhere
a precondition of the count.

**Against codepoints.** Codepoints differ from bytes by under 1% on English text
and by up to 2.8% on French prose, and there the extra bytes track extra tokens.
Counting bytes needs no UTF-8 decoding in awk.

**Against words** (15.7% raw, worse than lines) **and a two-term fit** of bytes
plus lines (7.4% raw). The second fits best and makes the cap two numbers no
author can check in their head.

### The awk self-test

Counting bytes with `length` is correct only in an awk whose `length` counts
bytes under `LC_ALL=C`. An awk that decodes UTF-8 regardless of locale would
give a two-byte character length 1 and count every file low, so every cap would
pass files it should refuse, silently. The script's first awk output line is
therefore a probe, `length` of a two-byte character, and the run fails with
`check-size: awk counts characters, not bytes` naming the awk it found unless
the probe prints 2. The only awk exercised so far is mawk; other awks, including
the second edition of onetrue-awk, are believed to count characters and are not
verified here. Failing the run is the point: a gate that reports green while
undercounting is worse than no gate.

## The caps: 20000 and 10000

Every counted file may hold 20000 non-whitespace bytes, and any file named
`SKILL.md`, at any depth, 10000. At 0.51 tokens per byte raw these are about 10k
and 5k tokens on disk, and about 12k and 6k as the Read tool presents them
(token-fit, "Measured").

The calibration is the old 400 lines at about 51 non-whitespace bytes per line.
The survey's candidate G is the smallest cap under which no file in this repo
that passes 400 lines fails (20500); it is rounded down to a round number. The
hub cap is half: 200 lines at the hub median of 45.9 bytes per line is about
9.2k (survey §6), and 10000 fails one hub of 25 surveyed.

Rounding down costs a file: this repo's own design hub, at 397 lines and 20429
bytes, failed and was split before the check shipped. The alternatives weighed
in survey §4 flip more files either way. A pooled-median cap (14000) fails 60
files that pass today, 11 of them here. The lock-inclusive no-regression cap
(64000) admits 20 files that fail today.

**Neither cap is configurable.** A need would be a reader measured to differ,
not a file that outgrew the cap. Should one appear, it becomes a per-path cap
reviewed in `size.exempt`, never an environment variable (mechanics §6). A cap
set by whatever grew last is not a calibration.

## `docs/changelog/` is counted

A dated record is checked by the commit that writes it, while its author can
still split it, and it never changes afterwards, so the cap fires once and at
the right moment. No record failed in any of the 14 repositories surveyed. The
changelog index grows by a bullet per change and does fail in three of them; its
fix is a split by period, never an exemption, because an exemption on the one
file that grows switches the cap off for exactly the file it exists for.

## A shipped script, uncached, wired by hand

The check is an executable `toolkit/check-size.sh` and a one-line `check-size`
recipe in `release.just` that nothing depends on. A consumer adds it to its
`precommit` dependencies, the shape `check-refs` already has.

**Uncached.** The check reads every file git does not ignore, a set no
consumer's sentinel hashes. Run inside a narrower cached body, a cached pass
would commit a file the check never read (mechanics §3). The same reasoning
keeps `check-refs` outside the cache, argued in [gates.md](gates.md). Running on
every call is also what forces the single pass the script makes: one listing and
one awk over every file, with counts aligned to the NUL-delimited list rather
than keyed by name, so a path holding a newline cannot forge a result. On
gitlore's 581 files one awk took 0.23 s where a process per file took 9.2 s.
This repo's own `precommit` runs it inside its cached body, after
`check-refs.sh --shipped toolkit`, because that sentinel hashes the whole tree.

**Rejected.**

- A `gates.just` recipe: six consumers do not import it, and bash inside a
  justfile string escapes `shellcheck`.
- A name carrying the unit: `check-size` names the property and survives a
  change of metric.
- A `--tree` mode like `check-refs.sh`'s: the dist tree is a subset of the
  source tree, so a pass over the source already covers it.
- A seeding flag that writes `size.exempt` for a consumer: a reason cannot be
  generated, and a placeholder defeats the rule.

Adoption blocks nothing by itself. `update.sh` edits nothing outside
`plugin-dev/`, so a consumer runs `just check-size` once unwired, splits or
exempts what it lists, and only then adds the recipe to `precommit`; the
migration note carries the steps.

## Scope

Every listed path counts unless skipped, tested in this order: symlinks;
anything not a regular file (a gitlink, a nested repo, a deleted tracked file, a
sandbox character-device mask); unreadable files, each with a stderr notice and
a count in the sign-off; binaries; the built-ins; `size.exempt` entries. The
built-ins are `plugin-dev/`, root `plans/`, and `uv.lock` and
`package-lock.json` at any depth. Untracked drafts and `docs/**` count.

Unreadable files are skipped rather than failed because the known producer is
the sandbox, and a gate red under the Bash tool and green in a hook is worse
than a hole that names itself. Lock files are built in because a tool owns them
and nobody can split one. Binaries are detected from `git ls-files --eol`, which
marks a binary on disk `w/-text`, untracked files included, from the same
listing; `grep -I` would cost a second process per file.

## `size.exempt`

A root `size.exempt` lists files over the cap on purpose and trees the cap does
not govern, one entry per line. The path runs to the first ` #`; the reason
after it is mandatory. A path matches itself and every whole component below it,
as in `dist.include`, and a trailing `/` is accepted. There are no globs: a glob
silently covers files written later.

**Two kinds of entry.** A file entry ratchets: it must name a listed file over
its cap. A directory entry declares scope: it must hold a listed file, none of
which need be over. Entries add to the built-ins and never replace them, unlike
`refs.exempt`, whose list replaces the defaults; the manual states the
difference once.

**Stale entries are refused.** Each failure prints
`size.exempt:<n>: <path> — <why>` and fails the run: an entry with no reason, an
entry matching no listed file, a file entry within its cap, and a repeat of a
built-in or of another entry. The commit that deletes or splits an exempted file
must drop its line, so a later regrowth is caught. A warning would repeat until
ignored.

**Rejected** (mechanics §5):

- A reason on the comment line above the entry: deleting the entry orphans it.
- `path|reason`: `|` is legal in a path.
- Replace semantics, as `refs.exempt` has: one entry would put every plan back
  under the cap.
- One file shared with `check-refs`: that list holds frozen history, this one
  holds overages with an end.
- `.gitattributes`: a second channel with no reason and no ratchet.
- An inline marker in the file: it needs a comment syntax and hides the decision
  in the file.

The overage report names neither `size.exempt` nor how to use it. It says to
split along a seam and not to shave prose or docstrings to fit, because an agent
reads an advertised exemption as its next step. This repo keeps no
`size.exempt`: its suites are split, never exempted.
