# 2026-10-18 — A shipped reference check, `check-refs.sh`

A Markdown link broke silently when its target moved, and in a plugin with a
`dist.include` a link from a shipped file to an unlisted one resolved in the
repo and dangled in the `dist` tree users install. A survey of the consumer
repos (`tmp/reference-survey.md`, not tracked) found links nearly clean, the few
broken ones in plans and one dated record, and a handful of shipped files
linking out of their planned sets. It also found that backticked paths are not a
reference syntax: they name the reader's files, examples and removed files as
often as live ones. My human partner decided on a check over links only, run at
commit time and again by the dist build.

## Added

- **`toolkit/check-refs.sh`.** Reads every Markdown file on disk git does not
  ignore, tracked or not, skipping `plugin-dev/` and submodules, and refuses a
  link, image or reference definition whose relative target is missing. Files
  under `docs/changelog/` and `plans/` are exempt, or those a root `refs.exempt`
  names. With a `dist.include`, read through `dist.sh paths`, or with
  `--shipped <path>...`, a reference from a shipped file must reach a shipped
  file that exists, exemptions aside. `--tree <tree>` checks a built tree from
  the object store. One `file:line: target — reason` line per offender; a pass
  names both checks and their counts.
- **`dist.sh tree` runs it on the tree it builds,** each refusal one `dist:`
  line, before the warnings, so a release refuses before any commit or tag.
- **A `check-refs` recipe in `release.just`,** depended on by nothing; the
  consumer wires `precommit: check-refs`. `migrations/v0.12.0.md` says so, and
  warns that a dist release now refuses a shipped link out of the set.
- **This repo's `precommit` runs `check-refs.sh --shipped toolkit`.** It found
  nothing to fix outside the exempt `plans/` and `docs/changelog/`.
- **`tests/check-refs-{syntax,scan,shipped}-test.sh`,** and a `dist-build`
  scenario for the build refusal. Written first and run red against no script.

- **Review fixes, before the first commit.** A target exists when the scan's own
  `git ls-files -co --exclude-standard` listing holds it (or a directory holding
  a listed path, or a path inside a submodule that is on disk), not when `-e`
  finds it: an ignored target is refused as "is ignored by git", a case-folded
  one on a case-insensitive disk as missing, and an untracked one passes, so
  precommit and release differ only on a link to an uncommitted file. A target
  above the root is refused as "leaves the repository" in both modes; the root
  counts as shipped. HTML comments and `\[escaped\]` brackets are skipped, and a
  backtick run with a backtick after it is a span, not a fence.

## Changed

- **`docs/design.md`'s limitations moved to `references/limitations.md`.** The
  hub keeps one line per limitation, as it does per decision. The new section
  and requirement would have taken the hub past its 400-line cap, and the
  limitation bodies were the cohesive block to split off.
- **The `toolkit/docs/dist-branch.md` recommendation** to list `docs` when a
  README links into it, which the check now enforces.

## Choices the brief left open

- A root `/path` target is skipped, not resolved from the root.
- `refs.exempt` replaces the defaults rather than adding to them; an empty one
  exempts nothing. Prefixes match whole path components.
- A shipped file's missing target is reported once, as "does not exist".
- A fence is recognised after any indent, so a fenced block in a list item is
  skipped; an indented code block is still read as prose.
