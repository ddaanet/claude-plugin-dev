# MD013 rewrap report

Files edited: 60 (all under `plans/` and `toolkit/migrations/`). Method: each
over-long code span moved into a fenced block with no info string, indented to
the list item's content column. Where the line was a bare list item, the fence
opens on the marker line (`- ` then three backticks), because an empty marker
line is re-joined by `rumdl fmt`.

## Verification

1. Text check: the `diff` over `git show HEAD:<file>` printed nothing for all 60
   files, but it strips whitespace, backticks and `.,:;` before comparing, so it
   does not detect dropped punctuation. Punctuation that followed a converted
   span was dropped after 34 fences, because a fence's closing line cannot carry
   it; `review.md`, finding 1, lists each one. Four fences that froze a hand
   wrap as a line break are now one line each.
2. `rumdl check --no-cache plans toolkit/migrations`: 105 lines down to 2
   (below).
3. A second `rumdl fmt --no-cache` over the 60 files: `git diff --stat`
   identical before and after.
4. List-item line count (`grep -c`) equal to HEAD in all 60 files.

## Left in place (2)

- `plans/2026-09-15-first-release-version/reports/deliverable-review-code.md:84`
  (102 columns): an italic quotation holding a code span. `rumdl` treats the
  emphasis as one unbreakable element, and re-joins any manual wrap. Splitting
  the emphasis would add asterisks, so it was not done.
- `plans/2026-10-15-dist-branch-release/reports/slice2-red.md:189` (90 columns):
  a bold run, unbreakable for the same reason. A manual wrap is re-joined by
  `rumdl fmt`.

## Notes

- Files modified by others (`CLAUDE.md`, `TASK.md`, `TODO.md`, `justfile`) were
  not touched by this work.
- Nothing was staged or committed.
