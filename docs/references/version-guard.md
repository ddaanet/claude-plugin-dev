# The version-guard hook

Why the hook that refuses agent edits to the manifest version is shaped the way
it is. The conclusion this argument supports is listed in
[../design.md](../design.md).

## Dual-channel hook output

`version-guard.sh` emits two distinct fields when denying an edit:

- `permissionDecisionReason` — verbose, agent-facing. Names the legitimate path
  (`just release …`), forbids workarounds, no escape hatches the agent can
  self-authorise.
- `systemMessage` — one short line, human-facing. Surfaces *that* a block
  happened, not *why* in detail.

This split exists because agents read instructions literally. A diagnostic
message intended for human eyes that says "if you really need to bypass this,
run X" gets parsed as a green light to run X. The agent channel is therefore
worded as unconditional refusal with redirect; the human channel is curt and
informative.

Both fields ride **stdout with exit 0**, which is the only way either is
delivered: Claude Code parses a hook's stdout as JSON, and only on exit 0. A
`permissionDecision` of `deny` there blocks the call exactly as `exit 2` does,
so nothing is lost by not exiting 2 — whereas on exit 2 the JSON is handed to
the model as raw stderr text, and `systemMessage` never reaches the human at
all.

## The deny message branches on whether the plugin has ever released

The steady-state wording is false on a plugin that has never released. It opens
"The manifest version is the last released version" — there is no last released
version — and sends the reader to `just release {patch|minor|major}`, which a
first release refuses on sight. An agent that follows it literally either
publishes whatever version the scaffold seeded or stalls with nothing it is
permitted to do. Both were observed while cutting a consumer's first release.

So the reason names the state it found. With no `vX.Y.Z` tag it says the plugin
has never been released, that the manifest holds `$current`, that `$current` is
what the initial release will publish verbatim, and that which version a plugin
first ships as is the maintainer's call and their edit to make. The predicate is
the one `release_preflight` uses — no tag matching `^v[0-9]+\.[0-9]+\.[0-9]+$` —
so the hook and the recipe cannot disagree about which state a repo is in. See
"First release publishes the manifest version as-is" in
[release-flow.md](release-flow.md).

The filter is duplicated rather than shared. `release.sh` runs its flow at top
level and is not written to be sourced, and a shared helper for one anchored
`grep -E` would mean a new file in the `dist-` tree — a shipped path in every
consumer — to spare a line of duplication. The two copies are held in step by a
single fixture tag set, `vnext` / `v1.2` / `v1.2.3`, exercised by both suites.

The initial-release branch keeps the no-bypass sentence the steady-state one
carries and offers no escape hatch. Nothing about a plugin being unreleased
makes the guard more negotiable; it only makes the redirect different.

### It names no route to the proposed version

The branch states what the manifest already holds and stops. It offers no
recipe, no flag and no command as a way to reach `$proposed`, which after the
opening `$current -> $proposed` line does not appear in the message again. A
message that says "to publish 9.9.9, do X" is an instruction to publish 9.9.9,
and the reason this branch exists at all is that choosing the first version is
not the agent's decision. The steady-state wording can name its recipe because
there the recipe computes the next version from the manifest and nobody is
choosing anything; here any named route is a route to a version an agent picked.

That is a property of the prose rather than of the decision, so it is asserted
as one: a test greps the reason for `$proposed` past its first line.

### Only the agent channel branches

`systemMessage` is byte-identical in both states. It reports *that* a block
happened, to a human looking at the repository it happened in; which state that
repository is in changes nothing about the one line, and branching would be a
second human string to keep in step for a reader who does not need the
difference. A test compares the two directly — tagless fixture against a
`v1.2.3` one, same payload.

### The listing can never turn a deny into an allow

Everything that picks the wording runs *after* the deny is established, and a
`PreToolUse` hook exiting non-zero for any status but 2 is a non-blocking error:
Claude Code reports it and the refused tool call proceeds. A hook that dies
while composing its message therefore allows the edit it had already refused — a
silent, total bypass, and the failure mode a correct-looking script reaches
first.

That inverts the usual rule about statuses. Elsewhere in the toolkit an unread
status is the bug; past the deny, an *un-absorbed* one is. Absorbing fails
closed — the worst outcome is the wrong wording on a refusal that still refuses
— while propagating fails open. So the listing is read as an `if` condition and
the filter's status is bound to its own capture with `||`, both places where
errexit is suspended, and every outcome becomes a plain variable: listing
failure, filter no-match, and any other filter status alike. Neither uses a
pipe, which sidesteps `pipefail` instead of reasoning through it.

An earlier shape read `$?` as the first statement of an errexit-live branch
body. Measured: inserting a single line above that read both clobbered the
status and exited the hook non-2 with no stdout, which is the bypass above. The
`||` form leaves no `$?` for a later edit to displace.

A failed listing is still not an empty one. The two take opposite wordings, so
folding failure into emptiness answers "never released" for a listing that said
nothing — and that is the permissive answer, telling an agent the maintainer is
free to choose a first version for a plugin that may already be published.
"Don't know" takes the steady-state wording: restrictive, and what the hook did
before this branch existed, so the pre-existing non-repo scenarios stay valid
unchanged. A third wording true in both states was weighed and rejected — never
false, but a third message to write, test and keep in step for a path that fires
only when git is missing or the project is not a repository.

`2>/dev/null` on the listing follows from the same case: a `CLAUDE_PROJECT_DIR`
that is not a repository is the ordinary pre-release state, so git's "not a git
repository" is an expected outcome here and not a diagnostic. The hook is silent
on stderr whatever it decides, and the suite asserts that against a non-repo
project directory.

Repo-local `GIT_*` variables are cleared first. A `claude` started from inside a
git hook inherits `GIT_DIR`, which overrides the `-C` and points the listing at
whatever repository the enclosing git invocation was using — measured: `GIT_DIR`
alone does this, `GIT_WORK_TREE` and `GIT_COMMON_DIR` do not. The list is
hardcoded rather than discovered via `unset $(git rev-parse --local-env-vars)`,
because that discovery call is itself a git invocation: it fails alongside a
genuinely absent or broken git and so clears nothing in exactly the runs where
the listing is least trustworthy. A future git adding another such variable is a
gap here, but a visible one.

One bound is accepted and stated rather than closed: a `CLAUDE_PROJECT_DIR` that
is not itself a repository but sits inside one lists the enclosing repository's
tags. That changes which wording the refusal carries, never the refusal.

## Locating the manifest

The hook locates the manifest from `CLAUDE_PROJECT_DIR`, never from the
payload's `cwd`. `cwd` tracks the Bash tool's persistent shell and moves with a
`cd` or an /add-dir; a manifest looked up under a drifted cwd is simply not
there, and the hook's own "not my file" path then exits 0. That is a silent,
total bypass of the guard, so there is no fallback to `cwd`. Comparing that path
against `tool_input.file_path` is done by absolutising both in shell rather than
with `realpath -m`, which is GNU-only: on macOS both substitutions come back
empty, the comparison succeeds, and the guard inverts into firing on every file
written. The manifest path is constructed rather than supplied, so symlink
resolution buys nothing that string comparison does not.

## Reading the proposed version

The Edit branch applies the edit to the manifest text and re-reads `.version`
from the result. Pattern-matching `new_string` for a `"version"` key was the
obvious cheaper route and is wrong: the shortest edit that bumps the version
replaces the value alone (`1.2.3` → `9.9.9`), carries no key to match, and is
the form an agent reaches for first. The substitution runs through jq's
`split/1`, which splits on a literal string, because JSON punctuation in
`old_string` would be read as a glob by a bash `${text/pat/rep}`. The Write
branch stays a plain jq read of `tool_input.content`, which is already the full
file.
