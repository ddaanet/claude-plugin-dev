# Item 1.1 / slice 1 — RED report

Mode: RED. Test written: `pipefail-stripped release_tags failure refuses`,
appended to the `=== the origin probes fail closed with pipefail stripped ===`
harness at the end of `tests/release-test.sh` (new scenario block, after the
existing `no-pipefail probe` assertions, before the `if (( failures > 0 ))`
tally).

SUT untouched: `toolkit/release.sh` is unmodified (`git diff --stat` below
confirms only the test file changed).

## What the test does

- Copies `toolkit/release.sh` with the `set -euo pipefail` line rewritten to
  `set -eu` (same idiom the existing harness uses), into
  `plugin-dev/release-nopipefail-tags.sh` inside the fixture plugin.
- Builds a `git` wrapper on `PATH` (`$sandbox/git-wrapper/git`) that exits 1
  with a stderr line for `git tag --list …` and `exec`s the real `git` (resolved
  via `command -v git` at fixture-build time) for every other invocation — the
  `guard_stub127_dir` stub idiom from `tests/version-guard-test.sh`, adapted to
  delegate rather than blanket-fail.
- Runs `release-nopipefail-tags.sh patch` in the fixture plugin (already
  published at v1.2.3) with that wrapper prepended to `PATH`.
- Asserts: `rc` is 1; `$out` contains
  `could not list this plugin's release tags` (the needle is
  `release_preflight`'s existing `die`, since the git stub prints nothing of its
  own); `$out` does NOT contain `git fetch --tags` (the lost-tags remedy is the
  wrong branch).

## Command and exit status

```
cd /Users/david/code/claude-plugin-dev && bash tests/release-test.sh
```

Exit status: 1 (2 failures reported, both from the new test; every other
scenario in the file printed no `FAIL:` line).

## Per-test output (verbatim)

```
=== pipefail-stripped release_tags failure refuses ===
FAIL: pipefail-stripped release_tags failure refuses names release_preflight's die: output did not contain 'could not list this plugin's release tags'
  --- output ---
git: fatal: stub git failing tag --list
hint: origin already has release tags for this plugin — the newest is
      v1.2.3, missing from this clone. Run `git fetch --tags` to catch up,
      then run the same command again.
error: local release tags are missing — refusing to guess whether v1.2.3 was published
  --------------
FAIL: pipefail-stripped release_tags failure refuses did not take the lost-tags branch: output contained 'git fetch --tags'
  --- output ---
git: fatal: stub git failing tag --list
hint: origin already has release tags for this plugin — the newest is
      v1.2.3, missing from this clone. Run `git fetch --tags` to catch up,
      then run the same command again.
error: local release tags are missing — refusing to guess whether v1.2.3 was published
  --------------

2 failure(s)
```

## Interpretation

Against unchanged `toolkit/release.sh`, the stripped copy's
`git tag --list 'v*' --sort=-v:refname | semver_tags` pipeline swallows the
wrapper's `git tag --list` failure (pipefail is what would normally carry it,
and the copy has that line stripped): `release_tag_list` reads empty with status
0, `release_preflight` takes the lost-tags branch instead of the
`|| die "could not list this plugin's release tags…"` branch, and the output is
the `git fetch --tags` hint rather than the refusal the test requires. The third
assertion (`assert_eq "$rc" "1"`) coincidentally passes because the lost-tags
branch also exits 1 (`error: local release tags are missing`) — the test
correctly fails on *content*, not on exit status alone, which is the point: rc
alone cannot distinguish the wrong branch from the right one, exactly why the
message and not-contains assertions carry the proof. Both failures are genuine
assertion mismatches — no `ImportError`, no "command not found", no bash error —
confirming the test exercises the `release_tags` defect the GREEN dispatch
(capture-then-filter with `|| return 1`) is meant to fix.

## Scope confirmation

Only `tests/release-test.sh` was modified. `toolkit/release.sh` is unchanged.
Slice 2's test (`pipefail-stripped release_tags failure publishes nothing`) was
not written. Nothing was committed; the new test remains uncommitted in the
tree, as required for a RED dispatch.

```
$ git -C /Users/david/code/claude-plugin-dev status --short
 M memory
?? .mcp.json
 M tests/release-test.sh
```

(The `memory` and `.mcp.json` entries predate this dispatch and were not touched
by it.)
