# 2026-08-28 — A refused release commit rolls the manifest back

Found in `cwd-safety` on 2026-08-27, reported by a brief now at
[plans/](../../plans/) alongside the rest of the closed set. `just release`
died mid-`bump_commit_tag` when the consumer's `pre-commit` hook refused the
release commit — gitlore's FR11 memory-approval gate, which every consumer
mounts. The manifest was already rewritten and staged; nothing was committed
and nothing was tagged.

The strand is what made it more than a retry. `common_preflight` requires a
clean tree, and the leftover bump is a dirty tree, so the obvious next command
fails:

```
error: uncommitted changes
```

Both entry points, not one. An audit of the brief established that
`common_preflight` runs before the mode dispatch, so `just resume-release` dies
on the identical line — the brief had assumed resume would at least answer
`no tag vX.Y.Z for plugin.json version X.Y.Z` and point somewhere. It does not.
Neither command names the gate that refused, the bump that was left behind, or
what to do about it. Recovery meant reading `release.sh` and reverting the
manifest by hand.

Fixed by guarding the commit and restoring the manifest from HEAD when it
fails, which puts the tree back exactly as the run found it. The failure then
means what a refused commit should mean: satisfy the gate and run the same
command again. The refusal names the gate, the version it rolled back to, and
that nothing was tagged.

Only the commit is guarded, not the whole of `bump_commit_tag`. An earlier
option wrapped the tag as well, against a tag racing in between
`release_preflight`'s existence check and `git tag -a` — but a `pre-commit`
hook cannot make `git tag` fail, and that is the failure this entry is about.
A guard for a race nobody has hit would be cruft with a reassuring name.

`tests/release-test.sh` covers it: a fixture consumer with a refusing
`pre-commit` hook, asserting the rollback, the clean tree, the absent tag and
that `gh` was never called — then, with the hook removed, that an ordinary
`release patch` completes with no manual repair in between. Confirmed red
against the unfixed script with all six assertions failing, including the bare
`uncommitted changes` on the re-run.
