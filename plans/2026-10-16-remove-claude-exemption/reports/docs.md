# Docs: remove the .claude/ clean-tree exemption

## Files touched

- docs/design.md: the conclusion "exempts `.claude/` and the gitlore memory
  gitlink" now reads "exempts only the gitlore memory gitlink". It states that a
  tracked `.claude/` file refuses, that the one reason (staged handoff frames)
  now lives in tracked root files, the cost (dirty `.claude/settings.json` stops
  a release), and that the exemption list prints only when one applies. The
  self-release conclusion is now "exclusion is a literal pathspec" (singular).
- docs/references/recovery.md: the section "The clean-tree check excludes the
  agent's own working state" is now "The clean-tree check exempts only the
  memory gitlink". The `### .claude/` subsection is now "`.claude/` is not
  exempt". It carries why the reason is gone, why the exemption is removed (the
  earlier "set of files depends on skills" argument is overridden, not
  answered), the accepted costs (`settings.json`, `gitlore-hook-setup`, dirty
  TASK.md/TODO.md; untracked and ignored files unaffected), and the conditional
  exemption list and the removed `.claude-plugin/` note. The memory subsection
  is unchanged except its last claim: a repo without the submodule "gets no
  exclusion at all" (was: the `.claude` exclusion and nothing more). The 'at the
  path separator' paragraph is replaced by a short statement that no
  `.claude-plugin/` note is needed.
- docs/references/self-release.md: heading and body now describe one literal
  exclusion (`memory`), and its cross-reference names the renamed recovery.md
  section.
- toolkit/README.md (~l.356): "`.claude-plugin/` is not exempt from the
  clean-tree check" is now "the clean-tree check refuses a dirty manifest".
- docs/changelog/2026-10-16-clean-tree-drops-dot-claude.md: new record (why it
  could go, costs, what changed, how a consumer picks it up).
- docs/changelog.md: index bullet added at the top.

No hits needing change in README.md, CLAUDE.md, docs/references/distribution.md
or toolkit/docs/ (they mention `.claude/` only as the repo's working environment
or `settings.json`). docs/references/recovery.md l.201 ("exemptions that did not
save them") stays true as written.

## Supersede convention

`grep -i supersed` over docs/changelog.md and docs/changelog/ found no
convention (no hits for "supersed" in any entry). Closest precedent is prose
naming of a reversal (e.g. 2026-08-14 "a reversal", 2026-09-17 "the overturned
decision"). The new record therefore opens by naming and linking the entry it
supersedes. The index bullet says "supersedes 2026-09-01". The 2026-09-01 record
is untouched.

## Tests

`just format-docs` ran (it also reflowed other plans/ files, none of which show
as modified). `bash tests/docs-test.sh`, `doc-sync-test.sh`, `citation-test.sh`,
`line-cap-test.sh` all pass. Largest files: docs/references/recovery.md 385
lines, toolkit/README.md 378, docs/design.md 347. Nothing over 400.

Caveat: I added the reasoning in recovery.md's "Why the exemption is removed
rather than narrowed" paragraph from the brief's wording; the last sentence
(maintainer's view that the cost of the occasional refusal is smaller) is my
paraphrase of the decision and worth a read.
