# Item 1.3, slice 2 — RED

**Passed on arrival**, as predicted — this is a characterization guard whose
value rests on the mutation evidence, and the mutation evidence holds: the
scenario fails cleanly when the push-route check is moved out of
`common_preflight` into `release_preflight` (the exact regression this slice
exists to catch), and slice 1's three release-mode settings stay green under
that mutation. A second mutation (full removal of the check) also fails the new
scenario, as expected. `toolkit/release.sh` is restored byte-identical after
both probes; nothing committed.

## Scope

IN: `tests/release-test.sh` only. `toolkit/release.sh` was mutated twice as a
probe and restored both times, verified byte-identical (`diff` against a
pre-mutation copy, not just `sha256sum`). Nothing else touched.

## `--resume` baseline on an untouched healthy repo

Already established by an existing scenario in the suite — "resume: no-op on a
healthy repo" (`tests/release-test.sh:385`) — which I re-read rather than
re-derive. On a repo that has already completed a real release and is run again
with `--resume`:

- exit 0
- output contains `already complete (nothing to do)`
- `$GH_LOG` contains `release view v1.2.4` —
  **`--resume` DOES call `gh` when it has somewhere to go.**

This is what makes `$GH_LOG` empty a real assertion for the new scenario: it is
not "resume happened to have nothing to do", it is "resume was refused before it
got the chance to probe". I did not re-run this baseline separately — the same
setup literally opens the new scenario (`release.sh patch` then `: > "$GH_LOG"`)
and the mutation runs below reproduce the un-refused behaviour
(`release view v1.2.4` in `$out`/`$GH_LOG`) directly, which is stronger
confirmation than a standalone repeat would have been.

## The scenario

Placed immediately after slice 1's release-mode block (`tests/release-test.sh`,
now at line 922, right before
`=== release: non-semver v tags are not releases ===`), matching the "related
ones" placement instruction — it is the `--resume` counterpart of the block
directly above it, not a general resume scenario grouped with the ones near the
top of the file.

```sh
echo "=== resume: common_preflight refuses a diverged push route ==="
# Same predicate as the release-mode block above, reached through --resume
# instead of `release`: outline.md decision 3 requires the refusal on both
# modes, and common_preflight runs unconditionally before the
# release/resume branch (`5fa9e0d`'s :714), so nothing resume-specific
# should be needed to reach it.
#
# The fixture is deliberately "healthy" in the sense that matters: a real,
# completed release already sits on origin, so an unmodified --resume here
# has somewhere to go and something to say — see "resume: no-op on a
# healthy repo" above, which is this exact setup without the diverged
# route, and which DOES call `gh release view v1.2.4` and reports
# "already complete (nothing to do)". Establishing that first is what makes
# `$GH_LOG` empty below a real assertion about ordering (refused before any
# resume probing) rather than an accident of resume having nothing to do
# for an unrelated reason.
new_sandbox "1.2.3"
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "0" "resume-push-route setup release exit code"
: > "$GH_LOG"
other="$sandbox/push-target repo.git"
git init -q --bare -b main "$other"
git -C "$plugin" config remote.origin.pushurl "$other"
run_in "$plugin" bash plugin-dev/release.sh --resume
assert_eq "$rc" "1" "resume diverged-push-route exit code"
assert_contains "$out" "remote.origin.pushurl" "resume diverged-push-route names the setting"
assert_contains "$out" "$other" "resume diverged-push-route names the value"
assert_eq "$(cat "$GH_LOG")" "" "resume diverged-push-route must not call gh"
```

Only `pushurl`, not all three settings: the runbook specifies "healthy fixture
with `remote.origin.pushurl` set" — singular — and slice 1 already proves the
three-key iteration and the `branch.$branch.pushRemote` derivation in release
mode; re-running all three here would test the same predicate through a
different mode without adding coverage the mutation below can't already see (the
mutation moves the whole loop, all three keys at once — see the mutation table).
Reused the `pushtarget`/`push-target repo.git` fixture convention from slice 1
verbatim, per the test-review's §1 instruction not to rename it (not that it
matters for `pushurl`, whose needle is the mktemp path, but the directory name
is shared machinery).

### Value assertion — included, and why

The dispatch asked me to consider whether the value should be asserted, given
slice 1's review found a key-only message slips past most assertions. I included
`assert_contains "$out" "$other" …` for the same reason slice 1 does: a GREEN
(or a future edit) that refuses on `pushurl` but reports only the key would
still pass "names the setting" and the exit-code and empty-`$GH_LOG` assertions.
The value assertion is the one that would catch that specific regression, so
leaving it out here would reopen exactly the hole slice 1's test-review closed,
just in the `--resume` path instead of `release`.

## Run against unmodified `toolkit/release.sh`

```
$ bash -n tests/release-test.sh && echo "bash -n OK"
bash -n OK
$ shellcheck tests/release-test.sh && echo "shellcheck OK"
shellcheck OK
$ git diff --stat -- toolkit/release.sh
(empty)
$ TMPDIR=/tmp/claude-1000 bash tests/release-test.sh
[... 50 scenario headers, including both "=== release: common_preflight
refuses a diverged push route ===" and the new
"=== resume: common_preflight refuses a diverged push route ===" ...]

all release scenarios passed
```

Exit 0. Passed on arrival, as expected.

## Mutation 1 — move the loop from `common_preflight` into `release_preflight`

This is the exact regression the slice exists to catch: the check still runs in
`release` mode, stops running in `--resume` mode.

- Backed up `toolkit/release.sh` to `/tmp/claude-1000/s2/release.sh.orig` first;
  `sha256sum` recorded before mutating:
  `cd91ac53725cac7541062792364679a3ca387e3580bf042ccccdf3815e4a0b36`.
- Removed the `local push_key push_values push_value` / `for push_key in …done`
  block (and its preceding comment) from `common_preflight`, between the branch
  check and the `MARKETPLACE_DIR` check.
- Inserted the same `local … / for … done` block (without the comment) as the
  first statement in `release_preflight`, right after its own `local`
  declaration.
- `bash -n toolkit/release.sh`: clean.

Run:

```
$ TMPDIR=/tmp/claude-1000 bash tests/release-test.sh
EXIT=1
```

Failures (`grep '^FAIL'`), verbatim — exactly 4, all in the new scenario:

```
FAIL: resume diverged-push-route exit code: expected '1', got '0'
FAIL: resume diverged-push-route names the setting: output did not contain 'remote.origin.pushurl'
FAIL: resume diverged-push-route names the value: output did not contain '/tmp/claude-1000/tmp.m1h1uXkqcH/push-target repo.git'
FAIL: resume diverged-push-route must not call gh: expected '', got 'release view v1.2.4'
```

All three `diverged-push-route (…)` scenarios from slice 1 (release mode) — 18
assertions total — stayed green; `grep '^FAIL'` on the full run shows only the
four lines above, none matching
`diverged-push-route (pushurl\|pushRemote\|pushDefault)`. The 5th assertion in
my scenario ("must not call gh") is the one listed above; there is no
marketplace-untouched assertion in this scenario to check separately, but for
completeness: the resumed run's `$out` under the mutation reports
`already complete (nothing to do)`, consistent with the mutated `--resume`
reaching the point slice 1's baseline scenario describes.

Restored: `cp /tmp/claude-1000/s2/release.sh.orig toolkit/release.sh`, then
`diff` against the backup — identical — and
`git diff --stat -- toolkit/release.sh` produced no output (exit 0).

**Conclusion: the scenario discriminates.** It catches the precise release-only
regression while slice 1's three release-mode settings remain unaffected.

## Mutation 2 (my choice) — remove the push-route check entirely

A reader might plausibly expect *this* scenario, standing alone, to also catch a
full feature removal (not just a mode-scoped regression) — I checked. Deleted
the same block from `common_preflight` without moving it anywhere.

```
$ bash -n toolkit/release.sh && echo OK
OK
$ TMPDIR=/tmp/claude-1000 bash tests/release-test.sh
EXIT=1
```

Failures: all 18 assertions across slice 1's three release-mode settings failed
(predictably — full removal breaks the release-mode block too), and all 4 of the
new scenario's assertions failed:

```
FAIL: resume diverged-push-route exit code: expected '1', got '0'
FAIL: resume diverged-push-route names the setting: output did not contain 'remote.origin.pushurl'
FAIL: resume diverged-push-route names the value: output did not contain '/tmp/claude-1000/tmp.ml3C3Ry2O3/push-target repo.git'
FAIL: resume diverged-push-route must not call gh: expected '', got 'release view v1.2.4'
```

**Yes, it catches this too** — unsurprising, since removing the check removes it
from both modes at once, and the new scenario exercises `--resume` directly.
This mutation is weaker evidence than mutation 1 (it doesn't isolate the
mode-scoping property), which is why the dispatch's chosen mutation was the
move, not the deletion — recorded here per instruction 4, not as the main proof.

Restored: `cp /tmp/claude-1000/s2/release.sh.orig toolkit/release.sh`, `diff`
against the backup — identical.

## Mutation table

| Mutation | Slice 1 (release, 3 settings, 18 assertions) | Slice 2 (this scenario, 4 assertions) |
|---|---|---|
| Move loop `common_preflight` → `release_preflight` | all green | all 4 red |
| Delete loop entirely | all 18 red | all 4 red |

## Full-suite and precommit, after final restore

```
$ diff /tmp/claude-1000/s2/release.sh.orig toolkit/release.sh && echo IDENTICAL
IDENTICAL
$ git diff --stat -- toolkit/release.sh
(no output)
$ TMPDIR=/tmp/claude-1000 bash tests/release-test.sh
[... all 50 scenario headers ...]

all release scenarios passed
$ just precommit
[... bash -n, shellcheck, _import-check, tests/hook-test.sh,
tests/release-test.sh, tests/update-plugin-dev-test.sh (all 50 scenarios
green), tests/dist-tree-test.sh ("dist tree ok (9 files, no gitlink)"),
tests/docs-test.sh ("docs ok (cap 400 lines, pointers resolve)"),
tests/doc-sync-test.sh ("doc sync ok (5 shared command blocks, Layout
matches toolkit/)") ...]
ok
```

## State on exit

- `toolkit/release.sh` — **untouched.** Probed twice (both mutations above) and
  restored from `/tmp/claude-1000/s2/release.sh.orig` each time; final `diff`
  against that backup is empty, and `git diff --stat -- toolkit/release.sh`
  produces no output.
- `git status --short` (top-level): only `M tests/release-test.sh`.
- Modified: `tests/release-test.sh` only (one new scenario, inserted after slice
  1's block, no existing scenario touched, `pushtarget` fixture name and the
  `ls-remote | cut` captures at the pre-existing line numbers untouched).
- **Nothing committed. Nothing staged.**
- `bash -n` and `shellcheck` on `tests/release-test.sh`: clean.
- `TMPDIR` was unset in this dispatch shell; every probe, backup and scratch
  file went to `/tmp/claude-1000/s2/`. Nothing left in the repo root.
