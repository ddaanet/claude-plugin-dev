# 2026-09-17 — Refusals that end in an act, and a bound the wording implied away

Three changes agreed after the first-release work landed, each found by reading
the refusals that work left in place rather than the code paths it changed.

## An unreadable marketplace.json no longer reads as an absent entry

`common_preflight`'s entry lookup used a two-branch `if` on `jq -e`. Measured
against jq 1.7, a clean no-match exits 1 and a parse error exits 5, and the `if`
read both as "this plugin has no marketplace entry yet".

In `release` mode that was masked: `check-version.sh` meets the same malformed
file downstream and refuses, with a misleading "version drift" message but
before anything is public. In `--resume` mode it was not masked at all.
`release_preflight` never runs on resume, so nothing reads the file again until
`bump_marketplace` — by which point `push_branch`, `push_tag` and
`create_github_release` have all run, and the GitHub release is public. The run
then died with jq's raw parse diagnostic rather than a `die`.

The fix splits the two statuses with an `elif`, mirroring the idiom already used
for the push-route keys in the same function, and refuses with
`could not read <path> — nothing was done` before either mode acts. This was the
last site of a family Phase 1 fixed five times, and the only remaining one whose
consequence was reached after publication.

## The version-drift refusal offers one remedy, because one works

It offered two more, and both were dead on every path that reaches it.

`git checkout HEAD -- <manifest>` is always a no-op there: `common_preflight`
refuses a dirty tree before `release_preflight` runs, and `clean_pathspecs`
exempts only `.claude/` and the gitlore submodule, never `.claude-plugin/`. So
the hand-written bump this refusal is about has always been committed already,
and reverting it takes a new commit.

`git fetch --tags` can never have anything left to fetch: `latest_tag` is read
from the local semver tags, and the lost-tags probe above has already
established that local and origin agree on the newest one. That one was worse
than useless — the probe's own hint is what sends an operator to fetch, so this
refusal handed back the command they had just run and the two closed a loop.

What replaces them is the act that works: set `.version` back to the last
released version, commit that edit, then re-run with the bump that produces the
version you want. The general lesson is that a refusal's remedy is a claim about
the state the refusal fires in, and is worth checking against that state rather
than against the situation that motivated writing it.

## `url.<base>.pushInsteadOf` is a stated bound

The diverged-push-route refusal checks three keys, and its wording implied it
covered "the push route". It does not. With `url.<base>.pushInsteadOf` set and
none of the three keys, `git push origin main` lands in the rewritten repository
while `git ls-remote origin` still reads the original — exactly the split the
check exists to prevent.

It stays unchecked, and the reason is that "refuse when set" does not carry
over. The rewrite fires only when its base prefixes origin's URL; a non-matching
base is inert (measured), and a global `insteadOf`/`pushInsteadOf` rewrite is an
ordinary thing to have configured. The three keys the check does read are
repo-scoped, where being set at all is already the anomaly — which is what makes
refusing on presence honest for them and not for this. Deciding whether a given
base matches is the URL-identity problem the design already declines to solve.

Plain `url.<base>.insteadOf` needs no check: it rewrites fetch and push alike,
so the probe reads the repository the release publishes to.

The bound is now recorded in the design hub, in `references/recovery.md`, and in
the code comment beside the check, so the next reader meets it where the
over-claim used to be.
