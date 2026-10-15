## Open decisions

- Whether to harden `push_dist`'s "already landed" detection in `toolkit/release.sh`: it matches origin `dist`'s tip subject `dist v$V from <sha>` only, as the plan specified; the slice 2 reviewer suggested also comparing the tip's tree to the rebuilt tree.
- Whether to split `toolkit/README.md` (421 lines, over the 400 soft cap, not test-enforced) — the dist section is the candidate — and `tests/dist-test.sh` (678 lines).

## Remaining

- Migrate each other plugin that vendors the toolkit to 0.10.0: `just update-plugin-dev dist-v0.10.0`, then `bash plugin-dev/install.sh` from the human's own shell where settings wiring changed, then commit `.claude/settings.json`. Handoff is done. Handoff's gate needs both `PATH` and `VIRTUAL_ENV` pointing at its own `.venv`, or `ruff` is missing and `ty` reads this repo's venv.
- Before gitlore adopts the dogfood shim: its evals copy `hooks/hooks.json` into the eval repo's settings and run `claude` from PATH, so under the shim with a `dist/plugin` present each hook fires twice (probed on CC 2.1.294). Decide how the evals avoid the plugin's copy loading as well.
- Triage `inbox/` (four briefs, one written mid-session by another session) and the untracked `plans/2026-10-08-version-guard-quoting/reports/preflight.md`.
