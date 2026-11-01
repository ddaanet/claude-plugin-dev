## Remaining

- Delegated /code-review medium of the check-frontmatter name commit and of the changelog retirement commit.
- Non-YAML stays refused: gitlore skills/resolve, handoff skills/handoff and skills/precompact must quote their description when they wire the check.
- After the release: a note in plugin-craft's inbox (standard-setup change) and shell-gotchas' inbox (drop scripts/check-frontmatter.py for the shipped recipe, which by then matches its name rules).
- TASK.md is staged by the whitespace recipe and stale; commit with explicit pathspecs so it stays out, and memory too.
- Before a release: /simplify then an xhigh review of dev against main. The mktemp fix, the dogfood manual fix and check-frontmatter wait on a release to reach consumers. toolkit/migrations/v0.15.0.md needs `just release minor`: the recipe defaults to patch. Check-frontmatter has not run under macOS bash 3.2 (heredoc inside $(...)): on the Mac run /bin/bash toolkit/check-frontmatter.sh and /bin/bash tests/check-frontmatter-interpreter-test.sh.
