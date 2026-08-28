# 2026-08-28 — The marketplace writability probe keeps mktemp's own words

Found auditing gitlore's vendored `plugin-dev/` copy, reported by
`brief-release-sh-two-nits-from-gitlore-audit.md`. `check_marketplace_writable`
creates a temp file in the marketplace's `.claude-plugin/` because
`bump_marketplace` unlinks and recreates `marketplace.json` there, so the
directory's writability is what matters rather than the file's mode bits.
Provoking the failure is the mechanism, so the probe is right; discarding what
it provoked was not.

The probe redirected mktemp's stderr to `/dev/null` and died with a message
naming a Claude Code sandbox restriction. That is the common cause and it is
useful advice, but the probe never established it. A read-only mount, a full
disk, a directory whose mode was changed by hand and a genuine sandbox denial
all produced the same sentence, and the one line that could tell them apart was
thrown away.

Now `2>&1`, with mktemp's diagnosis interpolated into the message and the
sandbox line kept as the advice it always was. On success `$probe` is still the
path, because mktemp says nothing on stderr when it succeeds.

Also comments the position of `[ "$mode" = "release" ] && check_marketplace_writable`
inside `common_preflight`. A false `&&` list is exempt from `errexit`
mid-function, which is why `--resume` skips the check rather than dying at it —
but as the *last* command of the function its status would become the
function's, and `common_preflight` would exit 1 with no message at all on every
resume. The exemption is positional and nothing else in the file says so.

`tests/release-test.sh`'s existing read-only-marketplace scenario carries the
new assertion. Confirmed red against the unfixed script: the message contained
the path and both escape hatches, and no trace of `Permission denied`.
