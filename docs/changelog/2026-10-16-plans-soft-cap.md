# 2026-10-16 — `plans/` leaves the 400-line gate; the cap is soft for plans

The repo owner ruled on what the 400-line cap binds: it is hard for the design
docs and for implementation, and soft for plans. A plan is prospective, and once
it lands it is a frozen record nobody reads again, so splitting one
retroactively churns a document for no reader. Soft means no gate check at all:
a warning would print on every gate run, forever, for a plan that can no longer
change. Whether a plan is too long to review is judged at review.

## What changed

- `tests/docs-test.sh` counts lines only over the markdown under `docs/`
  (`docs/changelog/` included, untracked drafts included). Its pointer check
  still covers `docs/` and `plans/`, over the same file list as before.
- The `<!-- cap-ok -->` exemption is removed from `docs-test.sh`. Its only users
  were landed plans under `plans/`, which are no longer counted, and a living
  doc over the cap is split, never marked. The inert `cap-ok` markers inside
  files under `plans/` are left as they are: those are frozen records.
- `tests/line-cap-test.sh` skips `plans/*` wholesale, any file type, the way it
  skips `docs/changelog/*`. Before, it counted a non-markdown file under
  `plans/`; now it counts a non-markdown file under `docs/` only. The fixture
  keeps `plans/data.json` and `plans/plan.md` at 401 lines so the exclusion is
  pinned, and its expected report is `my big file.txt` and `tests/over-cap.sh`.
- CLAUDE.md's Quality gate paragraph describes `docs-test.sh` as the cap over
  `docs/` and pointer resolution over `docs/` and `plans/`. No present-tense
  statement in `docs/design.md` or `docs/references/` said the cap gated
  `plans/`, so none needed rewriting.
