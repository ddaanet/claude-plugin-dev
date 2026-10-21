## Remaining

- My human partner runs a live dogfood session: `command -v` on a plugin bin/ command resolves in main-thread and subagent Bash; launched before the first `just dogfood`, session-start warns and `/reload-plugins` after the sync loads the copy without a restart (verified headless only).
- release-marketplace.sh rewrites marketplace.json whole in jq's 2-space style on every real bump; edit the version in place instead.
- scripts/self-release.sh common_preflight refuses a dirty tree with a bare "uncommitted changes" naming no path, while toolkit/release-preflight.sh report_dirty names them; make the self-release name the offending paths.
- `just format-docs` runs rumdl over docs/ and plans/ only, so the shipped manual (toolkit/README.md, toolkit/manual/, toolkit/migrations/) is never reflowed and its 400-line count is measured on hand wrapping; widen the recipe's scope.
- tests/docs-test.sh resolves docs/ and plans/ pointers with its own grep, which reads links inside inline code spans; check-refs.sh now covers the same ground over every Markdown file, so drop that half of docs-test or point it at check-refs.
- gitlore's dist.include ships all of `scripts/`, which holds its own gate tooling beside the runtime scripts; decide per-file entries or moving the tooling (found in the 0.12 patch-rework triage, tmp/patch-rework/triage.md).
- memory/MEMORY.md is over its byte budget (105%), so its tail is truncated at load: run /gitlore:index-audit when my human partner asks for it.
