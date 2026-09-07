# Distribution and versioning

How the toolkit reaches a consumer plugin and how a consumer knows which version
it carries. The conclusions these arguments support are listed in
[../design.md](../design.md).

## Distribution: git subtree, vendored at `plugin-dev/`

The toolkit content lives in each consumer plugin as committed files under
`plugin-dev/`, brought in via `git subtree add` at a tagged release.

Alternatives rejected:

- **A Claude Code plugin published in the marketplace.** Wrong audience: a
  Claude Code plugin extends end-users' sessions during *their* work, while the
  toolkit extends maintainers' sessions during *plugin development*. Same hooks
  API, totally different lifecycle and install destination.
- **Git submodule.** Pointer-vs-content split causes workflow friction — fresh
  clones need `--recurse-submodules`, CI needs an extra init step, the parent
  repo's working tree shows pointer changes that disorient agents. Subtree gives
  "just files" semantics.
- **User-level dotfiles + `just import` from `~/.config/...`.** Rejected because
  release infra must be versioned with the repo so CI, fresh clones, and old
  tags all reproduce. Dotfiles would introduce a contributor-side dependency
  that breaks any of those.
- **Manual copy / vendoring without subtree.** Drift inevitable; no command for
  "pull updates from upstream."

`--squash` is used on both `subtree add` and `subtree pull` so the consumer's
git log isn't polluted with the toolkit's history. The trade-off is harder
push-upstream, but the toolkit-to-consumer flow is one-directional in practice.

**Never hand-edit the vendored copy in a consumer.** The files under a
consumer's `plugin-dev/` are subtree-managed content owned by this repo. To
change what a consumer vendors, edit the source *here*, cut a tagged toolkit
release, then propagate into each consumer with
`just update-plugin-dev dist-vX.Y.Z` (which runs `git subtree pull`). Editing
`<consumer>/plugin-dev/*` directly reintroduces exactly the drift the subtree
model exists to prevent: the consumer's copy silently diverges from every other
consumer and from the tagged source, and the next `subtree pull` will conflict.
The single source of truth is `ddaanet/claude-plugin-dev` at a tag — nowhere
else.

## Consumers vendor a split dist ref, not the source tag

`git subtree` copies the **root tree** of whatever ref it is given. This repo's
root is its own working environment — a `memory` gitlink, `.claude/`, `.envrc`,
`.gitlore/`, `CLAUDE.md`, this repo's own `justfile`, `docs/`, `plans/`,
`tests/` — so vendoring a source tag shipped all of it into every consumer,
tracked in the consumer's own history.

Three of those actively misbehave rather than merely cluttering. The `memory`
gitlink is unregistered in the consumer's `.gitmodules`, so a bare
`git submodule status` fatals for the **whole repo** even though every submodule
the consumer registered is fine. `.claude/settings.json` and `CLAUDE.md` are
read by Claude Code for the directory an agent works in, so a consumer's agent
operating under `plugin-dev/` picked up this repo's hooks and instructions.

The consumer-facing files therefore live under `toolkit/`, and `just release`
cuts a second tag per release: `git subtree split --prefix=toolkit` yields a
commit whose root **is** `toolkit/`, tagged `dist-vX.Y.Z`. Consumers vendor
that. `tests/dist-tree-test.sh` pins the shipped set exactly, so adding a file
to `toolkit/` is a deliberate act rather than a silent inheritance.

Both `install.sh` and `update-plugin-dev` accept **only** a `dist-v*` ref. Every
other ref — source tag, branch, sha — resolves to the root tree and so
reintroduces the entire leak; a source tag is refused by name
(`pull dist-vX.Y.Z instead`), everything else by shape. A warning would not do,
because the damage is silent until someone runs `git submodule status`.

That refusal is what makes the fetch-time submodule collision unreachable, and
both call sites dropped the `-c fetch.recurseSubmodules=no` they used to carry.
The collision needed the fetched lineage to contain a gitlink at a path the
consumer had registered; the dist lineage contains no gitlink at all, and no
other lineage is vendorable. Keeping the flag "just in case" would be guarding a
case that can no longer arise — cruft with a reassuring name.

Migration needs nothing manual. A consumer vendored from a source tag has the
leaked paths in its tree, and its first pull of a `dist-` tag deletes all of
them in that same commit — verified against a consumer fixture carrying all 37
leaked paths, which came out at exactly the 8 shipped files with
`git submodule status` back to exit 0, no conflicts.

Rejected alternatives:

- **Building the dist tree from an allowlist** with `git mktree`/`commit-tree`
  at release time. Avoids moving files, but trades a one-time restructuring cost
  for permanent bespoke plumbing whose failure mode is silently shipping the
  wrong tree. `subtree split` is a supported command that does exactly this job,
  and costs *less* release-recipe code, not more.
- **Pruning the leaked paths after the subtree pull**, inside
  `update-plugin-dev`. The prune would live in the consumer's *vendored* copy,
  and it is that copy — not the tag being requested — which executes the
  upgrade, so the fix could never reach a consumer that does not already have
  it. Locally deleting files the upstream ref still contains also makes every
  subsequent 3-way subtree merge conflict.
- **Registering `plugin-dev/memory` in the consumer's `.gitmodules`.** Silences
  the error by making this repo's private memory a real submodule of every
  consumer — the opposite of the intent.
- **Untracking the offenders here** (`.claude/`, `.envrc`, `.gitlore/`). Partial
  at best: `memory` is a gitlore submodule that must stay committed, and
  `CLAUDE.md`, `justfile`, `docs/` and `tests/` are the repo. It cannot reach a
  clean shipped set.

## Versioning: tags only, never `HEAD`

`install.sh` and `update-plugin-dev` both take a ref like `dist-vX.Y.Z` (see
"Consumers vendor a split dist ref" for why the `dist-` lineage rather than the
source tag). Branch refs (`main`, `master`, `HEAD`) and a source `vX.Y.Z` ref
are refused outright.

The ref is optional: with none given, both resolve the newest `dist-` tag from
the remote (`git ls-remote --sort=-v:refname`) and say which one they picked.
That is still tag-pinning, not `HEAD`-tracking — the resolution happens once, at
invocation, and the subtree commit records the exact tag vendored, so an old
consumer checkout still names the exact toolkit content it carries. Passing a
ref explicitly remains the way to pin an older one.

Reasoning: the toolkit's whole purpose is release discipline. It would be
inconsistent to ship that infrastructure with no version discipline of its own.
More concretely:

- A consumer-plugin checkout at an old tag must give the *exact* toolkit content
  vendored at the time. Tracking `main` makes the subtree's effective version a
  function of "when did I last pull," which is unrecoverable.
- Bisection across toolkit changes only works if there are stable refs to bisect
  over.
- Forced reflection at toolkit-release time — same discipline the toolkit
  imposes on consumers.

## Separate repository, not part of any plugin

The toolkit lives at `ddaanet/claude-plugin-dev`, separate from the plugins that
consume it.

Pairs with `ddaanet/claude-plugins` (the marketplace) as a coherent naming set:
`claude-plugins` is what gets shipped to users; `claude-plugin-dev` is what the
maintainer uses to ship them.

Embedding the toolkit inside any single consumer would couple the toolkit's
release cadence to that plugin's, and make subtree-pull's canonical URL
ambiguous.

## Single `install.sh` handles bootstrap and wire

`install.sh` does three things in one invocation: `git subtree add` the toolkit
(if not already present), inject the `import` line into the consumer's
`justfile`, and add the version-guard hook to `.claude/settings.json`.

Everything it touches outside `plugin-dev/` belongs to the consumer, so it only
ever adds: the justfile keeps its own content and its trailing newline, and
`settings.json` is rewritten by a jq pass that appends one hook and preserves
the rest of the document, its mode and its ownership. A jq failure over an
existing `settings.json` is a hard error that leaves the file alone — never a
fall-through to writing a fresh one, which would mean an install silently
replacing a consumer's whole configuration.

Earlier draft: split into a separate "vendor" step (manual `git subtree add`)
and a vendored "wire" step (`bash plugin-dev/install.sh` post-vendor). Rejected
— the bootstrap loop ("you can't run `plugin-dev/install.sh` until `plugin-dev/`
exists") is solved by making the script self-aware of which phase it's in. One
step is worth more than the conceptual purity of separation.

## The bootstrap is `curl … | bash`, at a dist tag

The README resolves the newest `dist-` tag with `ls-remote` (so the block never
names a version and cannot go stale), fetches that tag's root `install.sh` over
HTTPS, and pipes it to bash with the same tag as its argument. A `dist-` ref's
root tree *is* `toolkit/`, so the URL serves the very file the plugin is about
to vendor, at the ref it vendors: no second distribution channel exists to fall
out of step with the dist lineage, and no release asset has to be uploaded and
kept correct. Passing the tag through spares `install.sh` the `ls-remote` on its
no-ref path and, more to the point, makes fetched script and vendored tree one
release by construction — they are otherwise two independent queries, over HTTPS
here and the SSH `TOOLKIT_URL` there.

Fetching to a file and running that is rejected. Its usual justification — the
script can be inspected before execution — describes nothing that happens: every
form of this block fetches a remote script and immediately runs it, so the extra
step performs the letter of the rule against `curl … | bash` while doing the
same thing in spirit, and at a fixed `/tmp` path it adds a file someone else can
pre-plant or swap between the fetch and the run. The one substantive property a
file buys is atomicity — bash executes what it has read, so a dropped connection
can run a truncated installer — and `install.sh` being idempotent covers it: a
partial run is repaired by running it again, the same remedy as for any other
interrupted install. A sibling-checkout shortcut is rejected for the docs too: a
local checkout is a local optimisation, and the instructions must work for
someone who has only the plugin repo in front of them.

## Run-in-target invocation pattern

`install.sh` reads `$PWD` as the target plugin. The alternative — taking a
target path as argument — was rejected for ergonomics (matches
`pre-commit install`, `npm init`, etc.). The magic-cwd risk is contained by an
early guard: the script aborts if the cwd doesn't contain
`.claude-plugin/plugin.json`.

## Update flow lives in `update.sh`, not the recipe

`update-plugin-dev` is a one-line wrapper: `bash plugin-dev/update.sh "$ref"`,
mirroring how `release` wraps `release.sh`. The guards, ref resolution, subtree
pull, VERSION check and migration-note printing all live in the script. A
justfile recipe body is second-class code here: it escapes `shellcheck` and
`bash -n` (the precommit gate lints scripts, not recipe bodies), it cannot be
executed directly by a test, and just's own parsing quirks apply inside it. The
recipe keeps only what must be just's: the `toolkit_url`/`toolkit_prefix`
settings and the recipe name.

The small dist-tag resolver is deliberately duplicated between `install.sh` and
`update.sh` (each side says so in a comment). The bootstrap script must stay
runnable on its own from a fresh clone, so it cannot depend on a sibling file,
and a shared lib file would grow the shipped set to spare a few lines.

## Migration notes: shipped in the dist tree, printed, never applied

Some toolkit releases need a consumer-side step the subtree pull cannot perform
— v0.4.0 required a `prerelease` recipe in the consumer's justfile before the
import would resolve. Those steps used to live only in per-release briefs
written by hand.

A release that has such a step ships `migrations/vX.Y.Z.md` in its dist tree.
After the pull, `update.sh` prints every note in the crossed range (old
`VERSION` exclusive, new inclusive, `sort -V` order). The notes are guidance for
the human to apply: an upgrade never touches files outside `plugin-dev/`,
because a consumer's justfile and settings are theirs, and a silently-mutating
upgrade is exactly the class of surprise the rest of this design exists to
prevent. Most releases need no note; the directory may not exist at all.

Structural limit, the same one that ruled out pruning leaked paths in
`update-plugin-dev`: the consumer's *existing* vendored copy executes the
upgrade, so the release that introduces a behaviour cannot deliver it to the
upgrade that lands it. Tolerable for guidance — the note is also readable in the
pulled tree and the release notes.

## Toolkit version source of truth: `VERSION` file (not tags only)

The toolkit ships a plain-text `VERSION` file at the repo root, bumped by the
self-release recipe in lockstep with the git tag.

Tag-only SOT was the obvious first choice — the toolkit has no `plugin.json`,
and tags already encode releases. It was rejected because the toolkit is
consumed via `git subtree`, and **tags don't propagate through subtree pulls**.
A consumer's vendored `plugin-dev/` directory is "just files," with no way to
ask "what version is this?" from inside the consumer's checkout.

Concrete consequences without `VERSION`:

- Consumers had to hand-maintain a version string in their `CLAUDE.md` to
  remember what they vendored — drift inevitable.
- `update-plugin-dev vX.Y.Z` had no way to verify the subtree pull actually
  applied (a half-applied pull, e.g. with merge conflicts, could leave older
  content in place silently).
- The toolkit's own `install.sh` and scripts couldn't self-identify without
  `git describe`, which fails on subtree-vendored copies.

`VERSION` solves all three: `cat plugin-dev/VERSION` is the authoritative answer
inside any consumer; `update-plugin-dev` can warn on mismatch; toolkit scripts
can read their own version from disk.

The cost is one line in the self-release recipe (write VERSION before the
commit) and the discipline of bumping it together with the tag — the same
invariant the consumer release recipe enforces on `plugin.json`. Submodules and
packages would have made this moot, but those were rejected for other reasons
(see "Distribution").
