## Open decisions

- Release 0.9.2 straight away, or only after the deliverable review of `e8885c3..HEAD`. Default: review first; the last two reviews each found real majors.

## Remaining

- Relay the 0.9.2 review findings, fix what my human partner accepts, then `just release patch`. It runs past the Bash 10-minute cap; wait for the notification, and use dangerouslyDisableSandbox.
- Dogfood 0.9.2 in handoff the same day: `just update-plugin-dev dist-v0.9.2` there. The auto-mode classifier refuses `install.sh` and some commits, so hand my human partner verbatim commands for those; handoff's gate needs its own `.venv` first on PATH.
- `docs/references/dogfood.md` is at exactly 400 lines: its next addition needs a split.
- Unprobed, recorded in the dogfood node: hooks firing twice in the gitlore evals under the shim, an empty plugin-root `.mcp.json`, `/reload-plugins` scope for commands/`.mcp.json`/output styles, jq 1.6's parse-error status.
