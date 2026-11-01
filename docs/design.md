# claude-plugin-dev — Design

Living design document. Updated when meaningful design decisions land or get
overturned. Not a changelog of features — a record of
*why this project has the shape it has*.

This file is the hub. It carries the motivation, the requirements, and one line
for every design decision and every limitation. The argument behind each line
lives in a node under `references/`, linked from the heading above it. Read the
hub first and open only the node whose decisions you are about to touch — a
whole-document read is neither needed nor intended.

## Motivation

Several Claude Code plugins under the same author (currently `handoff` and
`gitmoji`; eventually more) need the same release infrastructure: a
`just release` recipe that bumps `.claude-plugin/plugin.json`, commits, tags,
pushes, and creates a GitHub release. Each plugin had diverged on small details
(commit message format, interactive vs. non-interactive confirmation, branch
detection), and a real bug landed when an agent edited `plugin.json` directly
during development — caught only when the release recipe failed days later.

Two problems stacked:

1. **Drift.** Three near-identical recipes maintained independently. A fix in
   one didn't propagate.
2. **Missing guardrails.** The release recipe is the canonical version bumper,
   but nothing stopped an agent from manually editing `plugin.json`. The
   fact-of-the-mismatch was only discoverable at release time.

Both problems want the same answer: a single source of truth for release infra,
vendored into each consumer plugin and enforced via a `PreToolUse` hook on
`plugin.json`.

Developing a plugin raises a third problem, in the session doing the work.
Claude Code treats every path under a loaded plugin root as a sensitive file, so
a session that loads the plugin from its own working tree prompts on every agent
edit to it. It also runs whatever is on disk, so a half-edited hook script runs
in the session editing it. Consumers worked around this with hand-copied
launcher shims, which drifted the way the release recipes had.

The toolkit captures: the unified release recipe, the version-guard hook, a
one-shot install script, and a dogfood launcher that loads the plugin under
development from a synced copy. Vendored via `git subtree` so the content is
versioned with each consumer.

## Requirements

- Provide a `release` recipe that handles bump → commit → tag → push → GitHub
  release for any plugin whose manifest is at `.claude-plugin/plugin.json`.
- Provide a `PreToolUse(Write|Edit)` hook that refuses agent edits to
  `.claude-plugin/plugin.json`'s `.version`.
- Provide a one-shot installer that vendors the toolkit and wires it into the
  consumer's `justfile` and `.claude/settings.json`.
- Provide a dogfood launcher: a `claude` shim that loads the consumer plugin
  from a copy at `dist/plugin/`, so agent edits to the source meet no
  sensitive-file prompt and a half-edited hook script never runs in the session
  editing it. The copy changes only when promoted by `just dogfood`, and project
  hooks refuse agent edits to it and report a session that does not load it.
- Provide an opt-in `dist` branch holding only the paths a plugin lists, so a
  plugin whose repo root holds a gitlink can still be submitted to the plugin
  directory, and a dogfood copy of the same set.
- Provide opt-in gate sentinels and a quiet bats runner, so a plugin's
  `precommit` can skip itself over an unchanged tree and print a bats run as
  failures and a count, without a plugin that wants neither seeing a change.
- Provide a reference check a plugin's `precommit` runs: it refuses a Markdown
  link whose target is missing, or one leading from a shipped file out of the
  `dist.include` set, and the dist build refuses the second again.
- **Reproducibility:** old consumer-plugin tags must build identically to when
  they were tagged — the toolkit content vendored at the time must be
  retrievable, not subject to drift.
- **Portability:** fresh clones of a consumer plugin must work without any
  contributor-side dotfiles, system config, or central installation. CI must be
  able to run the recipe with no setup. Temporary files name their directory,
  because macOS `mktemp` without a template ignores `TMPDIR`.
- **Fail-fast:** misconfigured invocations (missing manifest, dirty tree,
  version desync) abort with actionable errors before any destructive or slow
  operation.
- **Idempotent install:** re-running `install.sh` with everything already wired
  is a no-op.
- **Self-hosting quality:** the toolkit's own scripts pass the same kind of
  checks (`bash -n`, `shellcheck`) it implicitly recommends for consumers.

## Design decisions

Each bullet states a conclusion. Its argument — the alternatives weighed, the
bug that motivated it, what it costs — is in the node named by the heading. A
decision that gets overturned is rewritten in both places, in the present tense;
the dated record of the reversal goes in the changelog.

### Distribution and versioning — [references/distribution.md](references/distribution.md)

- Vendored into each consumer with `git subtree`, at `plugin-dev/`.
- Consumers vendor the `dist-vX.Y.Z` split ref, never the source tag.
- A tag always, never `HEAD`.
- A separate repository from the plugins that consume it.
- **One `install.sh` bootstraps and wires in a single invocation** — subtree
  add, justfile import, and the version-guard and two dogfood hooks into
  `.claude/settings.json`.
- The first install is `curl … | bash` at a dist tag.
- `install.sh` takes its target from `$PWD`, not an argument.
- The update flow lives in `update.sh`, not in the recipe body.
- Migration notes ship in the dist tree and are printed, never applied.
- `toolkit/VERSION` is the version source of truth, not the tags alone.

### The release flow — [references/release-flow.md](references/release-flow.md)

- The manifest holds the *last released* version, and `just release` bumps from
  there.
- A first release publishes the manifest version as-is, detected by tag alone.
- The marketplace entry is bumped if present and created if absent.
- No interactive confirmation.
- The consumer's commit gate is named `precommit`.
- `release` depends on `prerelease`, never on `precommit` directly.
- The default branch is read from `origin/HEAD`.

### Recovery and the pre-flight state checks — [references/recovery.md](references/recovery.md), [references/clean-tree.md](references/clean-tree.md)

- `check-version.sh` detects a half-landed release.
- An empty local tag list is checked against origin first.
- **A push redirected away from origin is refused** when the config key is set
  at all rather than when it "diverges"; `pushInsteadOf` is a stated bound, not
  refused.
- **`resume-release` completes one** — the last steps, `push_dist` included for
  an opted-in plugin, are an idempotent block that probes remote state before
  acting.
- A refusal carries the diagnosis and the next command.
- A commit a consumer's gate refuses is rolled back.
- The clean-tree check exempts only the gitlore memory gitlink.

### The dist branch — [references/dist-branch.md](references/dist-branch.md)

- A plugin opts in with a `dist.include` allowlist at its root.
- An allowlist, not a denylist; paths are literal.
- The tree is built with plumbing from the release commit.
- Validation runs in the pre-flight, before the bump commit.
- The dist commit is reproducible, the branch is pushed without force, and
  `dist-vX.Y.Z` is a lightweight tag that is never moved.
- A missing `dist.sh` beside a plugin with `dist.include` is a refusal.
- User documentation ships in `manual/`; design stays in `docs/` and never
  ships.

### Gate sentinels — [references/gates.md](references/gates.md)

- Opt-in, in `gates.just` and `run-bats.sh`.
- The functions travel as an interpolated prolog.
- The consumer declares the inputs, and the cache is true only while every check
  reads inside them.
- Tool versions are an exported `PLUGIN_DEV_GATE_TOOLS`, empty by default.
- A pass is recorded only against the hash taken before the checks, and never
  from a hash that failed.
- One guard per recipe body, enforced.
- Names are toolkit-neutral, with no aliases.
- The quiet runner shows the log whenever bats failed with nothing else to show,
  and keeps it only then.
- gitlore's per-suite bats cache stays out.

### The reference check — [references/check-refs.md](references/check-refs.md)

- `check-refs.sh` runs from the consumer's `precommit`, not only at release.
- A reference is a Markdown link, image or reference definition, never a
  backticked path.
- Files are read from disk: every Markdown file git does not ignore, tracked or
  not.
- Dated records are exempt from resolving, and `plans/` is never read, as
  `check-size` skips it.
- **Shipped stays shipped, with no exemption**: given a `dist.include`, a link
  from a shipped file must reach a shipped file git lists.
- `release.just` gains a `check-refs` recipe that nothing depends on.

### The size check — [references/size-check.md](references/size-check.md)

- A file's size is its bytes, as `wc -c` counts them, not its lines.
- Two fixed caps: 20000 for every counted file, 10000 for any `SKILL.md`.
- `docs/changelog/` is counted.
- `check-size.sh` is a shipped script run uncached, wired by hand.
- A root `size.exempt` lists overages, each with a reason, and refuses stale
  entries.

### The frontmatter check — [references/frontmatter-check.md](references/frontmatter-check.md)

- `claude plugin validate` passes frontmatter that is not YAML, so a shipped
  check refuses it.
- `description` is required and `name` is not: the validator warns on the first
  and is silent on the second.
- PyYAML parses the block, not awk, and the Python is embedded and run as
  `python3 -I`.
- `check-frontmatter.sh` is a shipped script run uncached, wired by hand, and
  needs a venv the consumer adds.
- Runtime loading was not probed.

### This repo's own release — [references/self-release.md](references/self-release.md)

- The toolkit releases itself with a separate script.
- **It borrows the shape, not the code**: the same idempotent tail.
- A bump is refused while the current `toolkit/VERSION` is tagged but not fully
  published.
- `resume-release` re-cuts `dist-vX.Y.Z` from the `vX.Y.Z` tag, never `HEAD`.
- The clean-tree exclusion is a literal pathspec here.

### The version-guard hook — [references/version-guard.md](references/version-guard.md)

- **The deny is dual-channel, on stdout with exit 0.** The manifest is located
  from `CLAUDE_PROJECT_DIR`, never the drifting payload `cwd`, and an Edit is
  applied and re-read rather than pattern-matched.
- The deny message branches on whether the plugin has ever released.

### The dogfood launcher — [references/dogfood.md](references/dogfood.md), [references/dogfood-sync.md](references/dogfood-sync.md)

- The session loads a real copy at `dist/plugin/`, not a symlink.
- The copy is the whole repo tree minus what git ignores, every `.git` and
  itself, or only the `dist.include` paths when the plugin has one.
- The plugin root is the repo root.
- The copy syncs only on `just dogfood`.
- A launch with no copy exports the copy's path anyway.
- `dogfood.sh` carries `sync`, `pre-tool` and `session-start`, each rooted at
  the script's own location, never `CLAUDE_PROJECT_DIR` or a payload `cwd`.
- The copy guard denies an edit into `dist/plugin/`, compared on physical paths,
  and does not rewrite it.
- `session-start` reports a session that does not load the copy, a missing copy
  directory, and a missing `jq`.
- A failed sync is loud, and every refusal comes before the copy is made.
- The shim exports `CLAUDE_CODE_PLUGIN_DIRS` rather than passing `--plugin-dir`,
  and execs the next `claude` on PATH. The shim never syncs.
- The shim appends `<root>/dist/plugin/bin` to PATH unconditionally, after the
  user's entries, with no probe for the copy, the directory or a prior entry.
- `just dogfood` syncs and does nothing else: it starts no `claude` and depends
  on no gate.
- `install.sh` wires the hooks; `.envrc`, `.gitignore` and `clean` are
  documented, not edited, and the sync refuses until git ignores the copy.
- Existing consumers migrate by a printed note; breaking the hand-copied shims
  is accepted.

## Limitations — [references/limitations.md](references/limitations.md)

What the toolkit does not do, or does only at a known cost. Each is argued in
the node.

- **Hybrid Python+plugin repos (e.g. edify) are out of scope.**
- **`release` is not atomic, but it is recoverable.**
- **No automated propagation.**
- **Subtree pull requires the toolkit URL be reachable.**
- **The version-guard hook fires only in consumers that ran `install.sh`.**
- **Toolkit updates may require a consumer justfile edit.**
- **The shipped scripts carry a high comment volume, accepted rather than
  unnoticed.**
- **A dogfood session launched from a subdirectory runs without its project
  hooks.**
- **The dogfood sync is unprobed against macOS rsync.**
- **Solo-author workflow assumed.**
- **A gate's input list is partly unchecked.**
- **The reference check reads Markdown links and nothing else.**
- **No standardised hook library yet.**

## History

Write-time records of each change — what moved and the reasoning available at
the time — live in [changelog.md](changelog.md), one file per entry. This
document states what the toolkit *is*; the changelog states how it got there.
