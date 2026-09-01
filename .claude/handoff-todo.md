## Open decisions

- Which index pointers to retire for the ~24.4KB loader cap. The remedy is fixed — retire a pointer, never shorten one into an unroutable line — but the selection is unmade.

## Remaining

- Fix `version-guard.sh`, deliberately deferred from the 2026-09-01 shell audit. Four findings, all in `plans/2026-09-01-shell-audit-toolkit.md` (items 2-5): the hook JSON goes to stderr with `exit 2`, so Claude Code never parses it and `systemMessage` never reaches the human; `realpath -m` is GNU-only, so the "is this the manifest?" guard inverts on macOS; the manifest is located from the payload `cwd`, which drifts; and an `Edit` of the bare version value (`"1.2.3"` -> `"9.9.9"`) passes the guard entirely. `tests/hook-test.sh` captures with `2>&1`, so its assertions cannot tell the fixed script from the broken one — the channel fix needs the test rewritten in the same pass.
- Cut a release once version-guard lands, so consumers get both halves of the audit. v0.7.0 already ships the rest.
- Take the ddaanet tier's upstream facts: its remote is ahead of the local store, so every parent commit here declines to publish memory until `/gitlore:merge` runs.
