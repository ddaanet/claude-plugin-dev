# 2026-09-07 — A refused marketplace commit rolls the bump back too

The mirror of [2026-08-28](2026-08-28-refused-commit-rolls-back.md), one repo
over and much later in the flow, finally made automatic.

The 2026-09-03 diagnostics pass gave `bump_marketplace`'s commit failure a
message. It left the bump staged in `MARKETPLACE_DIR` and printed the command to
clear it:

```
git -C <marketplace> checkout HEAD -- .claude-plugin/marketplace.json
```

followed by `just resume-release`. That was scoped correctly for a brief about
messages, but it left the recovery at two commands, and made the first of them
mandatory rather than optional — `common_preflight` reads the leftover as an
unrelated dirty tree in the marketplace repo and refuses `resume-release` on it.
Which is precisely the argument that made the manifest rollback automatic in
August: a leftover that blocks the one command that would finish the release is
not a state to describe, it is a state not to leave behind.

It is stronger here than it was for the manifest. A refused version commit
leaves nothing published — there is no partial release, and the recovery is to
re-run the same command. A refused marketplace commit is the last step of a
release and its only write outside the plugin repo, so by the time it fires the
version commit, tag, branch push and GitHub release are all public. The release
genuinely is partial and `resume-release` genuinely is the command that finishes
it. Blocking that command is worse than blocking a retry.

So `git -C "$MARKETPLACE_DIR" checkout HEAD -- .claude-plugin/marketplace.json`
now runs on the refusal, and the message says the bump was rolled back and names
`just resume-release` as the whole recovery. Restoring from HEAD is safe for the
same reason it is safe in `bump_commit_tag`: `common_preflight` has already
established that tree clean, so the restore returns it to what this run found
rather than discarding anything a human left there.

`tests/release-test.sh`'s marketplace-refusal scenario was rewritten to assert
the rollback — the marketplace version back at its pre-release value, a clean
marketplace tree, the plugin tag still public — and then that a bare
`release.sh --resume`, with the gate satisfied and no manual checkout in
between, finishes the release.
