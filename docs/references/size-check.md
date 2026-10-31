# The size check

Why `check-size.sh` caps a file in bytes, why the two caps are fixed at 20000
and 10000, why dated changelog records are counted, why it ships as an uncached
script a consumer wires by hand, and how `size.exempt` lets a file stay over on
purpose. The reference check it is wired beside is argued in
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

## The metric: all bytes

A file's size is what `wc -c` prints for it: every byte, whitespace, indentation
and newlines included, counted one file at a time. Nothing is deleted first and
no locale or awk is involved, so the count is the file's size on disk.

**Chosen for how the agent pays.** The target is tokens as the Read tool
presents a file (`cat -n`), which prefixes every line with its number. On 131
files from 14 repositories, a single proportional fit gives 2.052 bytes per
token as presented, with a median absolute error of 7.2% (token-fit, "Pooled
fit, readtool"). The prefix costs about 3.1 tokens a line, and bytes track line
count through newlines and indentation, so they carry the charge without a
second term. A two-term fit of bytes plus lines fits better still (6.9% as
presented, 8.2% raw; token-fit, "Two predictors") and makes the cap two numbers
no author can check in their head.

**Against non-whitespace bytes.** They fit 9.5% as presented, and bytes beat
them in 96% of resamples of the paired bootstrap. Raw, the two are
indistinguishable (8.4% against 8.7%), so the choice rests on the presented
case, the one an agent pays. Non-whitespace bytes also go blind to the newlines
and indentation the prefix and the reading cost scale with. Re-wrapping moves a
byte count little, since a wrap swaps a space for a newline; it moves by what
each new line repeats: its indentation, as on a list continuation or a nested
comment, and the characters a wrap adds (a `>` on a blockquote continuation, a
comment leader, a `\` continuation). The bound of mechanics §8 does not carry
over, because it counted no indentation. No reflow formatter has to run ahead of
the check: rumdl stays for readability where a repo already runs it, and is
nowhere a precondition of the count. Indentation is counted, which is right: the
agent pays for it.

**Against lines.** A line is not a unit of reading cost. A changelog index of
103 lines held about 51000 non-whitespace bytes, some 26k tokens, and passed a
400-line cap by a wide margin. A line count is also honest only after a
normalizing wrap, so a line cap would have to ship a pinned formatter ahead of
the check, into consumers that have no Markdown formatter, and it still would
not cover code. As presented, lines fit at a median error of 11.3% against 7.2%
for bytes; raw, 13.3% against 8.4%. The files a line cap misjudges worst are
those with unusually long or short lines, which is the gaming the rule bans by
hand (token-fit, "Measured").

**Against codepoints.** Codepoints differ from bytes by under 1% on English text
and by up to 2.8% on French prose, and there the extra bytes track extra tokens.
A byte count needs no UTF-8 decoding.

**Against words** (16.8% as presented, worse than lines).

## The caps: 20000 and 10000

Every counted file may hold 20000 bytes, and any file named `SKILL.md`, at any
depth, 10000. The target is a file of about 10k tokens as an agent reads it, and
a hub of about 5k. At 2.052 bytes per token as presented, 20000 bytes is about
9.7k tokens and 10000 about 4.9k (token-fit, "Pooled fit, readtool").

The previous cap, 20000 non-whitespace bytes, was about 12k tokens as presented
at 0.6006 tokens per such byte, looser than the target; the caps stay at the
same numbers and the metric tightens them. They descend from the old 400 lines
at about 51 non-whitespace bytes per line. The survey's candidate G is the
smallest cap under which no file in this repo that passes 400 lines fails
(20500); it was rounded down to a round number. The hub cap is half: 200 lines
at the hub median of 45.9 bytes per line is about 9.2k (survey §6).

Survey §4 weighed the alternatives under the non-whitespace metric, and each
flips more files either way. A pooled-median cap (14000) fails 60 files that
pass today, 11 of them here. The lock-inclusive no-regression cap (64000) admits
20 files that fail today.

**Neither cap is configurable.** A need would be a reader measured to differ,
not a file that outgrew the cap. Should one appear, it becomes a per-path cap
reviewed in `size.exempt`, never an environment variable (mechanics §6). A cap
set by whatever grew last is not a calibration.

## `docs/changelog/` is counted

A dated record is checked by the commit that writes it, while its author can
still split it, and it never changes afterwards, so the cap fires once and at
the right moment. No record failed in any of the 14 repositories surveyed. The
changelog index grows by a bullet per change and does fail in three of them.
This repo's own index, `docs/changelog.md`, is over the cap, and its root
`size.exempt` exempts it, "retired or split once
plans/2026-10-31-brief-retire-dated-changelog.md is decided".

## A shipped script, uncached, wired by hand

The check is an executable `toolkit/check-size.sh` and a one-line `check-size`
recipe in `release.just` that nothing depends on. A consumer adds it to its
`precommit` dependencies, the shape `check-refs` already has.

**Uncached.** The check reads every file git does not ignore, a set no
consumer's sentinel hashes. Run inside a narrower cached body, a cached pass
would commit a file the check never read (mechanics §3). The same reasoning
keeps `check-refs` outside the cache, argued in [gates.md](gates.md). Running on
every call has a cost: one listing and one batched `stat`, which reads each
file's size from its metadata without reading the file. On gitlore the run takes
about 0.35 s, against about 2.8 s for one `wc -c` per file, measured on Linux
under load. The flavour is picked once, when the script loads: GNU coreutils
`stat --version` exits 0 and takes `-c %s`, the BSD and macOS one fails it and
takes `-f %z`. For a regular file the size `stat` reports is the count `wc -c`
prints. The names reach `xargs -0` NUL-delimited and `stat` after `--`, so a
name starting with a dash is read as the path it is, and counts align with the
list by position rather than being keyed by name, so a path holding a newline
cannot forge a result; a count of lines unequal to the list fails the run. This
repo's own `precommit` runs it inside its cached body, after
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
a count in the sign-off; binaries; the built-ins. The built-ins are
`plugin-dev/`, root `plans/`, and `uv.lock` and `package-lock.json` at any
depth. Untracked drafts and `docs/**` count. A `size.exempt` entry skips
nothing: it forgives an overage after the count.

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
reads an advertised exemption as its next step.
