## Remaining

- On macOS, before the release: rerun `/bin/bash tests/check-frontmatter-interpreter-test.sh` and the block, fields and scope suites with a directory holding a `bash` symlink to `/bin/bash` first on PATH, since the suites call a bare `bash` and Homebrew's comes first. All passed under bash 3.2 before the simplify pass, which replaced the heredoc-in-`$(...)` and the checker's list handling.
- Before a release: /simplify, then an xhigh review of dev against main. The mktemp fix, the dogfood manual fix and check-frontmatter reach consumers with that release, which needs `just release minor` because `toolkit/migrations/v0.15.0.md` exists and the recipe defaults to patch.
- After the release: a note in plugin-craft's inbox (standard-setup change) and in shell-gotchas' inbox (drop `scripts/check-frontmatter.py` for the shipped recipe, whose name rules now match).
- gitlore `skills/resolve` and handoff `skills/handoff` and `skills/precompact` must quote their description when they wire the check, since non-YAML stays refused.
