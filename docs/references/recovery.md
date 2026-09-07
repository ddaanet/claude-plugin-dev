# Recovery and the pre-flight state checks

What happens when a release lands only partially, and which working-tree state a
pre-flight is right to refuse. The conclusions these arguments support are
listed in [../design.md](../design.md).

## `check-version.sh`: catching a partially-completed release

`release`'s marketplace step (see "Marketplace entry" in
[release-flow.md](release-flow.md)) runs *after* `plugin.json` is bumped,
committed, tagged, pushed, and the GitHub release created. If anything from
`gh release create` onward fails, the plugin is left tagged and pushed at the
new version while `marketplace.json` is still at the old one — invisible to end
users, and nothing in the toolkit previously detected it: the pre-flight in
`release` only compares `plugin.json` against the latest tag, and the
version-guard hook only fires on edits to `plugin.json`, not on marketplace
staleness.

`check-version.sh` closes this by comparing `plugin.json`'s `.version` against
the consumer's entry in `$MARKETPLACE_DIR/.claude-plugin/marketplace.json`. It's
exposed as a `just check-version` recipe and also runs automatically as a
`release` pre-flight step, so a new release refuses to start on top of a drifted
marketplace from a previous incomplete one.

It was originally a gitlore-local script (it motivated the `prerelease` gate in
[release-flow.md](release-flow.md)), hardcoded to gitlore's plugin name and a
`../claude-plugins` sibling path. Absorbed into the toolkit with two fixes: the
plugin name is read from `plugin.json` instead of hardcoded, and the marketplace
path comes from `$MARKETPLACE_DIR` (matching `release.just`'s own convention)
instead of an assumed sibling directory. A missing marketplace entry is treated
as pre-first-publication state (skip), not drift (fail) — consistent with how
`release.just`'s marketplace step treats a missing entry.

## Recovery: `resume-release` and the shared release tail

`check-version.sh` detects a half-landed release but cannot fix one, and the
guard it feeds is deliberately strict: `release` refuses to start on top of
drift. Before `resume-release` nothing satisfied that guard except hand-editing
another repository. `resume-release` is the forward exit.

The last four steps of a release — push the branch, push the tag, create the
GitHub release, bump the marketplace — are one idempotent block that both
`release` and `resume-release` run. Each step probes remote state before acting:
`git ls-remote` for the branch and tag, `gh release view` for the release, and
`ls-remote` again — against the marketplace repo's own origin — for the
marketplace push. Probing the remote directly means the answer is authoritative
without a `git fetch`, so recovery never depends on how stale the local
remote-tracking refs are. A step that finds its work already done says so and
returns; only steps that act set `acted`.

Resume takes its version from `plugin.json` and requires the matching local tag
to already exist. It completes a release; it never starts one. Tagging `HEAD` on
a guess would tag whatever landed since the interrupted release, so a missing
tag is a refusal that points at `just release <bump>` instead. When every step
finds nothing to do, the summary says the release is already complete rather
than claiming to have completed it — that distinction is what makes running it
on a healthy repo safe rather than merely harmless.

A failure *of* the version commit is the one case recovery does not own. A
consumer's `pre-commit` hook can refuse it — gitlore's memory-approval gate is
on every consumer — and at that point nothing is committed or tagged, so there
is no partial release to resume. The manifest rewrite is already staged though,
and left in place it is a dirty tree that `common_preflight` refuses, blocking
`release` and `resume-release` alike on `uncommitted changes` with no mention of
the gate or the leftover. So the commit is guarded and the manifest restored
from HEAD, returning the tree to what the run found: a refused commit means
satisfy the gate and run the same command again, and recovery is not involved.
Only the commit is guarded — a `pre-commit` hook cannot fail `git tag`.

The marketplace commit is guarded the same way, and there the argument is one
step stronger. It is the last step of a release and its only write outside the
plugin repo, so a refusal leaves the version commit, tag, branch push and GitHub
release already public: the release genuinely is partial and `resume-release` is
what finishes it. A bump left staged in `MARKETPLACE_DIR` is precisely what
`common_preflight` reads as an unrelated dirty tree, so the leftover blocks the
one command that would help. The refusal used to print the
`git -C … checkout HEAD -- .claude-plugin/marketplace.json` to run first, which
made the recovery two commands and the first of them mandatory — the same
argument that made the manifest rollback automatic. It is automatic here too:
the tree is restored to the state `common_preflight` had already established was
clean, and the whole printed recovery is `just resume-release`.

A push refused by a consumer's `pre-push` hook is resume's ordinary case, and
the release commit is never amended to chase it. gitlore's hook publishes every
memory store before the parent push and refuses when one diverged, so the
release dies with the commit and tag local and nothing pushed. The tempting
repair — `commit --amend` the release commit so its gitlink names the merged
memory, then `tag -f` — buys nothing. The gitlink a parent commit records is
always an ancestor of memory's `live` or `live` itself, because each merge takes
the pending commit as its second parent, and a push of `live` publishes every
ancestor. So the moment the push succeeds the gitlink is public, whether or not
the tagged commit names the merge. Against that, the amend would force a tag the
script is about to publish and sequence a scripted rewrite behind a human merge
review. `push_branch` re-pushes on resume instead, and says so when it fails:
clear what the hook reported, run `just resume-release`, repeat if refused
again.

A tag that exists on the remote at a *different* sha is an error, never a
force-push. A reused tag means something published under that version already,
and no recovery path should paper over that.

`resume-release` has no `prerelease` dependency, unlike `release`. The code it
completes is already committed, tagged, and in most cases pushed — the gate
already passed once, before the interruption. Re-running it would make recovery
cost whatever the consumer's slowest gate costs, and a consumer with paid checks
would route around the recipe and finish by hand, which is the situation this
exists to end.

The flow moved out of `release.just`'s recipe body into `plugin-dev/release.sh`
to get three things a justfile recipe cannot have: `shellcheck` coverage,
offline end-to-end tests driving real git repos with a stubbed `gh`, and no
just/bash quoting seam — `{{...}}` interpolation inside a shell body is a
recurring source of quoting bugs that no linter sees. `release.just` keeps the
two recipes as one-line wrappers, which is also the whole interface consumers
depend on.

This repo's own self-release recipe stays bespoke. It has the same tail minus
the marketplace step, and it failed in the same window once — `v0.4.1` has a
`VERSION` bump commit and no tag. Resuming it by hand is a tag and a
`gh release create`, which the toolkit's sole maintainer can do;
`resume-release` exists as a convenience for consumers, who are more numerous
and less close to the code. Folding it in would also make the toolkit consume
its own consumer-shaped code, which the "don't run `release.just`'s recipes from
this repo" rule exists to prevent.

## The refusal is where the operational knowledge lives

What to do when a release dies is knowledge that has to arrive at the moment it
dies. Two places could have held it and neither reaches the reader in time. A
ddaanet memory file is readable only from a machine that mounts the tier, and
only when an index line matches the string the failure happened to print — while
the consumer hitting the failure is often a plugin repo with no memory store at
all. A `docs/` page is worse: nothing routes a reader to a document mid-failure,
and the `dist-` tree ships no `docs/`. The script is in every consumer by
construction, so the message is the one channel that cannot be missed, and the
one that cannot drift from the check it guards.

So every refusal on a path where the tree state is non-obvious, or where a
release may already be partly public, states three things: what was checked,
what was exempt from it, and the exact next command. The clean-tree checks print
the offending paths and the exemptions that did not save them; the marketplace
checks say what is already published before naming `just resume-release`; the
first-release and version-drift refusals state the invariant they protect and
give the command that satisfies it.

Two constraints shape the wording. No message offers a way to skip a check — the
same rule the version-guard hook's deny message follows, for the same reason: an
agent reads a named bypass as authorisation to take it. And the exemptions a
message lists are built in the same place as the pathspecs it reports on
(`clean_pathspecs` returns both), so a consumer whose vendored `plugin-dev/`
predates one of the exclusions is never told about an exclusion its own copy
does not make. Its `tree_is_clean` is the authority on what it exempts, and the
message is generated from it rather than written alongside it.

Paths printed from a diff are read NUL-delimited: a spaced path reported as two
words names two files that do not exist. A path containing a newline still
prints across two lines, which no git quoting mode survives `-z` to fix, and the
comment states that bound rather than implying full coverage.

## The clean-tree check excludes the agent's own working state

`common_preflight` refuses to release from a dirty tree, in the plugin repo and
in `MARKETPLACE_DIR` alike. Two paths are exempt, and they are exempt for the
same underlying reason: an agent session moves them between commits by design,
so their being ahead of HEAD is the resting state rather than unfinished work.

### `.claude/`

`.claude/` is the repo's own agent working environment — settings, hooks, and
the task frames the `handoff` and `precompact` skills write. Those skills stage
their frame (`.claude/handoff-task.md`, `.claude/handoff-todo.md`) for whatever
commit lands next, and a release is a commit that lands next; before the
exclusion it was instead a release refused on `error: uncommitted changes`, a
message naming neither the frame nor the skill that left it. The remedy was to
land the frame in a commit of its own first, which is discipline standing in for
a gate.

Nothing under `.claude/` is plugin content. A Claude Code plugin ships
`.claude-plugin/plugin.json` and the component directories beside it; `.claude/`
is what the *maintainer's* sessions read. So a release that does not stop for it
is not skipping over anything the release publishes. What is staged there rides
the release commit, which is what the frame was staged for.

Excluded whole rather than by filename. The set of files written under
`.claude/` is a function of which skills the maintainer runs — the two handoff
frames today, `gitlore-memory-message` and `settings.local.json` alongside them
— and an enumeration in the toolkit would have to track a list it does not own.
The cost of the wider exclusion is that a genuine edit to
`.claude/settings.json` (the version-guard wiring) no longer stops a release. It
stays in the tree either way and reaches no consumer, so the next commit picks
it up.

`.claude-plugin/` shares the excluded prefix and must *not* be exempt — it holds
the manifest whose version the whole release turns on. Git pathspecs match at
the path separator, so `:(exclude).claude` leaves it alone; that is asserted by
a test that dirties the manifest with a frame staged at the same time, rather
than inferred from how the matcher is documented to work.

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
`.gitmodules`, or one carrying no such submodule, gets the `.claude` exclusion
and nothing more.

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
hooks (see "Recovery"). Naming the submodule gitlore installs is weaker than
assuming where it installed it.

### This repo's own release recipe

The self-release recipe in the root `justfile` carries both exclusions as
literal pathspecs — `.claude` and `memory` — rather than repeating
`release.sh`'s `.gitmodules` lookup. It runs against exactly one repo, whose
mount path is known, so discovery would be answering a question that has no
second answer. That is the same reasoning that keeps the recipe bespoke at all
(see "Recovery"): it is not consumer-shaped code and does not have to
generalise.
