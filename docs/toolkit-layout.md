# Toolkit layout

What each file under `toolkit/` is for, one bullet per shipped file. Read it
before adding, moving or editing a shipped file; `tests/doc-sync-test.sh` fails
when a bullet and the tree disagree.

- `toolkit/release.just` — the recipes imported into consumer plugins'
  justfiles: `release`, `resume-release`, `check-version`, `check-refs`,
  `check-size`, `check-frontmatter`, `check-modes`, `update-plugin-dev`,
  `dogfood`. Thin wrappers over the scripts beside it; not run from this repo
  directly.
- `toolkit/release.sh` — the release flow itself. Validates state, bumps
  `.claude-plugin/plugin.json`, commits, tags, pushes, creates the GitHub
  release, and bumps the marketplace entry. `--resume` probes what already
  landed and does only what is missing. Holds the argument parsing and the step
  sequence; the steps live in five sibling files it sources from its own
  directory, sharing its shell, `set` line and globals:
  - `toolkit/release-preflight.sh` — the checks every run makes before any side
    effect: clean tree and its exemptions, push route, `MARKETPLACE_DIR`.
  - `toolkit/release-tags.sh` — release-history reads, and the release preflight
    that decides what version this run publishes.
  - `toolkit/release-resume.sh` — the resume preflight: what a `--resume` run
    probes and decides before finishing a partial release.
  - `toolkit/release-publish.sh` — the dist opt-in and pre-flight, the version
    commit and tag, each push, and the GitHub release.
  - `toolkit/release-marketplace.sh` — bumping or creating the plugin's
    marketplace entry, then committing and pushing it.
- `toolkit/check-version.sh` — `plugin.json` against its `marketplace.json`
  entry. Runs as `release`'s pre-flight, so a release refuses to start atop an
  unfinished prior one.
- `toolkit/update.sh` — pulls a newer toolkit version into a consumer. Resolves
  the newest `dist-` tag when given no ref, refuses any ref outside the dist
  lineage, and prints the migration notes for every version the pull crossed.
- `toolkit/dist.sh` — the dist branch's one script. Reads the `dist.include`
  allowlist at a consumer's root and builds, checks, validates and commits the
  tree holding only the listed paths; `release.sh` publishes it as the `dist`
  branch and `dogfood.sh sync` copies the same set. Not opted in, it does
  nothing. Its build runs `check-refs.sh --tree` on the tree it built.
- `toolkit/check-refs.sh` — refuses broken Markdown references: a link, image or
  reference definition whose relative target is missing (outside the exempt
  prefixes, `docs/changelog/` unless a root `refs.exempt` names others; root
  `plans/` is never read), and, given a `dist.include` or `--shipped`, one from
  a shipped file to an unshipped one. Reads every Markdown file on disk git does
  not ignore, skipping `plugin-dev/`, root `plans/` and submodules. This repo's
  `precommit` runs it with `--shipped toolkit`; consumers wire
  `precommit: check-refs`. Executable on disk, which `tests/dist-tree-test.sh`
  pins. Its two awk programs, the Markdown reader and the existence test over
  the git listing, live in `toolkit/check-refs-parse.sh`, which it sources from
  its own directory.
- `toolkit/check-size.sh` — refuses a file over the size cap: 20000 bytes as
  `wc -c` counts them, 10000 for a `SKILL.md` at any depth. Reads every file on
  disk git does not ignore, skipping `plugin-dev/`, root `plans/`, lock files,
  files marked `linguist-generated`, binaries, symlinks and submodules, plus
  whatever a root `size.exempt` lists, one entry and its reason per line.
  Uncached; consumers wire `precommit: check-refs check-size`. Executable on
  disk, which `tests/dist-tree-test.sh` pins.
- `toolkit/check-frontmatter.sh` — refuses a skill, agent or command whose
  frontmatter is missing, not YAML, or breaks the toolkit's field rules. Reads
  `skills/*/SKILL.md` and `agents/` and `commands/` `.md` files git does not
  ignore, from disk. Python is embedded and run as `python3 -I`, under
  `.venv/bin/python3` of the git top level, else the `python3` on PATH; PyYAML
  must import in one of them, else it names the remedy. Uncached; consumers wire
  `precommit: check-refs check-size check-frontmatter`. Executable on disk,
  which `tests/dist-tree-test.sh` pins. This repo has no skills, so its
  `precommit` does not run it.
- `toolkit/check-modes.sh` — refuses a script that starts with `#!` and lacks
  the execute bit. Checks the directory it lives in, the vendored copy in a
  consumer and `toolkit/` here, from anywhere in the work tree and with no
  arguments. Reads the files git does not ignore from disk and tests each with
  `[ -x ]`, so a file flipped to 644 by a consumer commit after vendoring is
  caught. Uncached; consumers wire
  `precommit: check-refs check-size check-frontmatter check-modes`. Executable
  on disk, which `tests/dist-tree-test.sh` pins by the same rule over every
  shipped file.
- `toolkit/exempt-list.sh` — sourced by `check-size.sh` and `check-refs.sh` from
  their own directory, executable like every shipped file that starts with `#!`:
  the one reader of `size.exempt` and `refs.exempt`, and the scope rule both
  apply (`plugin-dev/` and root `plans/` as whole leading components).
  `dist.sh`'s `dist.include` reader stays its own.
- `toolkit/dogfood.sh` — the dogfood launcher's one script, with three
  subcommands. `sync` mirrors the plugin tree, minus git-ignored paths and every
  `.git`, into `dist/plugin/`, the copy the session loads; `pre-tool` is the
  `PreToolUse(Write|Edit|NotebookEdit)` hook that refuses agent edits into that
  copy and names the source path; `session-start` is the `SessionStart` hook
  that warns when the session does not load the copy, no directory is there to
  load, or `jq` is missing. Each finds the repo root from the script's own
  location, never from `CLAUDE_PROJECT_DIR` or a hook payload's `cwd`.
- `toolkit/bin/claude` — the dogfood shim, a `claude` that the consumer's
  `.envrc` puts first on PATH as `PATH_add plugin-dev/bin`. Never syncs: it
  execs the next `claude` on PATH with its arguments unchanged and
  `CLAUDE_CODE_PLUGIN_DIRS` set to `dist/plugin/`, the copy only `just dogfood`
  writes, and the copy's `bin/` appended to PATH after the user's entries, both
  whether or not that copy exists yet. It never warns about a missing copy:
  `session-start` does.
- `toolkit/version-guard.sh` — `PreToolUse(Write|Edit)` hook that fires inside
  consumer plugins to refuse agent edits to `.claude-plugin/plugin.json`'s
  `.version`.
- `toolkit/install.sh` — one-shot: vendors this toolkit into a consumer plugin
  via `git subtree add`, wires the `release.just` import into the consumer's
  `justfile`, and adds the version-guard hook and, beside it, the two dogfood
  hooks (`dogfood.sh pre-tool` and `session-start`) to its
  `.claude/settings.json`.
- `toolkit/gates.just` — opt-in, never imported by `release.just`: a private
  `plugin_dev_gate_prolog` variable a consumer interpolates as the shebang of a
  gate recipe. It defines `sentinel-guard`, `check-sentinel`, `record-sentinel`
  and `gate-inputs-hash`, which skip a gate while the hash of its declared
  inputs is unchanged. Its tool-version list is the consumer's exported
  `PLUGIN_DEV_GATE_TOOLS`; it defines no other variable, so it imports beside
  `release.just` without a name clash.
- `toolkit/run-bats.sh` — the quiet bats runner, opt-in and independent of the
  sentinels: failures and a pass, fail and skip count in place of the TAP
  stream. Executable on disk, which `tests/dist-tree-test.sh` pins.
- `toolkit/README.md` — the consumer-facing manual, shipped in the dist tree.
  The place a plugin maintainer reads; keep it in step with the scripts above.
  Its chapters live in the `manual` directory, which holds user documentation
  and ships; `docs/` holds design and never does, and the README reaches it by
  one absolute URL at most.
- `toolkit/manual/dist-branch.md` — the manual's dist-branch chapter: how a
  plugin opts in with `dist.include`, and what each check refuses or warns
  about. Split out of `toolkit/README.md`, which keeps a stub section pointing
  here, so the manual stays under the size cap.
- `toolkit/manual/dogfood.md` — the manual's dogfooding chapter: setup of the
  shim and the copy, launching, promoting changes, and the two dogfood hooks.
  `toolkit/README.md` keeps a stub section pointing here.
- `toolkit/manual/gates.md` — the manual's gate-sentinel chapter: the prolog,
  how to choose the input pathspecs so a cached pass stays true, the
  tool-version list and the quiet runner. `toolkit/README.md` keeps a stub
  section pointing here.
- `toolkit/manual/size-check.md` — the manual's size-check chapter: the byte
  metric and the two caps, wiring `check-size` uncached, the scope skips in
  order, the `size.exempt` format and refusals, and the report.
  `toolkit/README.md` keeps a stub section pointing here.
- `toolkit/manual/frontmatter-check.md` — the manual's frontmatter-check
  chapter: what is read, each refusal, what is not refused, the wiring and the
  PyYAML setup. `toolkit/README.md` keeps a stub section pointing here.
- `toolkit/migrations/vX.Y.Z.md` — optional per-release note for a step a
  consumer must take by hand. Printed by `update.sh` for the crossed range;
  `tests/dist-tree-test.sh` allows this path and no other under `migrations/`.
- `toolkit/VERSION` — last-released toolkit version, plain text. Bumped by the
  self-release recipe; mirrors the latest git tag. Exists so consumers (which
  vendor via subtree, where tags don't propagate) can identify the version
  they're on with `cat plugin-dev/VERSION`.
