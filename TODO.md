## Remaining

- After 0.11.0 ships: delete memory/ddaanet/release-bare-not-bypass-flag.md and its index lines in memory/MEMORY.md and memory/ddaanet/MEMORY.md, and delete inbox/brief-release-bare-not-bypass-flag.md.
- After 0.11.0 ships, my human partner runs a live dogfood session: `command -v` on a plugin bin/ command resolves in main-thread and subagent Bash; launched before the first `just dogfood`, session-start warns and `/reload-plugins` after the sync loads the copy without a restart (verified headless only).
- Migrate consumers to the new toolkit, per repo with consent: gitmoji, cwd-safety, onekeys (0.6.x), shell-gotchas (0.7.1), candidature (0.7.2), gitlore (0.9.3), ghmem (0.9.3); install.sh from my human partner's shell where dogfood hooks are not yet wired. ghmem first reverts its "local hack, dogfood shim appends dist/plugin/bin to PATH" commit; on a conflict anyway, take upstream's plugin-dev/bin/claude.
- release-marketplace.sh rewrites marketplace.json whole in jq's 2-space style on every real bump; edit the version in place instead.
- scripts/self-release.sh common_preflight refuses a dirty tree with a bare "uncommitted changes" naming no path, while toolkit/release-preflight.sh report_dirty names them; make the self-release name the offending paths.
- `just format-docs` runs rumdl over docs/ and plans/ only, so the shipped manual (toolkit/README.md, toolkit/docs/, toolkit/migrations/) is never reflowed and its 400-line count is measured on hand wrapping; widen the recipe's scope.
- memory/MEMORY.md is over its byte budget (106%), so its tail is truncated at load: run /gitlore:index-audit when my human partner asks for it.
