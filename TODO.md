## Remaining

- Later: bare `mktemp` fix per plans/2026-10-31-brief-bsd-mktemp-ignores-tmpdir.md; frontmatter-gate brief parked; retire-changelog brief undecided (docs/changelog.md exempt in size.exempt meanwhile, no further tracking).
- Shared path-list parser plus one rule for `plans/`: check-size skips it built in, check-refs holds it as an overridable default, and three parsers (`load_exempt`, `read_exempt`, dist.sh's `dist.include` reader) each redo the CR, comment and trailing-slash handling. Answer once, apply to both checks — tmp/simplify-altitude.md item 2.
- Skip generated and lock files in check-size by git attribute (`linguist-generated` or `-diff` via `git check-attr`) instead of the `uv.lock|package-lock.json` basename list, which misses every other ecosystem; adds an attribute to the contract, so a design fork — tmp/simplify-altitude.md item 3.
- A suite pinning `resume_preflight`'s "local tag listing failed" path (release-resume.sh, the `local tag listing failed` refusal): a fail-open mutant survives today — tmp/xhigh-release-split.md item 1.
