# claude-plugin-dev — Design

Living design document. Updated when meaningful design decisions land or get
overturned. Not a changelog of features — a record of
*why this project has the shape it has*.

This file is the hub. It carries the motivation, the requirements, the
limitations, and a one-line conclusion for every design decision. The argument
behind each conclusion lives in a node under `references/`, linked from the
group heading above it. Read the hub first and open only the node whose
decisions you are about to touch — a whole-document read is neither needed nor
intended.

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

The toolkit captures: the unified release recipe, the version-guard hook, and a
one-shot install script. Vendored via `git subtree` so the content is versioned
with each consumer.

## Requirements

- Provide a `release` recipe that handles bump → commit → tag → push → GitHub
  release for any plugin whose manifest is at `.claude-plugin/plugin.json`.
- Provide a `PreToolUse(Write|Edit)` hook that refuses agent edits to
  `.claude-plugin/plugin.json`'s `.version`.
- Provide a one-shot installer that vendors the toolkit and wires it into the
  consumer's `justfile` and `.claude/settings.json`.
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
  add, justfile import, hook into `.claude/settings.json`. It only ever adds to
  what the consumer owns, and re-running it is a no-op.
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
- **A first release publishes the manifest version as-is** — a plugin that has
  never been released has nothing to bump from, so an explicit bump there is
  refused, naming the version that will ship instead.
- **The marketplace entry is bumped if present and created if absent** — one
  `just release` publishes a brand-new plugin end to end. The commit and the
  push are separately idempotent, each measured against the remote.
- **No interactive confirmation** — `release` runs behind Claude Code's
  permission layer or a human's own `just`, and the inner prompt re-asked the
  same question.
- **The consumer's commit gate is named `precommit`** — it names the moment it
  fires, and matches the pre-commit ecosystem's vocabulary.
- **`release` depends on `prerelease`, never on `precommit` directly** — a
  consumer whose release gate is bigger than its commit gate widens it there,
  instead of relying on remembering to type a second recipe.
- **The default branch is read from `origin/HEAD`** — with `symbolic-ref`, which
  is silent on stdout when the ref is unset, so the `main` fallback fires
  cleanly.

### Recovery and the pre-flight state checks — [references/recovery.md](references/recovery.md)

- **`check-version.sh` detects a half-landed release** — `plugin.json` against
  its marketplace entry, exposed as a recipe and run as a `release` pre-flight,
  so a release refuses to start on top of an unfinished one.
- **`resume-release` completes one** — the last four steps are an idempotent
  block that probes remote state before acting. It completes a release; it never
  starts one, and it says so when there was nothing to do.
- **A refusal carries the diagnosis and the next command** — where the tree
  state is non-obvious or a release may already be partly public, the message
  states what was checked, what was exempt, and what to run. It ships with the
  vendored tree, so it reaches consumers no memory store or `docs/` page does.
- **A commit a consumer's gate refuses is rolled back** — the manifest bump and
  the marketplace bump alike are restored from HEAD, because the leftover is
  what `common_preflight` then reads as an unrelated dirty tree, blocking both
  `release` and the `resume-release` that would finish a partly-public one.
- **The clean-tree check exempts `.claude/` and the gitlore memory gitlink** —
  an agent session moves both between commits by design, so their being ahead of
  HEAD is the resting state. The memory path is read from `.gitmodules` by
  submodule name; everything else still refuses.

### The version-guard hook — [references/version-guard.md](references/version-guard.md)

- **The deny is dual-channel, on stdout with exit 0** —
  `permissionDecisionReason` carries the agent-facing refusal with no escape
  hatch, `systemMessage` the one-line human notice. The manifest is located from
  `CLAUDE_PROJECT_DIR`, never the drifting payload `cwd`, and an Edit is applied
  and re-read rather than pattern-matched.

## Limitations

- **Hybrid Python+plugin repos (e.g. edify)** are out of scope. Their release
  recipes need PyPI publish, dry-run, rollback, and version bumping via
  `uv version` — different shape entirely. Wrapping edify-style flows into the
  unified recipe would either require conditionals that obscure the main path,
  or break edify outright. Edify keeps its bespoke recipe.
- **`release` is not atomic, but it is recoverable.** The tag push,
  `gh release create` and marketplace push are outward-facing and cannot be
  rolled back, so any failure after the version commit leaves the plugin tagged
  at the new version with a stale marketplace entry. That remains true. Its
  consequence no longer is: `just resume-release` completes the release from
  wherever it stopped. Recovery only ever moves forward to the version already
  committed — rolling a release back is still out of scope.
- **No automated propagation.** When the toolkit ships a new tag, each consumer
  plugin must run `just update-plugin-dev vX.Y.Z` individually. Adopting changes
  is a deliberate per-consumer decision — by design, but worth being explicit
  about.
- **Subtree pull requires the toolkit URL be reachable.** Fully offline
  development of consumers works, but updates need network.
- **The version-guard hook fires only in consumers that ran `install.sh`.** A
  consumer that vendored the toolkit but skipped installing the hook is
  unprotected. Mitigation: `install.sh` does both in one step.
- **Toolkit updates may require a consumer justfile edit.** Adopting a new
  toolkit tag is not always a pure `git subtree pull` — the `prerelease` gate
  landed as a required consumer-side recipe. Releases with such a step ship a
  `migrations/vX.Y.Z.md` note that `update.sh` prints after the pull; the
  upgrade itself never edits consumer files.
- **Solo-author workflow assumed.** The toolkit is built around one maintainer's
  plugins. Multi-contributor scenarios (e.g. forks proposing changes back to the
  toolkit) work mechanically but haven't been ergonomics-tested.
- **No standardised hook library yet.** The toolkit doesn't prescribe
  shellcheck, trailing-whitespace, end-of-file-fixer, etc. for consumer plugins
  — each consumer defines its own `precommit` recipe. May change if patterns
  converge across enough consumers.

## History

Write-time records of each change — what moved and the reasoning available at
the time — live in [changelog.md](changelog.md), one file per entry. This
document states what the toolkit *is*; the changelog states how it got there.
