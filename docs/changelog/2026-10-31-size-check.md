# 2026-10-31 — A shipped size check, `check-size.sh`, in non-whitespace bytes

The 400-line cap on any artifact a reader takes in at one go, and about 200 on a
`SKILL.md` hub, lived in this repo as `tests/line-cap-test.sh` and
`tests/docs-test.sh` and shipped nowhere. Six consumers kept checkers of their
own, no two alike, and seven had none. A line is also a poor unit: a changelog
index of 103 lines held about 51000 non-whitespace bytes, and a line count is
honest only after a normalizing wrap. A plan-stage design, with three reports on
calibration, token fit and mechanics, decided the replacement; it is
[plans/2026-10-31-line-cap-gate/design.md](../../plans/2026-10-31-line-cap-gate/design.md).

## Added

- **`toolkit/check-size.sh`** caps every file git does not ignore, read from
  disk, at 20000 non-whitespace bytes, and any `SKILL.md` at 10000. One listing
  and one awk count the whole tree. A failure is
  `oversized-file: <path>: <n> non-whitespace bytes > <cap>`; a pass prints one
  sign-off line naming every check and its count.
- **A root `size.exempt`**, one entry per line with a mandatory reason. File
  entries must be over their cap and directory entries must hold a listed file;
  stale, repeated and reasonless entries fail the run.
- **A `check-size` recipe in `release.just`** that nothing depends on. This
  repo's `precommit` runs the script inside its cached body.
- **A self-test**: the script refuses an awk whose `length` counts characters,
  since such an awk would count every file low and pass it.

## Changed

- **`tests/line-cap-test.sh` and `tests/docs-test.sh`** are replaced by suites
  for the script, and the 400-line statements in `CLAUDE.md` and
  [gates.md](../references/gates.md) became the size cap.
- **The design** gains [size-check.md](../references/size-check.md), holding the
  arguments, and a hub section with one conclusion per decision.

## Reasoning

Non-whitespace bytes fit tokens at a median error of 8.7% against 13.3% for
lines on 131 files; all bytes fit about the same and are rejected because they
charge for indentation and move when a file is re-wrapped. The caps are the old
400 lines at about 51 bytes per line, rounded down, which made this repo's own
design hub fail by 429 bytes and be split before the check shipped.
`docs/changelog/` is counted, because a dated record is checked once, by the
commit that writes it. The script is uncached and wired by hand for the reason
`check-refs` is: it reads a set no consumer's sentinel hashes.
