# 2026-10-15 — The manual's dist-branch section moves to its own file

`toolkit/README.md`, the consumer manual vendored as `plugin-dev/README.md`, had
grown to 427 lines, past the 400-line cap on anything a reader takes in at one
go. The dist-branch section was the cohesive part to spin off: it matters only
to a plugin that opts in with `dist.include`, and a maintainer who has not opted
in never needs to read it.

## What changed

- The section's body moves verbatim to `toolkit/docs/dist-branch.md`, shipped in
  the dist tree as `plugin-dev/docs/dist-branch.md`. The manual keeps a
  `## The dist branch` stub, a short summary and a pointer, so the
  `#the-dist-branch` anchors in the manual's Contents and in the root
  `README.md` still resolve. The manual is now 376 lines.
- `tests/dist-tree-test.sh` lists the new shipped file, and the Layout list in
  `CLAUDE.md` gains its bullet.

## Not done here

`toolkit/release.sh` is also over the cap, at 1019 lines. Splitting it into
sourced siblings was deferred: `tests/release-test.sh` and
`tests/release-dist-test.sh` copy named toolkit files into their fixtures, so a
new sibling fails both suites until those copy lines change, and that change was
left for my human partner's call.
