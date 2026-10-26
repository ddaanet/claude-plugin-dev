# 2026-10-26 — `docs-test.sh` leaves link resolution to `check-refs.sh`

`tests/docs-test.sh` had two halves: the 400-line cap over `docs/`, and a check
that every relative `](target)` link in `docs/` and `plans/` resolves. The
second half predates `toolkit/check-refs.sh`, which resolves links over every
Markdown file git does not ignore, so the two overlapped, and the older one was
the worse reader of Markdown. Its `grep` matched links inside inline code spans,
which `check-refs.sh` skips, and it checked `plans/` and `docs/changelog/`,
which `check-refs.sh` exempts on purpose: a dated record is never revised, and a
link in one to a file deleted later is true of its day.

My human partner accepted that `plans/` and `docs/changelog/` lose link
checking, in exchange for one checker with one definition of a reference.

## Changed

- **`tests/docs-test.sh`** keeps the cap over `docs/` and nothing else. The
  pointer loop and `md_files`, which only it used, are deleted; the header and
  the final summary line describe the cap alone.
- **`CLAUDE.md`**'s quality-gate paragraph describes `docs-test.sh` as the cap
  and names link resolution as `check-refs.sh`'s. The design hub and its nodes
  never described `docs-test.sh`, so they needed no rewrite.
- **`TODO.md`** loses the item that proposed this, and two others declined as
  not real problems.
