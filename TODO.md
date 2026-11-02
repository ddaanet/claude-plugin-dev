## Remaining

- On macOS, after the teleport: run `/bin/bash toolkit/check-frontmatter.sh` and `/bin/bash tests/check-frontmatter-interpreter-test.sh`; check-frontmatter has a heredoc inside `$(...)` never run under bash 3.2. Also run the other three `tests/check-frontmatter-*-test.sh` suites and `tests/mktemp-template-test.sh`, since the mktemp fix is unverified on macOS too.
- Before a release: /simplify, then an xhigh review of dev against main. The mktemp fix, the dogfood manual fix and check-frontmatter reach consumers with that release, which needs `just release minor` because `toolkit/migrations/v0.15.0.md` exists and the recipe defaults to patch.
- After the release: a note in plugin-craft's inbox (standard-setup change) and in shell-gotchas' inbox (drop `scripts/check-frontmatter.py` for the shipped recipe, whose name rules now match).
- gitlore `skills/resolve` and handoff `skills/handoff` and `skills/precompact` must quote their description when they wire the check, since non-YAML stays refused.
