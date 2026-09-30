# Item 3.2 — v0.9.0 migration note

## Written

`toolkit/migrations/v0.9.0.md`: a two-sentence intro, then four numbered steps,
one per D12 bullet, each with a verbatim-runnable command block for the
consumer's root, and a one-clause reason. The intro says every step is a no-op
where it already holds, and each command is idempotent on its own:
`git rm --ignore-unmatch` and a `git check-ignore -q ... ||` guard.

Named `v0.9.0.md` for a minor bump from `toolkit/VERSION` 0.8.0. If the release
picks another bump, rename it: `update.sh` prints notes in (old, new] only.

## D12 bullet to step

1. Re-run `bash plugin-dev/install.sh` maps to **step 1**. The reason given is
   that `update-plugin-dev` does not re-run it, and the step adds the dogfood
   hooks. The step also says to run it from the maintainer's own shell, since
   the sandbox refuses writes to `.claude/settings.json`.
2. Delete `.bin/claude`, `PATH_add .bin` and recipe lines naming it maps to
   **step 2**: `git rm --ignore-unmatch .bin/claude`, then a `grep` that finds
   the `.envrc` and `justfile` lines to delete. The reason given is that a
   `precommit` shellchecking the file fails once it is gone.
3. `PATH_add plugin-dev/bin` after `PATH_add .gitlore/bin`, then `direnv allow`,
   maps to **step 3**. It says "the last `PATH_add`", since consumers such as
   cwd-safety and handoff add `.venv/bin` after `.gitlore/bin`.
4. Ignore `/dist/plugin/` and make `clean` spare it maps to **step 4**. The
   ignore is conditional,
   `git check-ignore -q dist/plugin/ || printf '\n/dist/plugin/\n' >> .gitignore`,
   so a consumer already ignoring `/dist/` is left alone. The trailing slash
   matches `dogfood.sh`'s own check: the bare name misses a `/dist/plugin/`
   pattern before the copy exists. The leading `\n` guards against a
   `.gitignore` with no final newline. The `clean` half applies only where the
   recipe deletes `dist/`.

## Checks

- The step-4 command, run twice in a scratch repo whose `.gitignore` has no
  final newline, appended the pattern once, on its own line.
- `git rm --ignore-unmatch .bin/claude` with no such file exited 0.
- The note is hand-wrapped to 80 columns, since `just format-docs` covers only
  `docs/` and `plans/`, and `rumdl check` passes on it.
- `tests/dist-tree-test.sh` already admits any `migrations/vX.Y.Z.md`, and
  `tests/doc-sync-test.sh` folds migration notes into the generic Layout entry,
  so neither needed a change.
