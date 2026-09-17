# 2026-09-17 — One script under test per suite file

`tests/hook-test.sh` was 498 lines covering two unrelated scripts:
`toolkit/version-guard.sh`, a `PreToolUse` hook reading JSON payloads, and
`toolkit/check-version.sh`, which compares two JSON files and runs no git at
all. The name said "hooks" and only half of it was one. Split into
`tests/version-guard-test.sh` and `tests/check-version-test.sh`, each named for
the script it drives, with `justfile`'s `precommit` running both.

The seam was free. The check-version scenarios shared exactly two things with
the rest of the file — `$proj`'s `plugin.json` fixture and `assert_eq` — and
nothing else: none of the six git fixtures, neither PATH stub, no `run_guard`,
no `assert_deny`. So each file now carries its own copy of the six-line
assertion harness, which is what `release-test.sh` and `self-release-test.sh`
already do. A sourced helper would buy back six duplicated lines at the price of
a suite that can no longer be read or run on its own.

`check-version-test.sh` also drops the `unset $(git rev-parse --local-env-vars)`
preamble every other suite here opens with, and says why in its header: that
line exists because a leaked `GIT_DIR` from an enclosing `git commit` would
redirect a fixture's git commands at this repo, and this suite runs no git
command for it to redirect. Carrying it anyway would have implied a hazard the
file does not have.

## The residual overage

`version-guard-test.sh` lands at 447 lines, still past the 400-line guideline.
That was predicted when the split was deferred out of the first-release-version
plan, and the reason not to cut again has not changed: the remaining seam runs
*through* the shared fixtures rather than beside them. Payload-and-path
resolution and release-state wording both need `$proj`, `run_guard`,
`assert_deny` and `assert_allow`, so splitting there does cost a sourced helper
— a fragmented read, to satisfy a cap nothing under `tests/` measures and that
no hard-wrapping formatter has made honest for this path. About 45% of the file
is comment, which is this repo's house style and not padding.

Recorded rather than fixed, so the next reader inherits the argument instead of
the number.
