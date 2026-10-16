# The dist branch

Why a plugin can publish a branch holding only its shipped paths, why the paths
are an allowlist, why the tree is built with plumbing, and why the commit is
reproducible. The marketplace entry that follows the branch is in
[release-flow.md](release-flow.md); the resumable tail that pushes it is in
[recovery.md](recovery.md); the dogfood copy that mirrors the same set is in
[dogfood-sync.md](dogfood-sync.md). The conclusions these arguments support are
listed in [../design.md](../design.md).

## Why a branch

The Anthropic plugin directory refuses a plugin folder that holds a gitlink. A
plugin whose repo root is its plugin folder and that mounts a submodule there,
as the gitlore `memory` mount is, cannot be submitted from `main`. The
alternatives, all rejected:

- **A `git subtree split` of a subfolder.** It needs the plugin to live in a
  subfolder. Every consumer has the root layout, and `install.sh` refuses a repo
  without a root `.claude-plugin/plugin.json`.
- **Moving the plugin into a subfolder.** The same layout change, paid by every
  consumer, to solve one consumer's gitlink.
- **Removing the gitlink.** The memory mount is a consumer's own working
  environment, not the release's to take away.

A branch carrying only the shipped paths is the remaining shape. The directory
follows a branch, and a marketplace `url` source takes a `ref`, so the entry
points at `dist` and the plugin folder the directory sees has no gitlink in it.

## Why an allowlist

`dist.include` at the repo root lists the paths that ship, one per line. A
denylist ships every new dev file silently: a `plans/` directory, a scratch
note, a fixture added next month reaches the directory the day it is committed.
An allowlist inverts the failure. A forgotten path is missing from the plugin,
which `claude plugin validate --strict` and the plugin's own use show at once,
and a listed path that matches nothing is refused.

The file is read from the release commit's tree, never the worktree, so what
ships is what was committed. `dist.include` itself ships only when it lists
itself. A plugin without the file is not opted in, and nothing in the release or
the sync changes for it.

### The line rules

A path is literal. One per line, relative to the root; a trailing `/` is
stripped; blank lines and lines starting with `#` are skipped. Refused, naming
the line:

- an absolute path, a `..` component, a `.` component, an empty component, and a
  `.git` component;
- a leading or trailing blank;
- `*`, `?`, `[`, `]` and a backslash, the set `dogfood.sh` already refuses for
  rsync, so one file means one thing to both consumers of it;
- a carriage return, because a CRLF file would carry `\r` into every path and
  every line would then match nothing, which reads as a missing-path refusal on
  all of them. The file is refused whole, naming the cause.

A refused line is not matched against the tree, so it yields one refusal.

## Why plumbing

`dist.sh tree` reads `git ls-tree -r -l -z` of the release commit, keeps the
entries equal to or under a listed path, and feeds them to
`git update-index -z --index-info` on a temporary `GIT_INDEX_FILE`, then
`write-tree`. No checkout, no worktree, no branch switch, and the user's index
and working tree are never touched. Everything is NUL-delimited and pathspecs
are literal (`GIT_LITERAL_PATHSPECS=1`), so a path with a space or a newline
survives; a `git archive | tar` round trip or a `rsync` into a scratch repo
would have touched the filesystem and its quoting instead.

The tree is checked, not trusted. Refused: a listed path matching nothing; a
gitlink or symlink anywhere in the result, because the gitlink is what the
directory refuses and a symlink can point outside the plugin; no
`.claude-plugin/plugin.json`; a `plugin.json` that is not JSON.

Warnings, stderr and exit 0, each saying the plugin goes to directory review
rather than that it is blocked: more than 512 files; a file over 256 KiB that is
not a font or an image; a root `README.md` under 40 words; no `LICENSE*` at the
root and no `license` in `plugin.json`. They warn and never refuse, because they
are the toolkit's reading of what draws review rather than the directory's
published rule. They are computed on the result tree only.

## Validation runs in the pre-flight

`claude plugin validate --strict` runs on the tree extracted with `git archive`,
in the release pre-flight, before the bump commit. A failure leaves no commit
and no tag. The bump commit changes only `.version` in `plugin.json`, so the
validated tree and the shipped one differ in that string alone.

The dist pre-flight is its own step after `release_preflight`, because
`release_preflight` returns early on a first release, and the first release is
the one that creates `dist`. Opt-in without `claude` on PATH is refused there,
before anything is done, rather than released unvalidated.

`--resume` validates again, on the tree it is about to publish, before the first
push of `dist`: a resume has no pre-flight of its own to lean on.

`validate` is no evidence that a marketplace field is honoured: it passed an
entry carrying a misspelled `reff`. The release test pins `ref`, and the
marketplace reference is the evidence that the directory follows it.

## Reproducible commits

The dist commit's message is `dist v<version> from <full source sha>`. Author
and committer name, email and date are copied from the source commit, and the
parent is origin's `dist` tip, none for the first release. The same inputs give
the same sha, so a resume rebuilds the commit and compares instead of guessing
what an interrupted run pushed.

"Already landed" is detected from the tip's subject: a tip reading
`dist v$V from <the tag's commit>` is this release's, taken as it stands. A tip
that is anything else is built on, as the parent. The subject suffices without
comparing trees: it names the tag's full commit sha, and the tree is built from
that commit's own `dist.include` and files, so only a commit forging the subject
by hand could carry a different tree. The branch is pushed as
`<sha>:refs/heads/dist` without force, so a rejected push is a divergence to
look at and is never retried by overwriting. The release commit is never rebuilt
to match: the dist commit follows the source, not the reverse.

`dist-v<version>` is a lightweight tag at the dist commit, local and on origin.
The branch tip moves; the tag names one release's tree. A local or origin tag at
another sha is refused and never moved, and both are probed before the branch is
pushed, so a conflicting tag leaves nothing pushed rather than a branch ahead of
a tag that cannot follow it.

## When the script is missing

`release.sh` and `dogfood.sh sync` both refuse when `dist.include` exists and
`dist.sh` is not vendored beside them. A toolkit older than the file would
otherwise release or sync without the allowlist the plugin asked for, and ship
what the list leaves out. A plugin without `dist.include` never looks for the
script.

## Bounds accepted

**Whether the portal accepts `dist` before its first push is untested.** The
first release creates the branch before anyone points the directory at it.

**The warnings are a proxy.** A plugin can pass them and still be reviewed, or
trip one and pass.
