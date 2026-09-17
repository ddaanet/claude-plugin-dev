# Item 2.1, slice 1 — test review

Scope: `tests/hook-test.sh` (uncommitted working-tree changes) and
`reports/item-2-1-s1-red.md`. `toolkit/version-guard.sh` was mutated only for
probes and restored byte-identical (see "SUT integrity" at the end).

Verdict: the slice is a genuine red on three assertions, the fixture is honest,
and the scenario is a legitimate *existence* contract rather than a
discriminating one — slice 1 cannot tell a correct branch from three wrong ones,
and slices 4 and 6 are the guards that can. Two real defects found and fixed
(trap/`set -u` ordering, empty-array expansion under bash < 4.4). Red is
unchanged after the fixes.

## 1. Mechanical check

`bash tests/hook-test.sh`, verbatim (pre-fix run; `bash --version` reports
`GNU bash, version 5.2.37(1)-release (x86_64-pc-linux-gnu)`):

```
=== version-guard (Edit version change: deny) ===
=== version-guard (Edit bare version value: deny) ===
=== version-guard (Edit unrelated field: allow) ===
=== version-guard (Write version change: deny) ===
=== version-guard (unrelated file: allow) ===
=== version-guard (drifted payload cwd: deny) ===
=== version-guard (relative file_path: deny) ===
=== version-guard (BSD realpath, unrelated file: allow) ===
=== version-guard (no tags: initial-release wording) ===
FAIL: version-guard no-tags reason: never-released wording: expected to contain 'never been released', got 'plugin.json version edit refused: 1.2.3 -> 9.9.9.

The manifest version is the last released version. It is changed only by
'just release {patch|minor|major}', which validates state, bumps, commits,
tags, and pushes in one step. The release recipe also refuses if plugin.json
and the latest git tag disagree.

If the goal is to ship a release, invoke the recipe instead of editing this
file. Do not bypass this guard, modify the recipe, or alter version state by
other means.'
FAIL: version-guard no-tags reason: will-publish wording: expected to contain 'will publish', got 'plugin.json version edit refused: 1.2.3 -> 9.9.9.

The manifest version is the last released version. It is changed only by
'just release {patch|minor|major}', which validates state, bumps, commits,
tags, and pushes in one step. The release recipe also refuses if plugin.json
and the latest git tag disagree.

If the goal is to ship a release, invoke the recipe instead of editing this
file. Do not bypass this guard, modify the recipe, or alter version state by
other means.'
FAIL: version-guard no-tags reason: no last-released wording: expected NOT to contain 'last released version', got 'plugin.json version edit refused: 1.2.3 -> 9.9.9.

The manifest version is the last released version. It is changed only by
'just release {patch|minor|major}', which validates state, bumps, commits,
tags, and pushes in one step. The release recipe also refuses if plugin.json
and the latest git tag disagree.

If the goal is to ship a release, invoke the recipe instead of editing this
file. Do not bypass this guard, modify the recipe, or alter version state by
other means.'
=== check-version (MARKETPLACE_DIR unset: skip) ===
=== check-version (marketplace.json missing: skip) ===
=== check-version (no entry: skip) ===
=== check-version (in sync: pass) ===
=== check-version (drift: fail) ===

3 failure(s)
EXIT=1
```

Confirmed from this run:

- Exactly the three new wording assertions fail. Each failure text is the
  `fail()` message emitted from `assert_contains`/`assert_not_contains` after a
  failed `[[ ]]`, i.e. a real assertion failure — not a shell error, not a
  `set -e` abort, not an ERROR. None of the three passes.
- The new fixture's `assert_deny` passes: none of its five failure labels
  (`exit code`, `no deny decision`, `no permissionDecisionReason`,
  `no systemMessage`, `wrote to stderr`) appears.
- All fourteen pre-existing scenarios (eight version-guard, five check-version,
  plus the BSD-realpath allow) produce no `FAIL` line.

Lint: `bash -n tests/hook-test.sh` OK, `shellcheck tests/hook-test.sh` clean
(both before and after the fixes).

## 2. Discrimination — what slice 1 catches and what it does not

Four mutations run against the SUT in place (unconditional wording, `v*`
emptiness without the semver filter, repo-ness, and the intended green as a
control). **Slice 1 catches none of the three wrong predicates** — its fixture
has no tags, so every predicate a reasonable implementation could key on agrees
on it. It is an existence contract, and the control mutation confirms it is not
over-specified into unbuildability.

The table, and which slice owns each wrong implementation, is
[item-2-1-slice-coverage.md](item-2-1-slice-coverage.md). The load-bearing
conclusion for the orchestrator:
**slice 4 is the only slice that catches all three wrong predicates.**

## 3. Needle analysis

Each of the three needles was checked in both directions: can ordinary English
satisfy it by accident, and can a *correct* message fail it? No needle was
changed — all three are verbatim from the runbook, and changing one would change
the red. Two are constraints on the GREEN author rather than hazards in the
test; the negative needle is defeatable by rephrasing but is belt-and-braces
behind the two positives.

Full analysis, and the constraints it puts on any later edit to the message:
[item-2-1-message-needles.md](item-2-1-message-needles.md).

## 4. `extra_env` under `set -u` — fixed

The suite runs under `bash 5.2.37` on this box, where expanding an empty array
under `set -u` is safe (bash 4.4+). But the shebang is `#!/usr/bin/env bash`,
this repo explicitly targets macOS (there is a whole BSD-realpath scenario), and
macOS ships `/bin/bash` 3.2.57, where both `local extra_env=("${@:3}")` with
fewer than three arguments and `"${extra_env[@]}"` on an empty array are
unbound-variable errors. Every one of today's nine `run_guard` call sites passes
no `$3`, so on such a box the *entire* version-guard half of the suite would
abort on the first scenario.

House precedent says defend: `tests/release-test.sh:49` already writes
`for s in "${sandboxes[@]:-}"`. The `:-` form is wrong at this particular use
site, though — on an empty array it expands to a single empty word, which would
hand `env` an empty argument and make it fail with
`env: '': No such file or directory`. The correct form is
`${extra_env[@]+"${extra_env[@]}"}`.

Fix applied:

```sh
    local extra_env=()
    if [[ $# -gt 2 ]]; then extra_env=("${@:3}"); fi
    set +e
    guard_out="$(printf '%s' "$payload" \
        | env CLAUDE_PROJECT_DIR="$project" PATH="$guard_path" ${extra_env[@]+"${extra_env[@]}"} \
```

The `if` guards the `"${@:3}"` slice; the `+` form guards the expansion. Both
are needed for 3.2.

`tests/` does not ship to consumers, which bounds the blast radius to
maintainers running the gate on a stock-bash macOS — but it is a two-line fix
with existing precedent in the sibling suite, so it was applied rather than
merely noted.

Verified end-to-end that the replacement mechanism actually works (this is the
machinery slice 5 will be the first to use, so a silent break here would surface
as a confusing slice-5 red). Running `run_guard`'s body verbatim against a stub
that prints its environment:

```
empty:     rc=0 GIT_DIR=[unset] SPACED=[unset]
populated: rc=0 GIT_DIR=[/some/where] SPACED=[a b c]
```

The populated case carries a value containing spaces through intact.

## 5. The trap and `$git_proj` — fixed

The report's claim that the single-quoted trap body resolves `$git_proj` at exit
time is true but incomplete. As written, `trap` was at `:51` and
`git_proj="$(mktemp -d)"` at `:68`, with `mkdir -p "$proj/.claude-plugin"` and a
`cat >` heredoc in between — both of which can fail (read-only `$TMPDIR`,
ENOSPC) and, under `set -e`, exit. The trap then runs with `git_proj` unbound
under `set -u`.

Measured, rather than reasoned:

```
--- does set -u break a trap referencing an unbound var?
TRAP RUNS
/tmp/claude-1000/s1rev/traptest.sh: line 1: b: unbound variable
script exit=1
```

The trap starts, dies on the unbound expansion **before** reaching `rm -rf`, and
"TRAP DONE" never prints — so cleanup does not merely skip `$git_proj`, it skips
`$proj` and `$guard_err` too. Every temp dir leaks, on the exact path where
something already went wrong.

Fix applied: allocate the directory beside the other two, ahead of the trap, so
it is always bound.

```sh
proj="$(mktemp -d)"
guard_err="$(mktemp)"
# $git_proj is allocated here, not beside the fixture it belongs to below,
# so the trap can name it: under `set -u` a failure between the trap and a
# later assignment runs the trap with it unbound, which aborts the trap
# before the rm and leaks every temp dir. Same reason release-test.sh
# declares `sandboxes=()` ahead of its own trap.
git_proj="$(mktemp -d)"
trap 'rm -rf "$proj" "$guard_err" "$git_proj"' EXIT
```

The fixture block keeps `git init -q "$git_proj"` and its comment, now noting
the directory is allocated above. Positive control on the fixed shape:

```
--- positive control: trap with the var bound before it
TRAP RUNS
TRAP DONE (both removed: yes)
script exit=1
```

## 6. Fixture honesty

The report justifies a zero-commit `git init` fixture on `git tag --list`
exiting 0 with no output. Verified independently, and — more importantly —
verified for the *exact* pipeline the SUT will use, which the report did not
check. `toolkit/release.sh:282` is
`git tag --list 'v*' --sort=-v:refname | semver_tags`, where `semver_tags`
(`:269`) is `{ grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' || [ "$?" -eq 1 ]; }`.

```
--- zero-commit: git tag --list
rc=0
--- zero-commit: semver pipeline
out=[] pipeline_rc=0
--- with-commit: semver pipeline
out=[] pipeline_rc=0
--- raw exit codes of git tag --list in each
empty rc=0
withcommit rc=0
```

A zero-commit repo and a repo with a commit and no tags are indistinguishable to
the predicate: same empty output, same exit 0, on `git tag --list` and on the
full semver pipeline alike. The fixture is testing the same thing the SUT will
meet in production. No change needed.

Also checked that the fixture does not depend on the invoking user's git
configuration: `git init -q` emits nothing at all under
`HOME=/nonexistent GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null` (the
`init.defaultBranch` advice is suppressed by `-q`), so the suite's own stderr
stays clean on a box without `init.defaultBranch` set.

## 7. Harness transparency

- **`run_guard`'s default argument is genuinely transparent.**
  `git diff tests/hook-test.sh | grep -E '^[-+].*run_guard '` returns exactly
  one line — the `+` for the new scenario's call. No existing `run_guard` call
  line was added or removed, so none was edited. The nine pre-existing scenarios
  all pass (§1).
- **`unset $(git rev-parse --local-env-vars)` is correctly placed.** It sits at
  `:14`, immediately after `set -euo pipefail` and before `cd "$repo_root"` and
  before every git command in the file, including the fixture's `git init` at
  `:69`. Verified that `git rev-parse --local-env-vars` does not require a
  repository — it prints its fifteen-name static list with `rc=0` from a
  non-repo directory — so running it before the `cd` is safe. It is
  character-for-character the same construct, comment shape and
  `# shellcheck disable=SC2046` as `tests/release-test.sh:8-13`.
- **The SC2046 suppression is not hiding anything.** The word splitting is the
  mechanism, and the split input is a fixed list of `GIT_*` identifiers with no
  whitespace in any element (printed above). The one degenerate case — `git`
  absent from `PATH` — leaves `unset` with no arguments, which is a no-op
  returning 0, so it does not trip `set -e`; a box without `git` fails
  everywhere else in this suite anyway.

## 8. Whitespace safety

Reviewed the new code rather than only the happy path:
`git init -q "$git_proj"`, `mkdir -p "$git_proj/.claude-plugin"`, the
`cat > "$git_proj/..."` redirect, the trap body, both `run_guard` parameters and
the array expansions are all quoted. The only unquoted expansions in the added
code are the deliberate `unset $(git rev-parse --local-env-vars)` split (§7) and
`${extra_env[@]+"${extra_env[@]}"}`, whose inner expansion is quoted — proven
above to carry `SPACED=a b c` through as one argument.

Then run against a spaced input rather than claimed from reading. The whole
suite under `TMPDIR=/tmp/claude-1000/sp ace dir`, so every `mktemp -d` path
contains two spaces:

```
3 failure(s)
EXIT=1
```

Same three wording failures, nothing else — no shell error, no `assert_deny`
failure, no fixture breakage.

## 9. Fixes applied

Two, both in `tests/hook-test.sh`, both argued above:

1. `git_proj="$(mktemp -d)"` moved ahead of the `trap` line (§5) — without it,
   an early failure aborts the whole cleanup, not just this dir's.
2. `extra_env` built and expanded in the bash-3.2-safe form (§4) — without it,
   the version-guard half of the suite aborts on stock macOS bash.

Nothing else was changed. In particular the three needles, the `assert_deny`
call, the fixture's zero-commit shape and every existing scenario are untouched.

## 10. Post-fix re-run — red unchanged

`bash -n` OK, `shellcheck` clean, then `bash tests/hook-test.sh`:

```
=== version-guard (Edit version change: deny) ===
=== version-guard (Edit bare version value: deny) ===
=== version-guard (Edit unrelated field: allow) ===
=== version-guard (Write version change: deny) ===
=== version-guard (unrelated file: allow) ===
=== version-guard (drifted payload cwd: deny) ===
=== version-guard (relative file_path: deny) ===
=== version-guard (BSD realpath, unrelated file: allow) ===
=== version-guard (no tags: initial-release wording) ===
FAIL: version-guard no-tags reason: never-released wording: expected to contain 'never been released', got 'plugin.json version edit refused: 1.2.3 -> 9.9.9.
[...same steady-state message as in §1...]
FAIL: version-guard no-tags reason: will-publish wording: expected to contain 'will publish', got 'plugin.json version edit refused: 1.2.3 -> 9.9.9.
[...]
FAIL: version-guard no-tags reason: no last-released wording: expected NOT to contain 'last released version', got 'plugin.json version edit refused: 1.2.3 -> 9.9.9.
[...]
=== check-version (MARKETPLACE_DIR unset: skip) ===
=== check-version (marketplace.json missing: skip) ===
=== check-version (no entry: skip) ===
=== check-version (in sync: pass) ===
=== check-version (drift: fail) ===

3 failure(s)
EXIT=1
```

Identical to §1: the same three assertions, the same labels, the same messages,
`assert_deny` still passing, all fourteen pre-existing scenarios still passing.
The fixes changed nothing about what is red.

## SUT integrity

`toolkit/version-guard.sh` was mutated four times for §2 and restored from a
pre-probe copy each time. Final state:

```
$ git diff --stat toolkit/version-guard.sh
$ md5sum toolkit/version-guard.sh
e16114acd7e245c190b7e278ff141e19  toolkit/version-guard.sh
$ git status --porcelain toolkit/
```

Empty diff, empty status, and the digest matches the copy taken before the first
mutation — byte-identical to HEAD.

## For the GREEN dispatch

Three things this review turned up that the GREEN author needs:

1. The message must contain the literal `will publish` and
   `never been released`, and must not contain `last released version`
   **anywhere**, including inside a negation like "there is no last released
   version". Slice 1 is phrase-exact.
2. Slice 1 alone cannot tell the semver predicate from `v*`-emptiness, from
   repo-ness, or from no predicate at all. Do not read a green slice 1 as
   evidence the predicate is right; slice 4 is the only slice that catches all
   three wrong predicates.
3. The non-repo `$proj` scenarios already assert stderr stays empty
   (`assert_deny`'s last check), so once the listing lands they are a live test
   of the `2>/dev/null` on it — the item text's "expected outcome, not a
   diagnostic" justification has real coverage behind it and does not need a new
   scenario.

Nothing in slice 1 pre-empts or under-serves slices 2–6: it asserts wording
presence only, leaves `$proposed` containment (slice 2), `systemMessage`
invariance (slice 3), the predicate (slice 4), `GIT_*` clearing (slice 5) and
listing-failure fallback (slice 6) entirely to their own slices, and the
`run_guard` env-injection mechanism it builds ahead of slice 5 is verified
working (§4).
