## Open decisions

- None pending with my human partner.

## Remaining

- Slice 15 (batched stat): collect red review tmp/slice15-red-review.md; triage high/medium, fixes back to that reviewer (a21b56cb38f3c9db6); split tests/check-size-report-test.sh along scenario groups if the review says it is near the cap; green via Haiku (ac4bc2f4f53ef5ad7), edit only toolkit/check-size.sh; then update timing claims in toolkit/manual/size-check.md and docs/references/size-check.md (and CLAUDE.md if it says per-file wc) — leave dated docs/changelog records alone; just precommit; commit; /code-review medium of the commit; fix high/medium; review the fix commit.
- Propagation held until the 0.13.0 release (my human partner's call): memory/ddaanet/shared-claude.md Code bullet, memory/ddaanet/markdown-reflow-gate.md (+ descriptions in memory/MEMORY.md and memory/ddaanet/MEMORY.md), memory/ddaanet/split-commit-alone.md — all to say the size cap is 20000 bytes / 10000 SKILL.md (all bytes, wc -c), via gitlore:commit with summary approval; craft brief craft/inbox/2026-10-31-brief-size-cap-in-bytes.md (read-only repo, brief only). Also note for craft: design-doc-writing's decisions.md floor cut was rejected here as a false gain — my human partner had the hub keep conclusions and move rationale into nodes instead.
- Before release: xhigh review of the unreleased range, per shared-claude.md.
- Later: bare `mktemp` fix per plans/2026-10-31-brief-bsd-mktemp-ignores-tmpdir.md; frontmatter-gate brief parked; retire-changelog brief undecided (docs/changelog.md exempt in size.exempt meanwhile, no further tracking).
