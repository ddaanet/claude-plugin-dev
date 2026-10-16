## Remaining

- Cut toolkit 0.10.1 (release-bare fix, splits, line-cap gate, .claude/ exemption removal) when my human partner runs `just release`.
- After 0.10.1 ships: delete memory/ddaanet/release-bare-not-bypass-flag.md and its index lines in memory/MEMORY.md and memory/ddaanet/MEMORY.md, and delete inbox/brief-release-bare-not-bypass-flag.md.
- Migrate consumers to the new toolkit, per repo with consent: gitmoji, cwd-safety, onekeys (0.6.x), shell-gotchas (0.7.1), candidature (0.7.2), gitlore (0.9.3); install.sh from my human partner's shell where dogfood hooks are not yet wired.
- scripts/self-release.sh common_preflight refuses a dirty tree with a bare "uncommitted changes" naming no path, while toolkit/release-preflight.sh report_dirty names them; make the self-release name the offending paths.
