# The clean-tree check

Why `common_preflight` exempts only the memory gitlink from its dirty-tree
refusal, split out of [recovery.md](recovery.md), which holds the other
pre-flight state checks. The conclusions these arguments support are listed in
[../design.md](../design.md).

## The clean-tree check exempts only the memory gitlink

`common_preflight` refuses to release from a dirty tree, in the plugin repo and
in `MARKETPLACE_DIR` alike. One path is exempt: the gitlore memory submodule. An
agent session moves it between commits by design, so its being ahead of HEAD is
the resting state rather than unfinished work. It applies to this repo's own
release too, where it is a literal pathspec rather than a `.gitmodules` lookup —
see [self-release.md](self-release.md).

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
until it is committed. A dirty `TASK.md` or `TODO.md` refuses too, with no
replacement exemption: the routine flow is handoff, commit, release. Untracked
and gitignored files under `.claude/` (`settings.local.json`,
`gitlore-memory-message`) never appeared in `git diff HEAD` and are unaffected.

The refusal prints its "exempt from this check" list only when an exemption
applies, so a repo with no memory submodule is told nothing about exemptions it
does not have. No note says `.claude-plugin/` is not exempt: that note
disambiguated it from the `.claude` pathspec, and with no such pathspec a dirty
manifest refuses as any other tracked file does.

### The gitlore memory submodule

A gitlore-mounted memory store makes the check wrong as stated: the store is a
submodule whose checked-out HEAD moves whenever a session writes a fact, and the
parent's gitlink is folded forward by gitlore's own `pre-commit` hook on the
*next* commit, not immediately. Between commits the moved gitlink is the resting
state, not uncommitted work, and every consumer mounts one — so an unqualified
check refuses every release.

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

This is the toolkit's most specific coupling to gitlore, but not a new one — the
release tail is already written around gitlore's `pre-commit` and `pre-push`
hooks (see "Recovery" in [recovery.md](recovery.md)). Naming the submodule
gitlore installs is weaker than assuming where it installed it.
