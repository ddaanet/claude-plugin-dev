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
  able to run the recipe with no setup.
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

- **Vendored into each consumer with `git subtree`, at `plugin-dev/`** — release
  infra has to be versioned with the repo, so CI, fresh clones and old tags all
  reproduce with no contributor-side dotfiles.
- **Consumers vendor the `dist-vX.Y.Z` split ref, never the source tag** —
  `subtree` copies a ref's root tree, and this repo's root is its own working
  environment; both call sites refuse every other ref by name or by shape.
- **A tag always, never `HEAD`** — given no ref, `install.sh` and
  `update-plugin-dev` resolve the newest `dist-` tag once, at invocation, and
  record exactly what they vendored.
- **A separate repository from the plugins that consume it** — embedding the
  toolkit in one plugin would couple the toolkit's release cadence to that
  plugin's.
- **One `install.sh` bootstraps and wires in a single invocation** — subtree
  add, justfile import, and the version-guard and two dogfood hooks into
  `.claude/settings.json`. It only ever adds to what the consumer owns, and
  re-running it is a no-op. The one thing it rewrites is the version-guard's
  earlier unquoted command, requoted in place under whatever matcher the
  consumer gave it, because a path with a space split the bare one and the guard
  failed open.
- **The first install is `curl … | bash` at a dist tag** — a `dist-` ref's root
  tree is `toolkit/`, so one tag serves the installer and the content it
  vendors, and the resolved tag is passed through so the two are one release.
- **`install.sh` takes its target from `$PWD`, not an argument** — the magic-cwd
  risk is contained by an early guard for `.claude-plugin/plugin.json`.
- **The update flow lives in `update.sh`, not in the recipe body** — a justfile
  recipe body escapes `shellcheck` and `bash -n`, cannot be run by a test, and
  carries just's own quoting seam.
- **Migration notes ship in the dist tree and are printed, never applied** — an
  upgrade never edits a file outside `plugin-dev/`.
- **`toolkit/VERSION` is the version source of truth, not the tags alone** —
  tags do not propagate through a subtree pull, so a consumer needs a file it
  can read.

### The release flow — [references/release-flow.md](references/release-flow.md)

- **The manifest holds the *last released* version** — `just release` bumps from
  there. This is the invariant the version-guard hook protects and the release
  recipe re-checks.
- **A first release publishes the manifest version as-is, detected by tag
  alone** — a plugin is at its first release exactly when no `vX.Y.Z` tag exists
  locally or on origin, the marketplace entry playing no part. There is nothing
  to bump from, so an explicit bump is refused, naming the version that will
  ship instead.
- **The marketplace entry is bumped if present and created if absent** — one
  `just release` publishes a brand-new plugin end to end. A created entry gets
  an https `url` source; an opted-in plugin's entry also gets `ref: dist`, and
  an existing entry's `source` is otherwise never rewritten. The commit and the
  push are separately idempotent, each measured against the remote.
- **No interactive confirmation** — `release` runs behind Claude Code's
  permission layer or a human's own `just`.
- **The consumer's commit gate is named `precommit`** — it names the moment it
  fires.
- **`release` depends on `prerelease`, never on `precommit` directly** — a
  consumer whose release gate is bigger than its commit gate widens it there.
- **The default branch is read from `origin/HEAD`** — with `symbolic-ref`, so
  the `main` fallback fires cleanly when the ref is unset.

### Recovery and the pre-flight state checks — [references/recovery.md](references/recovery.md)

- **`check-version.sh` detects a half-landed release** — `plugin.json` against
  its marketplace entry, exposed as a recipe and run as a `release` pre-flight,
  so a release refuses to start on top of an unfinished one.
- **An empty local tag list is checked against origin first** — a clone can lose
  a tag origin still carries, so `release_preflight` probes origin's tags before
  the drift check and before any side effect. A listing it could not perform
  refuses; only origin's silence may say "never released" and continue. Partial
  tag loss — a clone keeping older release tags but not the newest — never
  reaches the probe and is a stated bound, not an oversight.
- **A push redirected away from origin is refused** — when the config key is set
  at all rather than when it "diverges", before any side effect, in both modes.
  Which keys carry that route, and which further one is a stated bound instead,
  are in the node.
- **`resume-release` completes one** — the last steps, `push_dist` included for
  an opted-in plugin, are an idempotent block that probes remote state before
  acting. It completes a release; it never starts one, and it says so when there
  was nothing to do. Its no-tag refusal picks its next command from one origin
  listing, where a failed listing costs only advice and never a harder refusal.
- **A refusal carries the diagnosis and the next command** — where the tree
  state is non-obvious or a release may already be partly public, the message
  states what was checked, what was exempt, and what to run. It ships with the
  vendored tree, so it reaches consumers no memory store or `docs/` page does.
- **A commit a consumer's gate refuses is rolled back** — the manifest bump and
  the marketplace bump alike are restored from HEAD, so the leftover never
  blocks `release` or `resume-release`.
- **The clean-tree check exempts only the gitlore memory gitlink** — its being
  ahead of HEAD is the resting state. The memory path is read from `.gitmodules`
  by submodule name; everything else still refuses, a tracked file under
  `.claude/` included. A dirty `.claude/settings.json` stops a release. The
  refusal lists exemptions only when one applies.

### The dist branch — [references/dist-branch.md](references/dist-branch.md)

- **A plugin opts in with a `dist.include` allowlist at its root** — the plugin
  directory refuses a plugin folder holding a gitlink, and a branch carrying
  only the shipped paths is the shape left once subfolders and
  `git subtree split` are out. Without the file nothing changes.
- **An allowlist, not a denylist** — a new dev file never ships by being
  committed; a forgotten path is missing from the plugin, and a listed path that
  matches nothing is refused. Paths are literal, and the line rules refuse
  anything that could mean more than one path.
- **The tree is built with plumbing from the release commit** — a temporary
  index, NUL-delimited, no checkout. A gitlink or symlink in the result, no
  manifest, or a missing listed path is refused; size, file-count, README and
  licence signals only warn.
- **Validation runs in the pre-flight, before the bump commit** — a failure
  leaves no commit and no tag, and the dist pre-flight is its own step because
  the first release skips `release_preflight`. Resume validates again before the
  first push of `dist`.
- **The dist commit is reproducible** — dates and identity from the source
  commit, the parent origin's tip, so a resume rebuilds the same sha. The branch
  is pushed without force, and `dist-vX.Y.Z` is a lightweight tag that is probed
  locally and on origin before anything is pushed and never moved.
- **A missing `dist.sh` beside a plugin with `dist.include` is a refusal** — in
  the release and in the dogfood sync alike, never a release or copy without the
  list.
- **User documentation ships in `manual/`; design stays in `docs/` and never
  ships** — a plugin lists `manual` and never `docs`, its README links into
  `manual/` relatively and reaches design by at most one absolute URL, in a
  Development line. The toolkit follows its own rule: `toolkit/manual/` holds
  the chapters, `docs/` the design.

### Gate sentinels — [references/gates.md](references/gates.md)

- **Opt-in, in `gates.just` and `run-bats.sh`** — `release.just` imports and
  calls neither, and the `precommit`/`prerelease` contract is unchanged; a
  consumer that adds the import line is the only one affected. `gates.just`
  defines one name, so it imports beside `release.just`.
- **The functions travel as an interpolated prolog** — both run in the recipe's
  own shell, and the import line is the only wiring.
- **The consumer declares the inputs, and the cache is true only while every
  check reads inside them** — the toolkit cannot see the checks. A gitlink
  hashes by name only, so a check over one runs uncached ahead of the guard. The
  guard hashes the justfile and the vendored `plugin-dev` tree itself, apart
  from the list, and refuses a pathspec that matches no file; no drift check
  ships.
- **Tool versions are an exported `PLUGIN_DEV_GATE_TOOLS`, empty by default** —
  one shell command per line.
- **A pass is recorded only against the hash taken before the checks, and never
  from a hash that failed** — the guard's, or the one an opt-in `hash-sentinel`
  re-takes after a formatter; moved inputs and an uncomputable hash alike leave
  the checks' verdict standing and say the pass was not recorded.
- **One guard per recipe body, enforced** — a second gate, a record or re-hash
  with no guard, no pathspec and a gate name holding a `/` are each refused.
- **Names are toolkit-neutral, with no aliases** — `PLUGIN_DEV_GATE_DIR`,
  `PLUGIN_DEV_GATE_FORCE`, the `plugin-dev/gates` gitdir path and the
  `plugin-dev-bats.` log prefix.
- **The quiet runner shows the log whenever bats failed with nothing else to
  show, and keeps it only then** — a green run leaves no log in `$TMPDIR`. A run
  that exited 0 having run no test is a failure.
- **gitlore's per-suite bats cache stays out** — bats-specific and larger; a
  later opt-in.

### The reference check — [references/check-refs.md](references/check-refs.md)

- **`check-refs.sh` runs from the consumer's `precommit`, not only at release**
  — a link breaks the day its target moves.
- **A reference is a Markdown link, image or reference definition, never a
  backticked path.**
- **Files are read from disk: every Markdown file git does not ignore, tracked
  or not** — `plugin-dev/` and submodules are skipped. A target exists when the
  same listing holds it, so an ignored or case-folded target is refused and an
  untracked one passes.
- **Dated records and plans are exempt from resolving** — `docs/changelog/` and
  `plans/` by default, a root `refs.exempt` in their place; a link to a file
  deleted later is true history.
- **Shipped stays shipped, with no exemption** — given a `dist.include`, a link
  from a shipped file must reach a shipped file git lists. The set comes from
  `dist.sh paths`, never a second parser. `dist.sh tree` checks the built tree
  from the object store, so a link to an untracked file passes `precommit` and
  refuses the release until committed.
- **`release.just` gains a `check-refs` recipe that nothing depends on** — the
  consumer adds `precommit: check-refs`, a dependency that runs ahead of any
  gate guard on every call.

### The size check — [references/size-check.md](references/size-check.md)

- **A file's size is its bytes, as `wc -c` counts them, not its lines** — a line
  count ignores line length and is honest only after a normalizing wrap; as the
  Read tool presents a file, bytes fit tokens better than non-whitespace bytes
  or lines, because the line-number prefix tracks newlines and indentation.
- **Two fixed caps: 20000 for every counted file, 10000 for any `SKILL.md`** —
  about 10k and 5k tokens as an agent reads the file, at 2.05 bytes per token.
  Neither is configurable.
- **`docs/changelog/` is counted** — a dated record is checked once, by the
  commit that writes it; the changelog index is split by period, not exempted.
- **`check-size.sh` is a shipped script run uncached, wired by hand** — a
  `check-size` recipe in `release.just` that nothing depends on; the consumer
  adds `precommit: check-size`. It reads every file git does not ignore, a set
  no consumer's sentinel hashes.
- **A root `size.exempt` lists overages, each with a reason, and refuses stale
  entries** — a file entry must be over its cap, a directory entry must hold a
  listed file, entries add to the built-ins, and there are no globs.

### This repo's own release — [references/self-release.md](references/self-release.md)

- **The toolkit releases itself with a separate script** —
  `scripts/self-release.sh` is not consumer-shaped: `toolkit/VERSION` in place
  of a manifest, no marketplace entry, two tags. Folding it into `release.sh`
  would make the toolkit consume its own consumer-shaped code.
- **It borrows the shape, not the code** — the same idempotent tail, each step
  probing origin before acting, reached by `just release` and by a
  `just resume-release` that depends on no gate.
- **A bump is refused while the current `toolkit/VERSION` is tagged but not
  fully published**
- **`resume-release` re-cuts `dist-vX.Y.Z` from the `vX.Y.Z` tag, never `HEAD`**
  — and leaves a dist tag origin already holds alone rather than pushing a
  recomputed ref over a published one.
- **The clean-tree exclusion is a literal pathspec here**

### The version-guard hook — [references/version-guard.md](references/version-guard.md)

- **The deny is dual-channel, on stdout with exit 0** —
  `permissionDecisionReason` carries the agent-facing refusal with no escape
  hatch, `systemMessage` the one-line human notice. The manifest is located from
  `CLAUDE_PROJECT_DIR`, never the drifting payload `cwd`, and an Edit is applied
  and re-read rather than pattern-matched.
- **The deny message branches on whether the plugin has ever released** — on the
  same no-semver-tag predicate `release_preflight` uses. The initial-release
  wording says the manifest already holds what the first release will publish,
  and names no route to any other version; only the agent channel branches, and
  a listing that failed takes the restrictive steady-state wording. Nothing
  computed after the deny is decided may fail.

### The dogfood launcher — [references/dogfood.md](references/dogfood.md), [references/dogfood-sync.md](references/dogfood-sync.md)

- **The session loads a real copy at `dist/plugin/`, not a symlink** — Claude
  Code resolves inline roots through `realpath`, so a symlinked root flags the
  source it points to.
- **The copy is the whole repo tree minus what git ignores, every `.git` and
  itself, or only the `dist.include` paths when the plugin has one** — deletions
  propagate, and an ignored name holding an rsync pattern character aborts the
  sync rather than being escaped. The allowlisted copy refuses on a bad list, a
  missing listed path or a missing `dist.sh`, before `dist/` is touched.
- **The plugin root is the repo root** — every consumer has the root layout, so
  nested roots are out of scope.
- **The copy syncs only on `just dogfood`** — a launch, a relaunch or any other
  `claude` through the shim loads the copy as it stands.
- **A launch with no copy exports the copy's path anyway** — the shim sets
  `CLAUDE_CODE_PLUGIN_DIRS` and execs, silently; `/reload-plugins` loads the
  copy the first `just dogfood` makes, with no relaunch. The warning is
  `session-start`'s; the shim neither refuses nor creates the copy.
- **`dogfood.sh` carries `sync`, `pre-tool` and `session-start`, each rooted at
  the script's own location** — never `CLAUDE_PROJECT_DIR` or a payload `cwd`,
  which a resumed session can take from another repository.
- **The copy guard denies an edit into `dist/plugin/`, compared on physical
  paths, and does not rewrite it** — the agent is given the source path.
- **`session-start` reports a session that does not load the copy, a missing
  copy directory, and a missing `jq`** — whole-entry matching on the variable,
  then a directory test; the human gets the remedy, the agent the fact, and
  nothing refuses.
- **A failed sync is loud** — `just dogfood` exits non-zero, and rsync's stderr
  is never redirected. Every refusal, `rsync` missing from PATH included, comes
  before the copy is made, so a refused first sync leaves no copy rather than an
  empty one the session would load in silence.
- **The shim exports `CLAUDE_CODE_PLUGIN_DIRS` rather than passing
  `--plugin-dir`, and execs the next `claude` on PATH** — the variable reaches
  hooks, which is what `session-start` checks. The shim never syncs.
- **The shim appends `<root>/dist/plugin/bin` to PATH unconditionally** — after
  the user's entries, standing in for a marketplace install, which
  `CLAUDE_CODE_PLUGIN_DIRS` does not do, with no probe for the copy, the
  directory or a prior entry, since a PATH entry that is missing or repeated is
  harmless; the argument is in [dogfood.md](references/dogfood.md).
- **`just dogfood` syncs and does nothing else** — the one promotion; it starts
  no `claude` and depends on no gate.
- **`install.sh` wires the hooks; `.envrc`, `.gitignore` and `clean` are
  documented, not edited** — and the sync refuses until git ignores the copy.
- **Existing consumers migrate by a printed note** — `update.sh` does not re-run
  `install.sh`, and breaking the hand-copied shims is accepted.

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
