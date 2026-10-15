# Slice 4 docs report

## Files changed

- docs/references/dist-branch.md (new, 138 lines): why a branch, why an
  allowlist, the line rules, plumbing and checks, pre-flight validation,
  reproducible commits, the missing-dist.sh refusal, bounds.
- docs/design.md: new "The dist branch" hub section with six conclusions;
  requirement bullet; marketplace-entry line gains the `url` source and
  `ref: dist`; resume-release line names `push_dist`; dogfood copy line states
  the allowlisted source set.
- docs/references/dogfood-sync.md: "The source set" retitled and rewritten in
  place, new subsection "With a `dist.include`" (status 0/3/1, filter order,
  symlink as file); intro and two "whole tree" phrases fixed.
- docs/references/release-flow.md: "Marketplace entry" now `url` source on
  creation, `ref: dist` on opt-in, existing `source` untouched, why `url` over
  `github`.
- docs/references/recovery.md: `push_dist` in the resumable tail (tag probe
  before branch push, landed detection by subject, resume validates again).
- CLAUDE.md: `dist-branch` added to the docs/references group list (dist.sh
  Layout entry and new suites were already present).
- toolkit/README.md: contents entries (dist.sh, release.sh, dogfood.sh sync),
  new "The dist branch" section (opt-in steps, what refuses or warns),
  Requirements mention `claude`.
- README.md: one bullet for the opt-in dist branch; dogfood bullet notes the
  allowlisted source set. No shared command block changed.
- toolkit/migrations/v0.10.0.md (new): opt-in steps; nothing changes without
  dist.include; created entries now use a url source.
- docs/changelog/2026-10-15-dist-branch-release.md (new) and its bullet at the
  top of docs/changelog.md.

## Stale statements found and fixed

- release-flow.md: "a `github` `source`" on creation, and "a `github` source ...
  is always correct".
- design.md and dogfood-sync.md: the dogfood copy as "the whole repo tree" /
  "the whole tree" (hub line, node title, intro, "syncs the whole tree");
  "Directories such as `plugin-dev/`..." qualified as the non-allowlisted case.
- recovery.md and design.md: "last four steps" of the tail.
- toolkit/README.md: contents list lacked dist.sh; dogfood.sh sync described as
  the whole tree. Nothing there said entries are created with `github`. The
  Layout list in CLAUDE.md already named dist.sh.

## Gates

- `just format-docs`: exit 0. It still prints MD013 lines it cannot fix, all in
  plans/ reports and two older lines
  (docs/changelog/2026-10-08-dogfood-no-copy-remedy-and-submodule-ignores.md:20,
  docs/references/dogfood-sync.md:138, the latter not from this edit).
- `bash tests/docs-test.sh`: docs ok (cap 400 lines, pointers resolve).
- `bash tests/doc-sync-test.sh`: doc sync ok (5 shared command blocks, Layout
  matches toolkit/).
- `bash tests/citation-test.sh`: citations ok.

## Unsure

- toolkit/README.md is now 421 lines. The 400 cap is tested only over docs/ and
  plans/, so no gate fails; it is over the soft cap and could split the dist
  section out if my human partner wants.
- The symlink behaviour (a listed symlink takes a file rule in the dogfood copy)
  is documented as the caller stated; I did not probe what rsync -a does with
  it.
- The migration note and README dist.include example use
  `.claude-plugin skills hooks scripts README.md LICENSE`, the plan's handoff
  allowlist, as an example only.
- format-docs reflowed 14 files in total, including plan reports that were
  already modified before this slice (slice3-green.md, slice3-red.md); I did not
  inspect those changes.
