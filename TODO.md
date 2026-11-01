## Open decisions

- Changelog retirement (plans/2026-10-31-brief-retire-dated-changelog.md; craft:design-doc-writing settles that it goes and that no new records are written). Asked, not answered, defaults stated: (4) delete the 70 records and docs/changelog.md in one commit, folding any argument the design cites into its node first, versus keeping them frozen: default delete, and my human partner should confirm this one before it runs; (6) every breaking release gets a migration note saying so in its first line: default yes; plugin-craft's toolkit-release skill reads docs/changelog.md and has its own brief, never edit that repo; (7) keep check-refs.sh's docs/changelog exemption: default keep; (8) no tag on the last commit holding records: default no tag. Order was: retirement first, but the frontmatter gate went first on my human partner's answer and writes no changelog record.

## Remaining

- check-frontmatter: delegated /code-review medium of its commit; then propose (never edit) the plugin-craft:plugin-creation standard-setup change and shell-gotchas dropping its local script.
- TASK.md is staged by the whitespace recipe and stale; commit with explicit pathspecs so it stays out, and memory too.
- Before a release: /simplify then an xhigh review of dev against main. The mktemp fix and the dogfood manual fix wait on a release to reach consumers.
