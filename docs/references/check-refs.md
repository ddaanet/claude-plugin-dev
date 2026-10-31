# The reference check

Why `check-refs.sh` runs at commit time, what it counts as a reference, why it
reads the disk, what it exempts, and how the shipped half meets the dist build.
The dist tree it guards is argued in [dist-branch.md](dist-branch.md); the gate
cache whose fingerprint it has to match is in [gates.md](gates.md). The
conclusions these arguments support are listed in
[../design.md](../design.md).

## Why at commit time

A Markdown link breaks the day its target is renamed or deleted, in a commit
that touches the target and not the link. Caught at release, the break is days
old and the commit that caused it is buried; caught in `precommit`, it is the
commit being made. So the check is a script a consumer's commit gate runs, and
the dist build runs its shipped half once more on the tree it is about to
publish, which is the one moment the tree that users install exists.

## What counts as a reference

An inline link or image, bracketed text followed by a target in parentheses, and
a reference definition, `[label]: target`, with a relative target. A scheme
(`https:`, `mailto:`), a pure `#anchor`, a root `/path`, a footnote, escaped
`\[brackets\]` and anything in a fenced block, an inline code span or an HTML
comment are not references. A run of three backticks with another backtick after
it on the line is a code span, not a fence, as CommonMark has it. The
`#fragment` is dropped before the lookup; `<angle brackets>`, a trailing title
and `%XX` escapes are read as CommonMark reads them, so a target with a space
resolves. The target is resolved from the containing file's directory, the
convention every consumer's links already follow.

A backticked path is deliberately not a reference. A survey of the consumer
repos found backticked paths in shipped files naming the reader's own project
files, teaching examples and files removed on purpose as often as live paths,
and no shape that separates a reference from a mention. Checking them would
refuse correct prose; a link is the one form whose author asked for a lookup.

The parser is a line scanner in POSIX awk, run under `LC_ALL=C` so a `%XX`
escape decodes to its byte. Its bounds are listed in
[limitations.md](limitations.md).

## Why the disk, and which files

The files read are `git ls-files -co --exclude-standard`, filtered to Markdown
and to regular files on disk, and read from disk. A gate cached by the sentinels
in [gates.md](gates.md) fingerprints the working tree, untracked files included;
a check that read the index would record a pass for a tree it never looked at,
and an untracked draft with a broken link would cache green. Tracked-but-deleted
files and gitlinks fail the regular-file test and drop out. `plugin-dev/` is
skipped, being vendored, though a link into it still resolves.

The same listing decides whether a target exists: a path git lists that is on
disk, a directory holding one, the root, or a path inside a listed submodule
that is on disk. A file test (`-e`) would accept an ignored file, which can
never ship or reach a clone, and on a case-insensitive disk a case-folded
target, which is dead on GitHub and on every Linux clone; the listing is exact
and leaves ignored files out. An ignored target is refused as "is ignored by
git". Untracked files are in the listing, so a link to a file the author has not
yet added passes, and the gate still reads the disk rather than the index. A
target that normalises above the root is refused as "leaves the repository": it
resolves only where the author's checkout happens to have a neighbour.

The listing takes no pathspec. `dist.sh` exports `GIT_LITERAL_PATHSPECS`, and a
glob pathspec under it would match nothing and pass every tree; the filter is in
the shell loop instead.

## Exemptions

A dated changelog record and a plan are frozen: a link in one to a file deleted
later is true about the day it was written. A plan never resolves its links
either, and `plans/` is a scope rule like `plugin-dev/`: the scan never reads
it, whatever `refs.exempt` says, exactly as `check-size` skips it always. One
rule for both checks, in `exempt-list.sh`, beats a default one of them lets a
consumer undo; no vendoring repo had a `refs.exempt` when it was made. The
resolve check also skips `docs/changelog/` by default. A repo whose frozen
records live elsewhere lists its own prefixes in a root `refs.exempt`, one per
line with `#` comments and an optional ` # reason`, and the file replaces that
default rather than adding to it, so an empty one exempts nothing. The list is
read by the reader `check-size` uses for `size.exempt` (blanks trimmed, CR
stripped, a trailing `/` dropped); `dist.sh`'s `dist.include` reader stays its
own, being a strict allowlist whose refusals are its contract. A prefix matches
whole path components, the same rule `dist.include` uses.

## Shipped stays shipped

The dist tree holds only the listed paths, so a link from a shipped file to an
unshipped one dangles in what users install, though it resolves in the repo.
With a `dist.include`, a reference from a shipped file must reach a shipped file
that exists. No exemption applies: a frozen record that ships still ships its
dead link. A target outside the set is refused as "is not shipped", a missing
one as "does not exist", once either way. The root counts as shipped, since it
holds every shipped path.

The shipped set is read through `dist.sh paths`, the parser the release and the
dogfood copy already use; a malformed list is refused in `dist.sh`'s own words.
`--shipped <path>...` replaces the set, for a repo whose shipped tree is not
described by a `dist.include`: this repo passes `--shipped toolkit`.

At release, `dist.sh tree` runs `check-refs.sh --tree` on the tree it built.
There every file is shipped, so the check reduces to "resolves inside the tree",
and it reads blobs and paths from the object store: the release commit is what
ships, and `dist.sh` builds from it, never from the worktree. Each line the
check refuses with becomes one `dist:` line.

The two runs agree but for one case, by design: a shipped file's link to an
untracked file passes `precommit` and refuses the release until the file is
committed. Requiring targets to be tracked at commit time would refuse a link
written before its target is `git add`ed, on every precommit in between; the
release is the first moment the difference matters, and it says which link.

## Wired by the consumer

`release.just` gains a one-line `check-refs` recipe, like `check-version`, and
nothing it defines depends on it: the toolkit does not add checks to a
consumer's gates. A plugin adds `precommit: check-refs`. As a dependency it runs
ahead of the recipe body on every call, which is where `gates.md` puts a check
over files a gate's pathspecs leave out. The cost lands on consumers whose
shipped files already link out of their set, typically a README into an unlisted
`docs/` or a shipped changelog into `plans/`: their next release refuses until
the target is listed or the link goes. The migration note says so.
