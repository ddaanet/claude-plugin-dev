# Item 1.3, slice 1 — GREEN

Scope: `toolkit/release.sh` only. `tests/release-test.sh` untouched from the
handed-over red state.

## Implementation

Inserted into `common_preflight`, immediately after the `$branch` /
`$main_branch` validation (`:149`) and before the `MARKETPLACE_DIR` checks —
before any side effect, and reached in both `release` and `--resume` modes since
`common_preflight` runs in both.

```sh
    for push_key in remote.origin.pushurl "branch.$branch.pushRemote" remote.pushDefault; do
        if push_value=$(git config --get "$push_key"); then
            die "push route diverges from origin: $push_key is set to $push_value; unset it or point it at origin"
        elif [ "$?" -ne 1 ]; then
            die "could not read git config $push_key"
        fi
    done
```

(Full comment block explaining the rationale is inline in the file, above the
loop.)

### Refusal message, verbatim (pushurl example)

```
error: push route diverges from origin: remote.origin.pushurl is set to /tmp/.../push-target repo.git; unset it or point it at origin
```

Names both the key (`remote.origin.pushurl`, `branch.main.pushRemote`,
`remote.pushDefault`) and the exact value `git config --get` returned
(`$push_value`), unmodified — satisfies test-review requirement 3.

### Branch key derivation

`"branch.$branch.pushRemote"`, not a hardcoded `branch.main.pushRemote`.
`$branch` is already bound and validated
(`[ "$branch" = "$main_branch" ] || die …` at `:149`) by the point this loop
runs, so no new derivation was needed — the check sits after that line
specifically so `$branch` is available and already known equal to
`$main_branch`. Satisfies test-review requirement 2 (the fixture cannot catch
this; it was a review-only requirement).

### Status-absorption form chosen, and why

`if push_value=$(git config --get "$push_key"); then … elif [ "$?" -ne 1 ]; then die …; fi`
— the assignment is the `if` condition itself, not the left side of a
`cmd || { … }` group.

Chosen over the `value=$(f) || { [ "$?" -eq 1 ] || die …; }` form the RED/
test-review reports sketch, for one reason: an `if` condition is natively exempt
from `set -e` (POSIX; this is the same exemption that already covers
`tree_is_clean "." || { … }` elsewhere in this file), so there is no group-body
pitfall to reason about at all — `item-1-2-s6-code-review.md` §2's finding
(errexit stays live for commands *inside* a `cmd || { … }` group's final
element) simply does not apply here, because nothing runs inside a brace group.
`$?` read as the first thing in the `elif` clause is still the failed `if`
condition's status, since nothing executes between the `if` failing and the
`elif` clause starting.

Net effect: status 0 (key set) → refuse, naming key and value. Status 1 (key
unset) → the `elif` test is false, loop continues — absorbed. Any other status →
`elif` is true → `die "could not read git config $push_key"`, a generic message
rather than silence. Per the test-review's judgement 4, no fixture in the suite
can pin this branch (a corrupt config breaks every git call with 128 before this
loop is even reached), so this form is chosen because it is the correct reading
of the capture rule, not because a test enforces it.

## Full-suite and precommit results

- `bash -n toolkit/release.sh`: clean.
- `TMPDIR=/tmp/claude-1000 bash tests/release-test.sh`: all 49 scenarios green,
  including all 18 assertions across the three diverged-push-route settings
  (`=== release: common_preflight refuses a diverged push route ===`),
  `all release scenarios passed`.
- `just precommit`: green — `bash -n`, `shellcheck`, `_import-check`,
  `tests/hook-test.sh`, `tests/release-test.sh`,
  `tests/update-plugin-dev-test.sh`, `tests/dist-tree-test.sh` (9 files, no
  gitlink), `tests/docs-test.sh` (cap 400 lines, pointers resolve),
  `tests/doc-sync-test.sh` (5 shared command blocks, Layout matches `toolkit/`).
  `format-docs` ran clean over the files this change touches (three pre-existing
  over-length lines flagged in unrelated, previously committed reports — not
  part of this diff, left untouched).

## Commit

`git diff --stat` before staging: `tests/release-test.sh | 69 ++`,
`toolkit/release.sh | 32 ++`, both additions only.

Staged: `tests/release-test.sh`, `toolkit/release.sh`,
`plans/2026-09-15-first-release-version/reports/item-1-3-s1-red.md`,
`plans/2026-09-15-first-release-version/reports/item-1-3-s1-test-review.md`.

Commit hash: **RECORDED BELOW AFTER COMMIT**

## Tree state after commit

Clean — verified with a top-level `git status` after the commit (the
`$HOME`-dotfile phantom-untracked issue only affects nested/scripted
`git status`, per the dispatch's environment caveat).
