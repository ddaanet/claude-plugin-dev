# The clean-tree check

Why `common_preflight` exempts the memory gitlink, and in the plugin repo the
handoff files, from its dirty-tree refusal and nothing else, and why `update.sh`
and `install.sh` leave that gitlink pending, split out of
[recovery.md](recovery.md), which holds the other pre-flight state checks. The
conclusions these arguments support are listed in
[../design.md](../design.md).

## The clean-tree check exempts the memory gitlink and the handoff files

`common_preflight` refuses to release from a dirty tree, in the plugin repo and
in `MARKETPLACE_DIR` alike. One path is exempt in both: the gitlore memory
submodule. An agent session moves it between commits by design, so its being
ahead of HEAD is the resting state rather than unfinished work. It applies to
this repo's own release too, where it is a literal pathspec rather than a
`.gitmodules` lookup — see [self-release.md](self-release.md). The plugin repo
also exempts its root `TASK.md` and `TODO.md`, which the release commit takes
(see "The release commit takes the handoff files" below), and so does this
repo's own release.

### `.claude/` is not exempt

A tracked file under `.claude/` that differs from HEAD refuses a release, and
the refusal names it. The one reason to exempt the directory was the task frames
the `handoff` and `precompact` skills staged there for whatever commit lands
next: a release is a commit that lands next, and a staged frame read as
uncommitted work, refusing on `error: uncommitted changes` and naming neither
the frame nor the skill. That reason no longer holds. The frames are `TASK.md`
and `TODO.md` at the repo root, ordinary tracked files that no hook
force-stages.

Why the exemption is removed rather than narrowed. The case for exempting the
directory whole was that the set of files written under `.claude/` is a function
of which skills the maintainer runs, so an enumeration in the toolkit would
track a list it does not own. That argument still holds; it is overridden, not
answered. With the staged frames gone, the exemption's remaining effect is that
an edit to a tracked file under `.claude/` rides the release commit without the
refusal naming it, and the maintainer has decided to accept the refusal its
removal brings back.

What it costs, accepted. An uncommitted edit to a tracked
`.claude/settings.json` (the version-guard wiring) or to
`.claude/gitlore-hook-setup` (gitlore's tracked install state) stops a release
until it is committed. Untracked and gitignored files under `.claude/`
(`settings.local.json`, `gitlore-memory-message`) never appeared in
`git diff HEAD` and are unaffected.

The refusal prints its "exempt from this check" list only when an exemption
applies, so the marketplace repo with no memory submodule is told nothing about
exemptions it does not have; the plugin repo's list always names the handoff
files. No note says `.claude-plugin/` is not exempt: that note disambiguated it
from the `.claude` pathspec, and with no such pathspec a dirty manifest refuses
as any other tracked file does.

### The gitlore memory submodule

A gitlore-mounted memory store makes the check wrong as stated: the store is a
submodule whose checked-out HEAD moves whenever a session writes a fact, and the
parent's gitlink is recorded by the *next* parent commit, not immediately:
gitlore's `gitlore-commit` stages the moved gitlink into the parent index after
a memory commit, and the parent commit that follows takes it. Between commits
the moved gitlink is the resting state, not uncommitted work, and every consumer
mounts one — so an unqualified check refuses every release.

The path is read from the repo's `.gitmodules`, keyed on the submodule name
`gitlore-memory`, and excluded by pathspec. It was originally the literal
`memory`, which is only gitlore's *default* mount point — the path is an
argument to gitlore's `install.sh`. A consumer that mounted the store elsewhere
got `uncommitted changes` on every release, with nothing in the message to point
at why.

Keyed on the name rather than the url because git absolutises a relative url on
the way into `.git/config`, so a url comparison is only reliable against
`.gitmodules` itself — and if `.gitmodules` is the file being read either way,
the name is the simpler key. It is also the stable one: gitlore fixes the name,
the user picks the path. `git config --get` returns a single key's value whole,
so a mount path containing spaces needs no `-z` splitting. A repo with no
`.gitmodules`, or one carrying no such submodule, gets no exclusion at all.

The narrowness is the point. `git diff --ignore-submodules=all` would drop the
`.gitmodules` read entirely for a two-line diff, but it exempts *every*
submodule: a consumer that vendors a code submodule and forgets to commit its
moved gitlink would release without being told. No consumer carries one today,
which is exactly what would make that regression invisible until one does. The
exemption is for the one submodule whose floating gitlink the toolkit knows to
be by design, and a submodule mounted at `memory` under some other name is not
that submodule.

The check runs `git diff --ignore-submodules=untracked`, here and in
`install.sh`'s guard, as `update.sh`'s dirt check does. A consumer may set
`submodule.<name>.ignore = all` or `diff.ignoreSubmodules` on a code submodule,
and a plain `git diff --quiet HEAD` honours it: the release would gate the
submodule's new content but commit and tag the old gitlink, shipping something
other than what was gated. The flag overrides the config, so a moved gitlink
refuses under any ignore setting, and so does modified content inside the
submodule. Untracked files inside a submodule pass, as untracked files in the
parent do: the check never refused those, and no commit of the parent could
carry them. The dirty-path report passes the same flag, so a refusal names the
moved path.

The check compares the index to HEAD as well as the worktree, with the same
pathspecs and flag, as `update.sh`'s dirt check does. A worktree diff alone
passes a path staged ahead of HEAD whose worktree was put back — a submodule
gitlink staged and then its checkout reverted, or a file staged and then
restored — and the release commit, which commits the index, would carry it
ungated. The report lists the union of both diffs, each path once.

This is the toolkit's most specific coupling to gitlore, but not a new one — the
release tail is already written around gitlore's `pre-push` hook (see "Recovery"
in [recovery.md](recovery.md)). Naming the submodule gitlore installs is weaker
than assuming where it installed it.

### The release commit takes the handoff files

`TASK.md` and `TODO.md` at the plugin root are the task frame a `/clear` or
`/compact` resumes from. They are bookkeeping, which never takes a commit of its
own: it is amended into the previous commit while that is unpushed, or rides the
next commit it belongs to. A release blocks both routes. Without the exemption,
a frame written before it, recording the post-release state, refuses the release
as uncommitted work; one written after it finds the release commit already
pushed, so it cannot be amended and stays dirty until an unrelated commit comes
along.

So the plugin repo's check excludes both as literal pathspecs, the refusal's
exemption list names them, and `bump_commit_tag` stages them into the release
commit beside the manifest as they are on disk: a file present is committed with
its content, one absent as deleted, whatever the index held. A staged blob the
worktree has since put back, a `git rm`, a `git rm --cached` of a tracked file
that is now ignored: each is committed as the disk has it, since a commit of the
index would publish a blob that is on no disk. The list is the union of
`git diff -z --name-only HEAD`, the same with `--cached`, and
`git ls-files -z -o --exclude-standard` over the two paths, and
`git update-index --add --remove` stages it, which takes a path absent from both
disk and index where `git add` fails. An untracked, ignored frame is the
consumer's choice and stays out; a frame written after the release that deleted
it is new again, and rides it. An unmerged one is refused in the pre-flight with
its name, because staging it from disk marks it resolved and would commit its
conflict markers.

A failure while staging them, or a commit the consumer's gate refuses, goes
through one rollback: the manifest is restored from HEAD and the handoff paths
are unstaged back to HEAD, whatever was staged in them before the run, their
content on disk untouched. A file left unstaged before the run is unstaged after
it and does not ride the commit that fixes the gate; the re-run takes them. A
first release makes no commit and `--resume` makes none either, so neither
carries them; a dirty frame then waits for the next commit, as it would without
the exemption.

The marketplace repo keeps refusing them. No commit there would take them, so an
exemption would only let them stay dirty past a release.

The paths are hardcoded, as the memory submodule's name is: they are the files
the handoff skills write, and a configurable list would be a knob for a set of
two. A file that is not a handoff frame but happens to be named `TASK.md` or
`TODO.md` at the root rides the release commit unnamed; that is the cost.

## `update-plugin-dev` leaves the memory pointer pending

`update.sh` cannot exempt the gitlink the way the release preflight does:
`git subtree` runs its own unscoped `git diff-index HEAD` and refuses any
tracked change, with no flag to scope it. Refusing as well would stop every
update in a consumer whose session has written a fact since its last commit,
which is the resting state. So the pull runs as
`git -c submodule.gitlore-memory.ignore=all subtree pull ...`: the setting makes
`git diff-index` skip that one submodule, `git subtree`'s clean-tree check
passes, and the pointer stays pending for the consumer's next commit, which
takes it anyway. The update commits nothing and moves nothing outside
`plugin-dev/`.

The setting hides a *staged* pointer from the check, though, and the merge
commit `git subtree` then makes would record it. Gitlore's `gitlore-commit`
stages the moved gitlink after every memory commit, so staged is the usual
state. When the gitlink is staged, the update records the staged sha, unstages
it before the pull, and restores exactly that staged entry afterwards from an
`EXIT` trap, so a failed pull leaves it staged too. The pointer ends as it
began, staged or not. The one exception is a pull stopped on a merge conflict:
restaging then would put the pointer into the commit that finishes the merge, so
the update prints the exact `git update-index` command that restores it instead,
to run once the merge is committed. The staged-pointer check passes
`--ignore-submodules=none`, so a consumer whose own config ignores the store
still has its staged pointer found.

The memory checkout is left exactly as it was, whatever its state: ahead of the
recorded commit, behind it, diverged from it, staged, or with dirt inside it.
The setting hides the submodule from the check whole, so none of those shapes
needs a decision from the update, and none is the update's to make: only the
human knows which side of a diverged store holds the facts.

The exemption is scoped by name, as the release preflight's is. Every other
tracked change refuses before the pull, in the worktree or in the index; a
change staged and then reverted in the worktree still counts, since
`git diff-index` compares HEAD with the index as well. A moved gitlink of a
submodule under any other name refuses too. The update's own dirt check runs
with `--ignore-submodules=untracked` and exempts the store by its path, so a
consumer's `diff.ignoreSubmodules` or `submodule.<name>.ignore` setting does not
hide a code submodule's unrecorded move or a change inside it, staged or not:
the update refuses on the tree as it is, not as the consumer's config shows it,
and its refusal lists what is dirty and says a change inside a submodule is
committed or stashed there. Untracked files inside a submodule pass, since no
merge in the parent can touch them. The `ignore=all` key is passed to the pull
alone, set for `gitlore-memory` alone.

Rejected: letting a staged pointer ride the subtree merge commit. The update
would then commit outside `plugin-dev/`, a pointer change under a message about
the toolkit.

Rejected: committing the pointer before the pull. It needs history rewriting for
a pointer the next commit takes anyway: an amend, which is safe only when no
other ref holds HEAD, or a pointer commit folded into the subtree merge by
rebuilding the merge on the pre-pointer parent. It would also run the consumer's
commit hooks, its gate included, for a commit nobody asked for. Rejected too:
moving a checkout that is behind the recorded commit up to it. That is a write
outside `plugin-dev/` for a state the human may have left on purpose.

## `install.sh` leaves the memory pointer pending too

A plugin repo that mounted its gitlore store before vendoring the toolkit has
the same resting state at install time: a memory commit moves the pointer ahead
of HEAD, and a guard with no exemption would refuse the first install on it.
`install.sh` therefore carries the same exemption as `update.sh`, as a copy
rather than a call, since the bootstrap script runs before any sibling file is
vendored: the path `.gitmodules` gives the submodule named `gitlore-memory`,
excluded as a literal pathspec, under `--ignore-submodules=untracked`, with the
index compared to HEAD as well as the worktree. Every other tracked change
refuses, a moved gitlink under another name included.

`git subtree add` runs the same unscoped clean check as `subtree pull`, so it
runs under `-c submodule.gitlore-memory.ignore=all`, and the commit it makes
takes the whole index, so a staged pointer is unstaged for the add and restored
from an `EXIT` trap, as the update does. An add into a new prefix cannot stop on
a merge conflict, so the restore is unconditional and the update's printed
command has no counterpart here.
