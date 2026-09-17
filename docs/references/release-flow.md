# The release flow

What `just release` does, the version it publishes, and the gate it runs behind.
The conclusions these arguments support are listed in
[../design.md](../design.md).

## Manifest version represents the *last released* version

`plugin.json`'s `.version` field reflects whatever was last tagged. The release
recipe bumps from there: `0.1.1 → 0.2.0` etc.

This is the invariant the version-guard hook protects. It's also checked by the
release recipe itself: if `plugin.json` and the newest semver tag disagree,
release aborts with guidance to revert the manual bump. The newest *semver* tag
and not simply the latest tag — `latest_tag` takes the first line of
`release_tags`, which is already filtered, so a `vnext` or a `v1.2` sorting
above the real release can never stand in for one.

The bug that motivated the guard: an agent committed a version bump inside a
feature commit (intending it to land at the next release). The release recipe,
which bumps from current, would have produced the *next* version after that —
silently skipping the intended one. Caught at release time when the recipe's tag
mismatch happened to trigger a check; would have shipped wrong otherwise.

The one state the invariant cannot describe is a plugin that has never been
released — there is no last release for the manifest to hold. See the next
decision.

## First release publishes the manifest version as-is

On a plugin that has never been released, `just release` (no bump argument)
publishes the version `plugin.json` already holds, rather than bumping forward
from it. Passing an explicit bump there is refused, naming the version that
would be published instead.

A plugin arrives at its first release carrying a version somebody chose, and
that version is adopted rather than bumped past. The official Anthropic
`plugin-dev` marketplace plugin — an unrelated project with a near-identical
name — scaffolds new plugins at `0.1.0` through `/plugin-dev:create-plugin`.
Under the bump-from-current rule that first release publishes `0.1.1`, and
`0.1.0` can never be published at all. Every plugin scaffolded there and
released here meets it.

The seed cannot be fixed where it originates. `install.sh` vendors the toolkit
and wires the recipe and hook into an *existing* manifest — it never writes a
version — and the scaffold that does write one belongs to a different project.
So the fix lives on this side.

`resume_preflight` is the other path that accepts the manifest version verbatim,
and a first release can be forced through it by hand-creating the tag and
running `just resume-release`. It exists to recover a release that landed
partially, and requires the tag to already exist precisely so it never invents
one; leaning on it to cut a first release means doing by hand the step it
refuses to guess at.

Detection is by tag alone: a plugin is at its first release exactly when no tag
matching `^v[0-9]+\.[0-9]+\.[0-9]+$` exists, locally or on origin. The
marketplace entry plays no part in that decision.

Detection used to require **both** no `v*` tags and no marketplace entry, on the
argument that either signal alone misreads a real state: a repo whose tags were
lost or never fetched still has its marketplace entry, and republishing over it
would collide with a version already out there. The lost-tags danger is real;
the conjunct was the wrong instrument for it. It only ever protected a lost-tags
repo that *had* an entry — so it covered plugins already published to the
marketplace and left a first-time publisher's lost-tags clone, which has no
entry yet, with no guard at all. That state is reachable: `check-version.sh`
treats a missing entry as ordinary pre-first-publication and skips, so a plugin
can carry real release tags and no entry.

`release_preflight` now probes origin directly whenever the local list is empty,
which addresses the lost-tags case rather than proxying for it: origin's tags
are the release record, any semver tag there refuses, and a listing that could
not be performed refuses too rather than reading silence as "never released".
That is strictly stronger than the conjunct, so the conjunct is gone — and with
it the requirement that a plugin's `marketplace.json` entry be hand-written
before its first release could be detected as one.

The tag test is `git tag --list 'v*'` through the `semver_tags` filter, not
`git describe`. `describe` sees only tags reachable from HEAD, so a release
tagged on a since-abandoned branch would read as no tags at all, and it returns
the nearest tag of any name rather than the newest release. The filter is what
keeps `vnext` and `v1.2` out: both are `v*` tags and neither is a release.

Both listings — `release_tags` locally and `origin_release_tags` over the wire —
carry `--sort=-v:refname`, and it is load-bearing rather than tidy. Every caller
reads the first line as the newest release, while refname order is
lexicographic, where `v1.10.0` precedes `v1.2.3` precedes `v1.9.0`: without the
sort a refusal names a tag that is not the newest as soon as a plugin reaches a
two-digit minor or patch. Newest-first is fixed inside each function rather than
at each call site, so no caller can forget it.

Refusing an explicit bump rather than ignoring it: a patch bump makes no sense
as an initial release, and no other bump makes sense either. A first release has
exactly one outcome, so a typed bump is a statement about a version history that
does not exist. Ignoring the argument would hide that mismatch; the refusal
names the version that will be published, which is the fact the caller needs to
act on.

This is also why `release.just` passes its bump argument through even when
empty, leaving `patch` as a default inside `release.sh`. The recipe signature
cannot distinguish an explicit `patch` from no argument at all, and on a first
release that distinction is the whole decision.

Three other mechanisms were weighed and rejected, the first two of them raised
by the brief that motivated this:

- **Teaching the version-guard hook to allow the edit** when no release exists,
  sharing the predicate with `release_preflight`. It is the only one that lets
  an agent write the version unaided, which is exactly why it goes: what a
  plugin first ships as is the maintainer's call, and a guard that permits the
  edit hands that call to whoever happens to be editing. The guard's *message*
  branches on the same predicate instead, saying the manifest already holds what
  the first release will publish and naming no route to any other version — see
  [version-guard.md](version-guard.md).
- **A first-release version selector**, `just release --initial 0.1.0`, refused
  once any semver tag exists. It is the option that keeps the guard's invariant
  literally true, since version state would then change only through the recipe.
  Rejected because it adds an argument valid exactly once in a plugin's life and
  puts the recipe in the business of *choosing* a version rather than publishing
  the one already chosen. It does not even remove the manual edit: a plugin
  content with its scaffolded version still releases without the flag, so the
  selector is a second way in beside the first rather than a replacement for it.
- **Seeding a baseline tag** — creating `v0.0.0` at install so that "never
  released" is a state that never occurs. It writes a release that did not
  happen into the one namespace both listings treat as the release record, and
  `just release` then bumps from it to `v0.0.1`: the same
  version-nobody-asked-for outcome, moved one step along. It carries the seeding
  objection below as well, helping only plugins installed after the change.

Also rejected: seeding new consumers at `0.0.0` (via `install.sh` or by
documented instruction) so that `0.0.0` reads unambiguously as "nothing
released" and `just release minor` produces `0.1.0`. It keeps the invariant
literally true, but it only helps plugins installed after the change — a plugin
already vendored and sitting unreleased still hits the original conflict, which
is precisely the case that surfaced it. It also puts `install.sh` in the
business of rewriting the very field the version-guard hook exists to protect.

## Marketplace entry: bump if present, create on first publication

The release recipe's marketplace step handles both a plugin that already has a
`marketplace.json` entry and one being published for the first time:

- **Entry present** → rewrite its `.version` to the new version (the original
  behaviour).
- **Entry absent** → append a new entry synthesised from `plugin.json` (`name`,
  `description`, `author`, `repository`/`homepage`, `license`) plus a `github`
  `source` whose `repo` is derived from the plugin's `origin` remote
  (owner/repo, parsed from either the SSH or HTTPS URL).

Originally the recipe treated a missing entry as a fatal pre-flight error
(`no entry for '<name>'`). That made the *first* release of any plugin
impossible through the recipe — the maintainer had to hand-edit
`marketplace.json` first, then release. Since the recipe's whole premise is that
"a tag without a marketplace bump is invisible to end users," first publication
is exactly when the marketplace touch matters most. Creating the entry from the
manifest closes that gap: one `just release` publishes a brand-new plugin end to
end.

`source` is the one field not present in `plugin.json`, so it's derived from
`origin` rather than the manifest. The recipe only targets single-plugin
GitHub-hosted repos (the consumer-plugin model), so a `github` source with an
owner/repo slug is always correct here; the monorepo `git-subdir` sources (e.g.
the skills bundle) are out of scope and hand-maintained. The `origin`-remote
requirement for new plugins is validated in the pre-flight block, before any
destructive op.

The commit is idempotent. When the rewrite produces no change — the entry was
pre-added at exactly the version being released — `git commit` would exit
non-zero under `set -e` and abort the recipe *after* the irreversible
commit/tag/push/`gh release create` had already run, leaving the maintainer
staring at `exit code 1` on a release that actually succeeded. The step checks
`git diff --cached --quiet` and skips the commit when nothing changed.

That check answers "should I commit?" and *only* that. Whether to push is a
separate question with a separate probe: the marketplace repo's own `HEAD`
against its own `origin`, via `ls-remote` on its own branch. The two were once
one check, which meant a marketplace commit whose push was rejected could never
be recovered — the next run found nothing staged, skipped the push along with
the commit, and reported the release complete. Idempotence has to be measured
against the remote, not against the working tree, or a recovery tool reports
success on the state it exists to repair.

## No interactive confirmation in `release`

The `release` recipe runs non-interactively. It does not prompt
`Release X? [y/N]` before committing/tagging/pushing, and there is no `--yes`
argument.

An earlier version prompted with `read -rp` and offered `--yes` as a skip. Both
were removed: `release` always executes behind Claude Code's permission layer
(or a human's own `just` invocation), which already gates the command. The inner
prompt re-asked the same question, and `--yes` existed only to silence it in the
common case where an outer gate was present — i.e. almost always. Dropping both
collapses a double-confirmation into the single gate that matters.

Safety is unchanged: the pre-flight guards (dirty tree, wrong branch,
manifest/tag desync, marketplace pre-flight) still abort before any destructive
op. Only the interactive keystroke was removed.

The same applies to this repo's own self-release recipe (the `release` in the
local `justfile`): it too dropped its `read -rp` prompt and `--yes` for the
identical reason.

## Recipe naming: `precommit`, not `validate`

The consumer-defined commit gate is called `precommit`. `validate` was
considered but rejected:

- `validate` isn't an established convention — it shows up mostly in
  schema-validation contexts (k8s, terraform), not "the gate before a
  commit/release."
- `precommit` names the *moment* it should fire, matches the pre-commit
  ecosystem's vocabulary, and is already used in adjacent projects (e.g.
  `edify`).
- `release` reaching `precommit` reads naturally: "the same gates that pass for
  a commit must pass for a release."

That last point was an argument about what to *name* the commit gate, and it
predates a consumer whose release gate is bigger than its commit gate. It is not
an argument for `precommit` being the recipe `release` binds to — `release` now
depends on `prerelease` (next section), which for most consumers is exactly
`prerelease: precommit`.

## Release gate: `release` depends on `prerelease`

`release` depends on a consumer-defined `prerelease` recipe, not on `precommit`.
Consumers define both; the usual body is one line:

```just
prerelease: precommit
```

A consumer whose release gate is larger widens it there:

```just
prerelease: precommit evals
```

The motivating consumer is `gitlore`, which has a fast `precommit`
(check-version, lint, test) and a slow, paid `evals` gate that drives the real
`claude` CLI. With `release` hardcoded to `precommit`, `just release` shipped
without ever running the evals; the workaround — remembering to type
`just prerelease release` — is discipline, not a gate. A release recipe that can
be satisfied by remembering something is not a gate.

Rejected alternatives:

- **A private `_release-gate: precommit` in `release.just`, overridden in the
  consumer's justfile.** Non-breaking, and the shape most of the design pressure
  initially pointed at. Rejected because overriding an imported recipe requires
  `set allow-duplicate-recipes := true`, which the toolkit would have to declare
  on the consumer's behalf — a repo-wide setting that silently turns the
  consumer's *accidental* duplicate recipes from an error into
  last-definition-wins. Trading a global safety check for one override point is
  a bad exchange, and the backward compatibility it buys isn't needed: consumers
  update their justfile as part of `update-plugin-dev` anyway.
- **`just "$gate"` as the recipe's first shell line**, with an overridable
  `release_gate := "precommit"` variable. Non-breaking, but the gate vanishes
  from just's dependency graph and `--list`, and failures surface through a
  nested `just` invocation. Also inconsistent: every other precondition in
  `release` is a real dependency or a pre-flight check.
- **Taking the recipe name from a variable** (`release: {{gate}}`) — just does
  not support recipe names from variables in a dependency list.

This is a **breaking change**: a consumer that pulls the new toolkit without
adding `prerelease` gets
`error: Recipe release has unknown dependency prerelease`. That error is a
whole-justfile compile error, so *every* recipe fails, `just precommit` included
— not just `release`. The blast radius is deliberate and, on reflection, the
better failure mode: it fires at update time, when the maintainer is already in
the justfile, and names the exact missing recipe. The alternative — a `release`
that quietly runs a narrower gate than intended — is the bug this section exists
to fix.

Locked in by `_import-check`, which builds three stub consumers — plain
(`prerelease: precommit`), widened (`prerelease: precommit evals`), and one with
`prerelease` missing — and asserts via `--dry-run` that `release` resolves to
the right gate chain in the first two and that the third fails with an error
naming `prerelease`. Verified against just 1.46.0.

## Default branch detection via `origin/HEAD`

The release recipe doesn't hardcode `main` — it reads the default branch from
`git symbolic-ref --short refs/remotes/origin/HEAD` and falls back to `"main"`
if unset. Lets the recipe work on `master`, `trunk`, fork-default branches,
etc., with no behaviour change in the common case.

`symbolic-ref` rather than `rev-parse --abbrev-ref` because the latter exits
non-zero *and* prints `"origin/HEAD"` to stdout when the ref is unset. Combined
with `pipefail` and a `|| echo "main"` fallback, the substitution captured both,
producing a two-line `main_branch` and the nonsensical error "must be on HEAD
(currently main)". `symbolic-ref` is silent on stdout when the ref is unset, so
the fallback fires cleanly.
