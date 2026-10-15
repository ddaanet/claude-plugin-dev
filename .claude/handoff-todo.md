## Remaining

- Dist-branch plan slices 0–4, then `just release minor` (0.10.0) and dogfood on handoff: `just update-plugin-dev dist-v0.10.0`, add `dist.include`, `just dogfood`, a handoff release creating `dist`.
- Migrate each other plugin that vendors the toolkit to 0.9.3: `just update-plugin-dev dist-v0.9.3`, then `bash plugin-dev/install.sh` from the human's own shell, then commit `.claude/settings.json`. Handoff is done; its gate needs its own `.venv` first on PATH.
- Before gitlore adopts the dogfood shim: its evals copy `hooks/hooks.json` into the eval repo's settings and run `claude` from PATH, so under the shim with a `dist/plugin` present each hook fires twice (probed on CC 2.1.294). Decide how the evals avoid the plugin's copy loading as well.