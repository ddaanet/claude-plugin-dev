# Dist branch release — plan

Promoted from two inbox briefs:
[the dist branch brief](../2026-10-15-brief-dist-branch-release.md) (from
handoff) and
[the url-source brief](../2026-10-14-brief-marketplace-entry-url-source.md)
(from ghmem). My human partner took every default proposed on 2026-10-15; the
choices are recorded under "Decisions". Ships as one minor release, 0.10.0.

## Problem, verified

Handoff carries a gitlink (`memory`, the gitlore submodule) at its repo root,
which is its plugin folder. The Anthropic plugin directory refuses a plugin
folder holding a gitlink, and these plugins ship from the root, so
`git subtree split` and a subfolder layout are out (the brief's "Rejected
approaches"). A branch carrying only the shipped paths is the remaining shape.

Probed on 2026-10-15 (CC 2.1.300):

- Building a tree from handoff's HEAD restricted to
  `.claude-plugin skills hooks scripts bin README.md LICENSE` with
  `ls-tree -r -z` piped into `update-index -z --index-info` on a temp
  `GIT_INDEX_FILE`, then `write-tree`, gives 25 files, no gitlink or symlink,
  and passes `claude plugin validate --strict` once extracted with
  `git archive`. Handoff has no `LICENSE` file (its `plugin.json` sets
  `license`), so the brief's example allowlist names a missing path.
- The marketplace reference lists `url | url, ref, sha`, with `ref` a branch or
  tag. Updates follow the entry's `version`, which `bump_marketplace` raises
  every release, so a `ref: dist` entry needs nothing more.
- `claude plugin validate --strict` passed a marketplace entry carrying a
  misspelled `reff`, so validate is no evidence that `ref` is honoured. The docs
  are the evidence; the release test pins the field.
- `bump_marketplace` creates entries as `{source: "github", repo}`, which clones
  over SSH (url-source brief).

## Decisions

1. **Existing marketplace entry:** when the plugin opts in, `bump_marketplace`
   sets `.source.ref = "dist"` and touches nothing else in `source`. Without
   opt-in, existing entries' `source` is never rewritten.
2. **Validation runs in the pre-flight**, on the tree built from HEAD before the
   bump commit, so a failure leaves no commit and no tag. The bump commit
   changes only `.version` in `plugin.json`, so the validated tree and the
   shipped one differ in that string alone. `--resume` validates again before
   the first push of `dist`. Opt-in without `claude` on PATH is refused in the
   pre-flight.
3. **A listed path absent from the tree is refused**, at release and at sync.
4. **The dist commit is reproducible:** author and committer dates are taken
   from the source commit, the parent is origin's `dist` tip (none for the first
   release), so `--resume` rebuilds the same sha and compares instead of
   guessing. Pushed as `<sha>:refs/heads/dist` without force.
5. **Dogfood sync** copies only the listed paths when the allowlist exists,
   still from the working tree, still minus ignored paths.
6. **A new shipped script, `toolkit/dist.sh`**, holds the allowlist reader, the
   tree build and its checks, used by `release.sh` and `dogfood.sh`.
7. **The url-source brief lands first**, in the same release.

## Slice 0 — entry creation writes a `url` source

`toolkit/release.sh`, `bump_marketplace`, creation branch: `source` becomes
`{source: "url", url: ("https://github.com/" + $repo + ".git")}`. The slug
derivation is unchanged. The `repository` fallback is unchanged.

Tests: `tests/release-test.sh` pins the created entry's `source.source` as
`github` (around the "created entry source type" assertion); it changes to pin
the whole `source` object. Red first: the assertion fails against the unchanged
script. The existing-entry path keeps a `github` fixture entry and asserts its
`source` is untouched.

## Slice 1 — `toolkit/dist.sh`

### The allowlist: `dist.include` at the repo root

One path per line, relative to the repo root. A trailing `/` is allowed and
stripped. Blank lines and lines starting with `#` are skipped. Refused, naming
the line: an absolute path, a `..` component, a leading or trailing blank, and
any of `* ? [ ] \` (paths are literal; the same set `dogfood.sh` already refuses
for rsync). `dist.include` itself is not shipped unless listed.

### Subcommands

Each prints one `dist:` line per refusal on stderr and exits 1; stdout carries
only the result.

- `dist.sh enabled <commit>` — exit 0 when `dist.include` exists in that
  commit's tree, 1 when not. Release reads the allowlist from the commit, never
  the worktree.
- `dist.sh tree <commit>` — prints the sha of a tree holding exactly the listed
  paths of `<commit>`, built with plumbing on a temp `GIT_INDEX_FILE`, NUL
  delimited throughout, pathspecs literal (`GIT_LITERAL_PATHSPECS=1`). Refuses:
  a listed path matching nothing; a gitlink (160000) or symlink (120000)
  anywhere in the result; no `.claude-plugin/plugin.json`. Warns (stderr, exit
  0): more than 512 files; a file over 256 KiB not ending in
  `.png .jpg .jpeg .gif .webp .woff .woff2 .ttf .otf`; a root `README.md` under
  40 words; no `LICENSE*` file and no `license` in `plugin.json`. Each warning
  says it sends the plugin to directory review, not that it blocks.
- `dist.sh validate <tree>` — `git archive` into a temp dir, run
  `claude plugin validate --strict` there, exit with its status. Refuses when
  `claude` is not on PATH.
- `dist.sh commit <source-commit> <tree> <version> [<parent>]` — `commit-tree`
  with message `dist v<version> from <full source sha>`, author and committer
  name, email and date copied from the source commit, so the same inputs give
  the same sha. Prints the sha.
- `dist.sh paths <root>` — for `dogfood.sh`: reads `<root>/dist.include` from
  the worktree, applies the same line rules and the absent-path refusal against
  the worktree, prints the normalised paths NUL-delimited. With no
  `dist.include` it prints nothing and exits 3, so the caller can tell "not
  opted in" from a refusal.

### Tests: new `tests/dist-test.sh`

One script under test, its own copy of the harness. Fixture repos built in a
temp dir; `claude` is a stub on PATH recording its arguments and exiting with a
configurable status. Cases, each red first against a `dist.sh` that does not
exist yet or lacks the behaviour:

- handoff's allowlist (with a fixture `LICENSE`) builds a tree with exactly the
  listed paths; a dev file at the root (`plans/x.md`, `memory` gitlink outside
  the list) is absent;
- refusals: gitlink inside a listed directory, symlink inside one, no
  `plugin.json`, a listed path missing, each bad line form;
- a path holding a space and one holding a newline survive the build;
- `commit` twice with the same inputs gives the same sha; the message and dates
  are as specified; with no parent the commit is a root;
- `validate` passes the extracted tree's directory to the stub with `--strict`
  and propagates a failing status; refuses with no `claude` on PATH;
- warnings fire at the thresholds and do not change the exit status;
- `paths` exit 3 without the file.

Add the suite to `justfile`'s `precommit` (both the `bash -n` list and the run
list), `toolkit/dist.sh` to the shellcheck list, and `dist.sh` to
`tests/dist-tree-test.sh`'s shipped list and to `CLAUDE.md`'s Layout list
(`doc-sync-test.sh` checks the latter against `toolkit/`).

## Slice 2 — `release.sh` publishes `dist`

Opt-in is `dist.sh enabled` on HEAD (release) or on `$tag^{commit}` (resume).
All of it is skipped, and output is unchanged, when not opted in.

- **Pre-flight** (release mode, inside `release_preflight` after its existing
  checks): refuse without `claude` on PATH; `dist.sh tree HEAD` then
  `dist.sh validate`. Any failure dies before `bump_commit_tag`.
- **`push_dist`**, a new step between `push_tag` and `create_github_release`, so
  the marketplace never names a `ref` that is not on origin:
  1. `tip=$(ls_remote_sha . refs/heads/dist)`.
  2. If `tip` is non-empty and its message (fetched with `git fetch origin dist`
     when not local) reads `dist v$V from <tag commit>`, the branch already
     landed: `dist_sha=$tip`. Otherwise build `tree`, `validate` it on resume,
     `dist_sha=$(dist.sh commit …)` with `tip` as parent, and
     `git push origin "$dist_sha:refs/heads/dist"`. A rejected push dies with a
     hint naming `just resume-release`; it is never retried with force.
  3. Tag `dist-v$V`: lightweight, local and on origin, at `dist_sha`. Probed
     like `push_tag`: a local or origin tag at another sha is refused, never
     moved.
  4. Notes in the existing voice: `dist: pushed`, `dist: already pushed`,
     `dist tag dist-v$V: pushed` / `already pushed`; each action sets `acted`.
- **`bump_marketplace`**: when opted in, the jq for both paths also sets
  `.source.ref = "dist"`. The no-op guard keeps working: an entry already at
  `$V` with `ref: dist` is byte-identical.
- `release.sh` finds `dist.sh` beside itself, the way the consumer vendors both
  under `plugin-dev/`.

### Tests: new `tests/release-dist-test.sh`

Same fixture shape as `release-test.sh` (local bare origins, `gh` stub) plus a
`claude` stub, copying `dist.sh` beside `release.sh`. A second suite for the
same script under test keeps `release-test.sh` (1730 lines) from growing.

- first opted-in release: origin `dist` is a root commit holding only the listed
  paths; `dist-vX.Y.Z` on origin points at it; message names the release commit;
  the marketplace entry carries `ref: dist` and its type unchanged;
- second release: `dist` gains one commit whose parent is the first;
- validation failure (stub exits 1): no commit, no tag, nothing pushed, manifest
  unchanged;
- no `claude` on PATH: refused before any commit;
- resume after each kill point — after `push_tag`, after the dist branch push,
  after the dist tag push — finishes, and a second resume prints
  `already complete (nothing to do)`;
- origin `dist-vX.Y.Z` at a foreign sha: refused, nothing moved;
- not opted in: no `dist` ref on origin, no `claude` call, marketplace entry has
  no `ref`.

Kill points use the git-wrapper technique `release-test.sh` already uses.

## Slice 3 — `dogfood.sh sync` honours the allowlist

When `dist.sh paths "$root"` exits 0, rsync gets the existing excludes first
(ignored paths, `.git`, `/dist/plugin/`), then for each listed path an include
rule for it and each parent directory (`+ /a/`, `+ /a/b/`, and `+ /a/b/***` for
a directory), then `- *`. Filter rules go through `--filter` merge input
NUL-delimited, keeping `--delete --delete-excluded`. Exit 3 keeps today's
behaviour. Exit 1 refuses the sync with `dist/` untouched.

Tests (`tests/dogfood-sync-test.sh`): an unlisted root file is absent from the
copy; an untracked file inside a listed directory is present; an ignored file
inside one is absent; a file deleted from a listed directory leaves the copy; a
listed path missing refuses the sync and leaves the previous copy intact; no
allowlist behaves as today. The `vendored` copy of `dist.sh` sits beside
`dogfood.sh` in the fixture.

## Slice 4 — docs

- New node `docs/references/dist-branch.md`: why a branch (directory follows a
  branch; gitlink refusal), why an allowlist (denylist ships new dev files
  silently), why plumbing over subtree split and subfolders, reproducible
  commits and resume, validation in the pre-flight, the directory rules the
  checks mirror. Hub conclusions in `docs/design.md`.
- `docs/references/dogfood-sync.md` "The source set": rewritten in place for the
  allowlisted case; hub line if it states the source set.
- `docs/references/release-flow.md` "Marketplace entry": `url` source on
  creation, `ref: dist` on opt-in.
- `docs/references/recovery.md`: `push_dist` in the resumable tail.
- `toolkit/README.md`: opt-in section (create `dist.include`, commit it,
  release; the first release creates `dist`; point the directory at `dist`).
- `toolkit/migrations/v0.10.0.md`: the opt-in steps, and that nothing changes
  without `dist.include`.
- `CLAUDE.md` Layout (`dist.sh`), quality gate list (two new suites).
- Dated record `docs/changelog/2026-10-15-dist-branch-release.md` and index
  bullet.

## Process

Slices in order, each red then green, per the shared TDD split: tests by a
Sonnet author, red reviewed by a different agent, green by Haiku, reviewer one
rung above. Slices 0 and 2 change `release.sh`; slice 1 must land before 2 and
3. Red runs saved under `reports/`. `just precommit` before each commit, run by
the main session. Then `just release minor`, and dogfood the same day:
`just update-plugin-dev dist-v0.10.0` in handoff, add its `dist.include`, run
`just dogfood` and check the copy, then a handoff release creates `dist`.

## Open

- Handoff's rename to `autodrive-handoff` is handoff's work; nothing here
  depends on the plugin name.
- Whether the portal accepts `dist` before its first push is untested; the first
  release creates it before anyone points the directory at it.
