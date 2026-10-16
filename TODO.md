## Remaining

- Cut toolkit 0.11.0 (release-bare fix, splits, line-cap gate, .claude/ exemption removal, opt-in gate sentinels) when my human partner runs `just release minor`; a patch bump would skip printing toolkit/migrations/v0.11.0.md.
- Gate sentinels (toolkit/gates.just, toolkit/run-bats.sh) landed on dev without review: act on its /code-review findings before cutting 0.11.0.
- After 0.11.0 ships: delete memory/ddaanet/release-bare-not-bypass-flag.md and its index lines in memory/MEMORY.md and memory/ddaanet/MEMORY.md, and delete inbox/brief-release-bare-not-bypass-flag.md.
- Migrate consumers to the new toolkit, per repo with consent: gitmoji, cwd-safety, onekeys (0.6.x), shell-gotchas (0.7.1), candidature (0.7.2), gitlore (0.9.3), ghmem (0.9.3); install.sh from my human partner's shell where dogfood hooks are not yet wired. ghmem first reverts its "local hack, dogfood shim appends dist/plugin/bin to PATH" commit, which edits the lines the shim change rewrites; on a conflict anyway, take upstream's plugin-dev/bin/claude.
- After the dogfood-shim merge, my human partner runs a live dogfood session: `command -v` on a plugin bin/ command resolves in main-thread and subagent Bash.
- release-marketplace.sh rewrites marketplace.json whole in jq's 2-space style on every real bump; a compact-style file gets a whole-file diff per release. Edit the version in place instead.
- scripts/self-release.sh common_preflight refuses a dirty tree with a bare "uncommitted changes" naming no path, while toolkit/release-preflight.sh report_dirty names them; make the self-release name the offending paths.
