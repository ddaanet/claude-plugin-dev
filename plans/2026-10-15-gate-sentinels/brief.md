## Brief: ship gitlore's gate sentinels and quiet bats runner in the toolkit

2026-10-15. Written from a `handoff` session (`/Users/david/code/handoff`) after
a release whose `precommit` printed several hundred lines of bats TAP and re-ran
the whole gate on a tree it had just passed. My human partner asked for both of
gitlore's answers to that, and judged they belong in the toolkit rather than
copied per plugin. Everything below is input to decide on, not a decision taken
for this repo: put the open choices to my human partner.

### What exists, in gitlore

- **Quiet bats.** `/Users/david/code/gitlore/scripts/run-bats.sh` (35 lines):
  runs `bats "$@"` into a `mktemp` log, prints only the `not ok` blocks (or the
  whole log when no TAP line appeared), then one line
  `bats: N passed, M failed — full log: <path>`, and exits with bats' status.
  Portable as it is; only the `gitlore-bats.` log prefix names gitlore.
- **Gate sentinels.** In `/Users/david/code/gitlore/justfile`, the `bash_prolog`
  variable (about lines 183-300) defines `check-sentinel`, `sentinel-guard`,
  `record-sentinel`, `gate-inputs-hash` and `run-suites`. A shebang recipe opens
  with `sentinel-guard <gate> <pathspecs…>`, which hashes the inputs and exits 0
  with `<gate>: cached (inputs unchanged)` when the hash matches the recorded
  one; it ends with `record-sentinel`, which records the pre-run hash only if
  the inputs did not move during the run. The sentinel lives under the gitdir
  (`git rev-parse --git-path gitlore/gates`). The comments there carry the
  reasoning for each guard; read them before changing any of it.
- **Per-suite bats cache.** `scripts/run-bats-cached.sh` (201 lines) plus
  `parse-bats-junit.py`, reached through `run-suites`: one key per suite under
  the whole-tree sentinel. Bats-specific and larger.

### Verified here

- A justfile's `import`ed file exposes its variables to the importer's shebang
  recipes: an imported `p := "/usr/bin/env bash\n…f () {…}"` used as `#!{{ p }}`
  in the importing justfile ran `f` (just on this box, 2026-10-15). So a toolkit
  `.just` file can carry the prolog the way `release.just` already carries the
  release recipe.

### Points the port has to settle

1. **Names.** `GITLORE_GATE_DIR`, `GITLORE_GATE_FORCE`, `GITLORE_TEST_JOBS` and
   the `gitlore/gates` gitdir path need a toolkit-neutral spelling. A rename,
   not an alias: gitlore patches its justfile when it takes the dist tag that
   ships it.
2. **Tool versions in the hash.** `gate-inputs-hash` folds in `bats --version`
   because gitlore does not pin its tools. `handoff` pins its Python tools
   through `uv.lock` (an input file) but not `bats`, `shellcheck` or `claude`.
   The set of version commands hashed has to be a per-consumer parameter.
3. **Inputs are an allow-list the consumer declares**, and every check a gate
   runs must read only inside it (the `gate-cache-must-cover-every-check` memory
   in the `ddaanet` tier has the full rule, including that a gitlink input such
   as `memory/` cannot be hashed, so a check reading it runs uncached ahead of
   the guard). gitlore's `justfile_gates` suite guards the allow-list against
   drift; whether the toolkit ships an equivalent check is open.
4. **One guard per shebang body**: `check-sentinel` sets shell variables
   `record-sentinel` reads back.
5. **Contract and migration.** It touches the `precommit`/`prerelease` contract
   the manual owns. Opt-in for a consumer (nothing breaks for one that does not
   import it) seems right; it still wants a migration note under
   `toolkit/migrations/` and a changelog pointer line.

### Proposed scope

Defaults agreed in the `handoff` session, still yours to revisit: the quiet
runner and the sentinel functions first; `run-bats-cached.sh` as a later opt-in.
No interim copy in `handoff`: it adopts the gates through
`just update-plugin-dev dist-vX.Y.Z` once released.

For orientation, `handoff`'s current gate is `just precommit` in
`/Users/david/code/handoff/justfile`: jq, `claude plugin validate`,
`claude plugin test`, shellcheck, ruff, docformatter, mypy, ty, three bats files
and pytest, all serial, all uncached. Its likely input set:
`.claude-plugin .claude/settings.json bin hooks scripts skills tests justfile pyproject.toml uv.lock plugin-dev`
(`claude plugin validate`/`test` read `skills/` and `hooks/`).
