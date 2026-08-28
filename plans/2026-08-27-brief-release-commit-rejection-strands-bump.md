# Brief: a rejected release commit strands the manifest bump

2026-08-27

Reported from `cwd-safety`, cutting v0.6.0 with the vendored toolkit. No change
was made to this repository — this is a finding, not a patch.

## What happened

`just release minor` ran the gate green, then `release.sh` reached
`bump_commit_tag`, rewrote `.claude-plugin/plugin.json` to `0.6.0`,
`git add`ed it, and ran `git commit -m "release: 0.6.0"`. The repo's gitlore
pre-commit hook rejected that commit: memory was dirty with no approved commit
summary, so the hook printed its instructions and exited non-zero. Under
`set -euo pipefail` the script died there.

That left the manifest bumped and **staged**, with no commit and no tag.

Recovering from it is where the sharp edge is:

- `just resume-release` refuses — `resume_preflight` requires a local tag at
  the manifest's version, and there is none. Its hint says to run
  `just release <bump>` instead.
- `just release minor` refuses too, and less helpfully. `common_preflight`'s
  `git diff --quiet HEAD -- . ':(exclude)memory'` sees the staged bump and dies
  with a bare `error: uncommitted changes`. Nothing connects that message to
  the script's own leftover, and the natural reading is that the user dirtied
  the tree.

I resolved it by hand with `git checkout HEAD -- .claude-plugin/plugin.json`,
then re-ran `just release minor`, which completed cleanly.

## Why it is worth fixing

The pre-commit hook rejecting a release commit is not an exotic state. Any
consumer with a commit gate — gitlore's FR11 approval gate here, but equally a
lint or secret-scan hook — hits it the first time the gate has something to say.
The gate is doing its job; the script just has no story for the commit failing.

`git commit` is the only step in `bump_commit_tag` that can fail against a
tree the preflight already validated, and it is called with no handling, so
`set -e` turns a recoverable refusal into a stranded working tree.

Every other step in `release.sh` is written probe-before-act so `--resume` can
finish a partial release. This one gap sits *before* the tag, which is exactly
the point `--resume` uses to decide a release was started, so the resume path
cannot see it.

## Options, for the maintainer to choose between

None of these is a decision — the trade-offs are yours.

1. **Roll back on commit failure.** Wrap the `git commit` in `bump_commit_tag`
   so a non-zero exit restores the manifest (`git checkout HEAD -- "$manifest"`,
   or unstage and revert the `jq` rewrite) and dies with a message naming the
   hook rejection as the cause. Leaves the tree exactly as `release.sh` found
   it, so the user fixes the hook complaint and re-runs the same command.
   Smallest change; keeps `--resume`'s tag-anchored contract intact.

2. **Teach `common_preflight` to recognise its own leftover.** If the only
   uncommitted change is `$manifest`, and its staged version is one bump ahead
   of `HEAD`'s, say so — name the likely cause and the exact
   `git checkout HEAD -- .claude-plugin/plugin.json` to run. Diagnostic only,
   no state change; composes with option 1 rather than replacing it.

3. **Dry-run the commit gate in `release_preflight`.** Costly and fragile —
   hooks are not generally idempotent or side-effect-free — and it does not
   help when the gate's complaint appears between the check and the commit.
   Mentioned for completeness; I would not take it.

Option 1 plus option 2's message is the shape I would expect to want, but the
call is yours.

## Where to look

In `toolkit/release.sh`:

- `bump_commit_tag` — the `git add "$manifest"` / `git commit -m "release: $V"`
  pair, immediately before `git tag -a`.
- `common_preflight` — the `git diff --quiet HEAD -- . ':(exclude)memory'` line
  that produces `error: uncommitted changes`.
- `resume_preflight` — the tag-existence check that makes `--resume` decline
  this state, and whose hint currently points at the command that also declines.

Observed against the copy vendored at `plugin-dev/` in `cwd-safety` as of this
date; all three functions were current there.

## Reproducing

In any consumer with a pre-commit hook that can refuse:

1. Make the hook exit non-zero (for gitlore: leave memory dirty with no
   approved summary in `.claude/gitlore-memory-message`).
2. Run `just release patch`. It dies after staging the bump.
3. `git status` shows `M .claude-plugin/plugin.json`, no tag at the new version.
4. `just resume-release` → `no tag vX.Y.Z for plugin.json version X.Y.Z`.
5. `just release patch` → `error: uncommitted changes`.
