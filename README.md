# claude-plugin-dev

Shared release infrastructure for Claude Code plugins: a `just release`
recipe, a version-guard hook, and a one-shot installer, vendored into
each consumer plugin with `git subtree`.

**This repository is not a Claude Code plugin.** Nothing here is
installed into a Claude Code session from a marketplace. It is a
development toolkit whose artifacts run inside *other* repositories —
the plugin repos a maintainer ships from.

## Why it exists

Several plugins under the same author needed the same release flow, and
each had drifted on the details — commit message format, confirmation
prompts, branch detection. A fix in one never reached the others. At the
same time nothing stopped an agent from hand-editing
`.claude-plugin/plugin.json`'s version during development; the mismatch
surfaced days later, when a release failed.

Both problems have one answer: a single source of truth for release
infra, vendored into each plugin at a tag, with the invariant enforced by
a `PreToolUse` hook. See [docs/design.md](docs/design.md) for the full
rationale, including the alternatives that were rejected.

## What a consumer plugin gets

- **`just release [patch|minor|major]`** — pre-flight checks, bump
  `plugin.json`, commit, tag, push, create the GitHub release, and bump
  (or create) the plugin's `marketplace.json` entry.
- **`just resume-release`** — completes a release that landed only
  partially, by probing remote state and doing only what is missing.
- **`just check-version`** — `plugin.json` against its marketplace entry;
  also runs as a `release` pre-flight, so a release refuses to start on
  top of an unfinished one.
- **`just update-plugin-dev [dist-vX.Y.Z]`** — pulls a newer toolkit
  version in and prints the migration notes for the range crossed.
- **A version-guard hook** that refuses agent edits to the manifest's
  `.version`, with a verbose agent-facing refusal and a one-line human
  notice.

[toolkit/README.md](toolkit/README.md) is the manual for all of it, and
ships with the vendored copy — that is the file a plugin maintainer
reads day to day.

## Installing in a plugin

Resolve the newest **dist** tag, fetch that tag's `install.sh`, and run
it from the plugin's root directory:

```sh
repo=ddaanet/claude-plugin-dev
cd /path/to/your/plugin
tag=$(git ls-remote --tags --refs --sort=-v:refname \
        "https://github.com/$repo.git" 'dist-v*' | head -1 | sed 's|.*/||')
curl -fsSL "https://raw.githubusercontent.com/$repo/$tag/install.sh" \
    | bash -s -- "$tag"
```

A `dist-` tag's root tree *is* `toolkit/`, so that URL serves exactly the
`install.sh` the plugin is about to vendor, at exactly the ref it vendors
— there is no separate download channel to keep in step. Passing `$tag`
on to the script makes the installer and the vendored tree one release by
construction, instead of two independent lookups that normally agree.

The block names no version, so it cannot go stale. To pin an older
toolkit, substitute its dist tag in both places. The first install needs
`curl`; nothing else here does.

`install.sh` reads `$PWD` as the target plugin and aborts unless it finds
`.claude-plugin/plugin.json` there. It vendors the toolkit under
`plugin-dev/`, adds `import 'plugin-dev/release.just'` to the justfile
(creating one if absent), and wires the version-guard hook into
`.claude/settings.json`. It only ever adds — your justfile and settings
keep their content. Re-running with everything already in place is a
no-op.

Then define the two gates the recipes depend on:

```just
import 'plugin-dev/release.just'

precommit:
    jq . .claude-plugin/plugin.json > /dev/null
    bash -n scripts/*.sh
    # ...whatever else your plugin needs...

prerelease: precommit
```

`prerelease` is what `release` depends on, and it is mandatory — just
rejects a justfile whose dependency names a missing recipe, so omitting
it fails immediately rather than silently at release time. For most
plugins `prerelease: precommit` is the whole recipe; a plugin with slow
or paid checks widens it (`prerelease: precommit evals`) without putting
them on every commit.

Commit the result:

```sh
git add plugin-dev justfile .claude/settings.json
git commit -m "add claude-plugin-dev toolkit"
```

## Updating in a plugin

```sh
just update-plugin-dev                 # newest dist tag on the remote
just update-plugin-dev dist-vX.Y.Z     # or pin one
```

To see what is available:

```sh
git ls-remote --tags --refs --sort=-v:refname \
    git@github.com:ddaanet/claude-plugin-dev.git 'dist-v*'
```

Updates are per-consumer and deliberate: a new toolkit tag reaches a
plugin only when someone runs this. A release needing a consumer-side
step ships a note at `plugin-dev/migrations/vX.Y.Z.md`, printed after the
pull — the update itself never edits files outside `plugin-dev/`.

**Never hand-edit `plugin-dev/` in a consumer.** It is subtree-managed
content owned by this repo; local edits diverge from every other consumer
and conflict on the next pull. Change the source here, cut a release, and
pull the tag.

## Versioning

Each release cuts **two** tags. `vX.Y.Z` is the source tag; `dist-vX.Y.Z`
is a `git subtree split --prefix=toolkit` of the same commit, so its root
tree is exactly the consumer-facing files. Consumers vendor the `dist-`
tag — `git subtree` copies a ref's *root* tree, and this repo's root is
its own working environment (a `memory` submodule, `.claude/`,
`CLAUDE.md`, its own justfile, docs and tests). Both `install.sh` and
`update-plugin-dev` refuse a source ref by name and anything else —
branch, sha, `main` — by shape.

Given no ref, both resolve the newest `dist-` tag from the remote and say
which one they picked. That is still tag-pinning: the resolution happens
once, and the subtree commit records the exact tag vendored, so an old
consumer checkout still names the toolkit content it carries.

`toolkit/VERSION` holds the last-released version in plain text, because
tags do not propagate through a subtree pull — `cat plugin-dev/VERSION`
is the authoritative answer from inside a consumer.

## Requirements

`bash`, `jq`, `git`, `gh`, and [`just`](https://just.systems) in the
consumer plugin.

## Working on the toolkit itself

`toolkit/` is the shipped boundary: everything under it, and nothing
else, reaches a consumer. The repo root is this repo's own working
environment and stays here. Adding or removing a shipped file means
updating the list in `tests/dist-tree-test.sh`, which fails otherwise.

```sh
just precommit    # shellcheck + bash -n + the four test scripts
just release [patch|minor|major]
```

`release` bumps `toolkit/VERSION`, commits `release: X.Y.Z`, cuts both
tags, pushes, and creates the GitHub release. It refuses to run on a
dirty tree or when `VERSION` disagrees with the latest tag — the same
invariant the consumer recipe protects on `plugin.json`.

Don't run `release.just`'s recipes from this repo: they expect a
consumer-shaped layout and will fail or produce nonsense here.

- [docs/design.md](docs/design.md) — living rationale for every design
  decision; what the toolkit *is*.
- [docs/changelog.md](docs/changelog.md) — dated write-time records of
  how it got there.
- [CLAUDE.md](CLAUDE.md) — conventions binding on agent sessions in this
  repo.

## License

MIT
