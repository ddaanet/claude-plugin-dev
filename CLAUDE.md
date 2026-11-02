# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Agent Instructions — claude-plugin-dev

This repository is *not* a Claude Code plugin. It is a development
toolkit that gets vendored into Claude Code plugins via `git subtree`.
The artifacts here run inside *other* repositories — keep that
inversion in mind when editing.

## Layout

**`toolkit/` is the shipped boundary.** Everything under it — and nothing
else — reaches a consumer, because `just release` cuts a
`dist-vX.Y.Z` tag via `git subtree split --prefix=toolkit` and consumers
vendor that. Adding a file to `toolkit/` ships it to every plugin; the
repo root is this repo's own working environment and stays here. Adding
or removing a shipped file means updating the list in
`tests/dist-tree-test.sh`, which fails otherwise.

Before adding, moving or editing a shipped file, open
[docs/toolkit-layout.md](docs/toolkit-layout.md): it says what each one is for.

- `justfile` — *this repo's own* dev recipes (distinct from
  `release.just`). Defines `precommit`, behind a sentinel from its own
  `toolkit/gates.just`, and wraps the self-release script
  as `release` and `resume-release`. Root-level, so it is not shipped.
- `scripts/self-release.sh` — this repo's own release flow, the
  counterpart of `toolkit/release.sh` and deliberately not shared with
  it: that one releases a plugin, this one releases the toolkit
  (`toolkit/VERSION`, no marketplace, two tags). Same shape, though —
  every step past the local commit is probed before it is taken, so
  `--resume` finishes a run that died mid-flight. Root-level, so it is
  not shipped; covered by `tests/self-release-*-test.sh`.
- `README.md` — presents this repo and carries the consumer install and
  update instructions. Root-level, so it is not shipped: the vendored
  manual is `toolkit/README.md`, and a change to the install or update
  flow has to land in both — `tests/doc-sync-test.sh` enforces that over
  the command blocks the two sections share.
- `docs/design.md` — the design hub: motivation, requirements, and a
  one-line conclusion per decision and per limitation. States what the
  toolkit *is*. Read it first and open only the node you need.
- `docs/references/*.md` — one node per group of decisions (a large group may take more than one)
  (`distribution`, `dist-branch`, `check-refs`, `dogfood`, `dogfood-sync`,
  `gates`, `release-flow`, `recovery`, `clean-tree`, `self-release`, `size-check`, `frontmatter-check`, `version-guard`, and
  `limitations`, which argues the hub's one-line limitations), each holding the argument behind
  the hub's conclusions: alternatives weighed, what it costs. A decision
  that changes is rewritten in both places.
- `plans/` — specs and implementation plans. Prospective content only;
  `docs/` holds what is true now.
- `inbox/` — briefs, notes and findings that arrive from a session in
  *another* repository. They go here, never the repo root, where they read as
  tracked project documents. Triage means acting on a file and deleting it, or
  promoting it into `plans/`. Root-level, so it is not shipped.
- `pyproject.toml`, `.rumdl.toml`, `.envrc` — dev tooling, not a Python
  package and not shipped. `uv sync` materializes `.venv`, direnv puts
  it on PATH, and `just format-docs` runs rumdl over `docs/`, `plans/` and
  the shipped manual: the toolkit README and the
  manual and migrations directories beside it.

## Quality gate

```sh
just precommit
```

Runs `bash -n` and `shellcheck` on the shell scripts, `check-refs.sh
--shipped toolkit` over this repo's own Markdown, `check-size.sh` over every file, a private
`_import-check` that imports `release.just` into a stub consumer to
catch justfile syntax errors (it imports `gates.just` beside it too), and then
**every test under `tests/`**,
found by the `tests/*-test.sh` glob, so a new suite is gated with no list to edit,
each suite described in [tests/CLAUDE.md](tests/CLAUDE.md). A
green `precommit` — including the one a
pre-commit hook runs — is therefore evidence the whole release suite
passed, not just the linters. **One script under test per suite
file**, each carrying its
own copy of the small assertion harness rather than sourcing a shared
one: a suite that can be read and run alone is worth more than the
duplicated six lines. **No suite file passes 20000 bytes**: a suite that
would is split along its scenario groups into sibling files, each with
its own fixture setup, and `check-size.sh` fails the gate otherwise. It also runs `whitespace` and
`format-docs`, which needs rumdl: `uv sync` once, and the recipe finds
`.venv/bin/rumdl` whether or not direnv has exported it. Must be green
before committing.

The recipe is gated by `toolkit/gates.just`: `sentinel-guard` over every
non-ignored file but the `memory` gitlink, then the two formatters, then
`hash-sentinel`, the checks and `record-sentinel`, so a run over an unchanged
tree prints `precommit: cached (inputs unchanged)` and formats nothing.
`PLUGIN_DEV_GATE_FORCE=1 just precommit` runs it anyway. **Every check picks
its files from disk** — `git ls-files -co --exclude-standard`, the set the
sentinel hashes, and execute bits by `[ -x ]` — never from the index: a check
that read the index would see a file the next `git add` stages while the hash,
which reads disk, did not move, and a cached pass would let it commit
unchecked. `whitespace` stages a tracked file it fixes and fixes an untracked
one in place without adding it.

## Releasing the toolkit

```sh
just release [patch|minor|major]
```

Reads `toolkit/VERSION`, bumps, commits `release: X.Y.Z` (the gitmoji
commit-msg hook lands it as `🔖 X.Y.Z`; nothing probes the subject), tags,
cuts the `dist-vX.Y.Z` split tag consumers vendor, pushes main + both
tags, and creates a GitHub release. Refuses to run on a dirty tree or when
`toolkit/VERSION` disagrees with the latest tag (same invariant as the
consumer release recipe protects on `plugin.json`), and refuses to bump
while the *current* `toolkit/VERSION` is tagged but not fully published
— tags on origin, GitHub release — because that state passes every other
guard and a re-run would publish the next version while stranding the
one whose push failed.

```sh
just resume-release
```

Finishes a release that landed partially, from `toolkit/VERSION`'s
current value. Every remaining step is probed before it is taken, so
running it on a complete release says so and does nothing. It depends on
no gate, for the reason `release.just` gives consumers: a prerelease that
already passed must not have to run again to finish the release it
gated.

Tags only; never expect consumers to track `main`. See
docs/references/distribution.md "Versioning" and "Consumers vendor a
split dist ref" for the reasoning.

## Conventions

- **The consumer-defined commit gate is `precommit`**, not `validate`.
  All documentation and example justfiles must use this name. See
  docs/references/release-flow.md "Recipe naming".
- **`release` depends on `prerelease`, never on `precommit` directly.**
  Consumers define both; `prerelease: precommit` is the usual body, and
  a consumer with slow or paid checks widens it. Don't "simplify" the
  indirection away — see docs/references/release-flow.md "Release
  gate". Any change to the binding must keep `_import-check`'s three
  stub shapes passing (plain, widened, and missing-`prerelease`).
- **`gates.just` and `run-bats.sh` stay opt-in.** `release.just` never imports
  the first or calls the second, and `gates.just` defines no name `release.just`
  does (`_import-check` imports both into one stub). A consumer that imports
  neither must see no difference. Every refusal inside the prolog is an explicit
  `exit`: its guard runs as the condition of an `if`, where bash suspends
  errexit, so a bare failing command would be skipped. The sentinel functions'
  variable names (`sentinel_dir`, `sentinel`, `gate_cwd`, `gate_inputs`,
  `guard_hash`) are read by gitlore's `run-suites`, which is not shipped:
  renaming one is a breaking change, and wants a migration note.
- **Hook output is dual-channel.** When `version-guard.sh` denies an
  edit, `permissionDecisionReason` carries the verbose agent-facing
  message (no escape hatches the agent can self-authorise);
  `systemMessage` carries a one-line human notice. Don't conflate
  them. Don't soften the agent message into something an agent could
  read as instruction (e.g. "you can run X to bypass" — actively
  bad).
- **`${CLAUDE_PROJECT_DIR}` in `install.sh`'s hook commands is
  intentionally single-quoted** — in `hook_cmd` (version-guard), in
  `legacy_hook_cmd` and in the dogfood hooks' `pretool_cmd` and
  `session_cmd`. Claude Code expands it at hook-fire time, not bash at
  install time. The `# shellcheck disable=SC2016` above each of the four
  is load-bearing. Inside the single quotes, all three live commands
  double-quote `"${CLAUDE_PROJECT_DIR}"`, so a repo path with a space
  survives the hook shell; a bare one word-splits and the guard fails
  open. `legacy_hook_cmd` is the bare spelling `hook_cmd` used to have.
  `add_hook` counts a hook as already wired when an entry under its event
  carries the same command string, so it takes the legacy spelling as an
  optional fourth argument and rewrites that entry in place — the
  consumer's matcher survives — instead of appending a second
  version-guard beside it. Only the version-guard call passes it.
- **Heredocs in `install.sh` that emit example justfile content are
  unquoted** (so `$import_line` expands). That means backticks inside
  the heredoc body get parsed as command substitution by bash. Avoid
  decorative backticks in those heredocs — they are not rendered as
  markdown anywhere.
- **Recipe doc comments must be a single line.** just uses only the
  *last* comment line above a recipe as its `--list` doc string, so a
  two-line comment lists as a sentence fragment. Applies to `justfile`,
  `release.just`, and the example justfile `install.sh` generates. Put
  longer explanation in a file header or inside the recipe body — but
  never above a shebang recipe's `#!` line, which must come first.
- **The design is present tense; git carries the history.**
  `docs/design.md` and its `docs/references/` nodes state what the toolkit is,
  how it is built and why, with the reason a decision stands (the trade-off
  weighed, the alternative ruled out, the constraint). The doc states the
  decision that stands with its reason, never struck through, in the hub's
  conclusion and in the node's argument alike; a decision inverted or retired is
  deleted and the commit says why, and a rejected alternative that makes sense
  on its own is a decision and stays.
  The narration of a change (the incident, the belief that turned out false,
  the order of events) goes in the commit body, which a design-significant
  change always carries and a point-fix does not need. No dated record is
  written beside the design.
- **A breaking release ships a migration note that says so in its first
  line, from 0.15.0 on.** `toolkit/migrations/vX.Y.Z.md` opens with the heading
  `# Migrating to X.Y.Z (breaking)`; a consumer that pulls the release can
  otherwise break with no step taken. Earlier notes carry no marker, so an
  unmarked note before 0.15.0 says nothing. A release that only adds opt-in pieces
  with no clash possible needs no note. See docs/references/distribution.md
  "Migration notes".

## Non-goals for this repo

- Don't add a `.claude-plugin/plugin.json` here. It is not a Claude
  Code plugin. The `toolkit/VERSION` file is the source of truth.
- Don't run `release.just`'s recipes from this repo. They expect a
  consumer-shaped layout (`.claude-plugin/plugin.json`, a `precommit`
  recipe) and will fail or produce nonsense here. Use the local
  `release` recipe in this repo's `justfile` instead.
- Don't add hybrid Python+plugin support to `release.just`. Repos
  like `edify` are deliberately out of scope; their release shape is
  different enough that wrapping them would obscure the main path.
  See docs/design.md "Limitations".

@memory/ddaanet/shared-claude.md
