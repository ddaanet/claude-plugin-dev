# Item 2.1, slices 2-6 — RED

Scope: `tests/hook-test.sh` only. `toolkit/version-guard.sh` was mutated only
for the guard proofs below and restored byte-identical after each; the working
tree carries no SUT change.

SUT checksum before the first mutation and after the last:
`3a7e923a452966bfe5c87d9795806e39` (md5sum of `toolkit/version-guard.sh`),
confirmed identical after every one of the four mutation rounds and again at the
end via `git status --porcelain toolkit/version-guard.sh` (empty) and
`git diff --stat toolkit/version-guard.sh` (empty).

## Per-slice verdict

| Slice | Case | Result |
| --- | --- | --- |
| 2 | Guard | Passes unmutated; fires on a mutation that interpolates `$proposed` after the opening line. A mutation that offers the recipe as a route *without* naming `$proposed` literally is **not** caught — see "Slice 2, mutation A" below. |
| 3 | Guard | Passes unmutated; fires when `human_msg` is made to branch. |
| 4 | Guard (predicate) | Passes unmutated on both halves; fires on both named wrong predicates. |
| 5 | Genuine RED | Fails on both assertions against unchanged code — `GIT_DIR` leak not cleared. |
| 6 | Genuine RED | Fails on both assertions against unchanged code — failed listing folded into emptiness. |

## Fixtures added

All four allocated ahead of the `trap`, same reason `$git_proj` already was
(`tests/hook-test.sh:56-66`): an unbound name in the trap body under `set -u`
aborts the trap before its `rm -rf`, leaking every temp dir it names, not just
its own.

- **`$git_tagged_proj`** — a real repo, one empty commit, tagged `v1.2.3`.
  Serves three roles: the steady-state half of slice 3's byte-identity check,
  the steady-state half of slice 4's predicate check, and — reused rather than
  duplicated — the "second fixture carrying v1.2.3" slice 5 points a leaked
  `GIT_DIR` at. Decided to reuse rather than build a fifth fixture: slice 5 only
  needs a real repository whose tag listing would answer STEADY if discovered,
  and this one already is exactly that, honestly, for the role it plays in
  slices 3 and 4.
- **`$git_vnext_proj`** — a real repo, one empty commit, tagged `vnext` and
  `v1.2` — two real tags, neither semver. Slice 4's discriminating half: an
  implementation keyed on `git tag --list 'v*'` emptiness sees two tags and
  answers steady-state wrongly; the intended semver-filtered predicate still
  answers initial-release.
- **`$guard_stub127_dir`** — a `PATH` stub directory holding a `git` that
  unconditionally `exit 127`s, prepended to `guard_path` for slice 6's one
  scenario only and restored immediately after, following the existing
  BSD-realpath scenario's pattern (`tests/hook-test.sh` around the
  `stubdir`/`guard_path` swap).

Tagging needs a commit, so `$git_tagged_proj` and `$git_vnext_proj` — unlike
`$git_proj`, which stays uncommitted on purpose — set `user.name`/ `user.email`
locally via `git -c` rather than depending on the invoking user's global git
config. Verified no stderr from any fixture-construction command: the unmutated
full-suite run below has empty `stderr=[]` on every `assert_deny`, and fixture
setup itself (`git init -q`, `git commit -q`, `git tag`) produced no output when
run standalone during construction.

`run_guard`'s third-parameter mechanism (`NAME=value` pairs), built ahead of
slice 5 in slice 1 and verified there as working end-to-end, is exercised for
the first time by a real scenario here: slice 5 passes
`"GIT_DIR=$git_tagged_proj/.git"`, an absolute path, avoiding any ambiguity
about whether `GIT_DIR` resolves relative to the pre- or post- `-C` cwd.

## Unmutated full-suite run

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
=== version-guard (v1.2.3 tag: steady-state wording) ===
=== version-guard (vnext/v1.2 tags only, no semver tag: initial-release wording) ===
=== version-guard (leaked GIT_DIR cleared: initial-release wording) ===
FAIL: version-guard git-dir-leak reason: never-released wording despite leaked GIT_DIR: expected to contain 'never been released', got 'plugin.json version edit refused: 1.2.3 -> 9.9.9.

The manifest version is the last released version. It is changed only by
'just release {patch|minor|major}', which validates state, bumps, commits,
tags, and pushes in one step. The release recipe also refuses if plugin.json
and the latest git tag disagree.

If the goal is to ship a release, invoke the recipe instead of editing this
file. Do not bypass this guard, modify the recipe, or alter version state by
other means.'
FAIL: version-guard git-dir-leak reason: no last-released wording despite leaked GIT_DIR: expected NOT to contain 'last released version', got (same text as above)
=== version-guard (git listing fails: steady-state wording, empty stderr) ===
FAIL: version-guard git-listing-failure reason: steady-state wording despite failed listing: expected to contain 'last released version', got 'plugin.json version edit refused: 1.2.3 -> 9.9.9.

This plugin has never been released -- no vX.Y.Z tag exists yet, so the
manifest is not tracking a previous release. It holds 1.2.3, which is
what the initial release will publish, verbatim. Which version a plugin
first ships as is the maintainer's call and their edit to make.

Do not bypass this guard, modify the recipe, or alter version state by
other means.'
FAIL: version-guard git-listing-failure reason: no never-released wording despite failed listing: expected NOT to contain 'never been released', got (same text as above)
=== check-version (MARKETPLACE_DIR unset: skip) ===
=== check-version (marketplace.json missing: skip) ===
=== check-version (no entry: skip) ===
=== check-version (in sync: pass) ===
=== check-version (drift: fail) ===

4 failure(s)
EXIT=1
```

Exactly four failing assertions, all attributable to slice 5 (2 assertions) and
slice 6 (2 assertions). Slice 1's three wording assertions, slices 2/3/4 in
full, and all fourteen pre-existing scenarios produce no `FAIL` line. A second
run after all four mutation-and-restore cycles below reproduces this transcript
byte-for-byte (`diff` empty).

## Slices 5 and 6 — current (wrong) behaviour, measured from this run

- **Slice 5.** With `GIT_DIR` leaked to `$git_tagged_proj/.git`, the tagless
  `$git_proj` fixture answers **STEADY** wording ("the last released version …")
  — the clearing the item requires does not exist yet, so the listing discovers
  the tagged repo through the leaked variable.
- **Slice 6.** With `git` stubbed to exit 127, the tagless `$git_proj` fixture
  answers **INITIAL** wording ("never been released … will publish …") — the
  failed listing is indistinguishable from an empty one, the inversion of the
  item's stated intent (a failed listing yields the steady-state wording).

Both match the slice-1 code review's prior measurement, reproduced independently
here rather than quoted.

## Mutation proofs — slices 2, 3, 4

Method per the dispatch: `cp` the SUT aside, edit in place, run
`bash tests/hook-test.sh`, restore from the copy, confirm the checksum. Full
transcripts are long (each failing assertion prints the whole reason text); this
section gives the failing-assertion labels only, which is what discriminates the
mutation. Restore-and-checksum was confirmed after every round below, not just
once.

### Slice 2

**Mutation A** — reinstated the exact prose the slice-1 code review removed
(`This plugin has never been released -- no vX.Y.Z tag exists yet. The first
release will publish whatever plugin.json holds when
'just release {patch|minor|major}' runs; …`), which offers the recipe as a
route to the proposed version *conceptually* but never prints the digits
`9.9.9`. Result: **not caught**. The full-suite failure set was identical to the
unmutated baseline (slice 5's two assertions, slice 6's two) — no new `FAIL`
line. This is a real, reportable gap in slice 2's literal-string check: it
catches a message that *names* the proposed version, not one that hands over the
same route in prose. The dispatch anticipated this by asking for a second
variant.

**Mutation B** — same initial-release branch, rewritten to interpolate
`$proposed` directly:
`Running the recipe now would publish $proposed as the first release.`. Result:
**caught**.

```
FAIL: version-guard no-tags reason: will-publish wording: expected to contain 'will publish', got 'plugin.json version edit refused: 1.2.3 -> 9.9.9. …'
FAIL: version-guard no-tags reason: proposed version not offered as a route after the opening line: expected NOT to contain '9.9.9', got '
```

(The `will-publish` failure is incidental to this mutation's wording choice, not
evidence for slice 2; the second line is slice 2's own assertion firing.)
Checksum after restore: `3a7e923a452966bfe5c87d9795806e39` — matches.

### Slice 3

Mutation: split `human_msg` on the same `release_tags` predicate so it differs
between branches (`… [initial release]` suffix on the tagless case). Result:
**caught**.

```
FAIL: version-guard systemMessage byte-identical across tagless and tagged fixtures: expected 'version-guard: blocked plugin.json version edit (1.2.3 -> 9.9.9) [initial release]', got 'version-guard: blocked plugin.json version edit (1.2.3 -> 9.9.9)'
```

No other new failures. Checksum after restore:
`3a7e923a452966bfe5c87d9795806e39`.

### Slice 4

**Mutation B1** — dropped the semver filter, keyed on `git tag --list 'v*'`
emptiness alone. Result: **caught**, on exactly the `vnext`/`v1.2` half:

```
FAIL: version-guard vnext-tags reason: never-released wording: expected to contain 'never been released', got '… -- steady-state text …'
FAIL: version-guard vnext-tags reason: no last-released wording: expected NOT to contain 'last released version', got (same)
```

No other new failures — the `v1.2.3` half (already tagged) is unaffected by this
mutation, as expected. Checksum after restore:
`3a7e923a452966bfe5c87d9795806e39`.

**Mutation B2** — keyed on repo-ness (`git -C "$project" rev-parse --git-dir`
succeeding) instead of reading tags at all. Result: **caught**, and more broadly
than the coverage node's slice-1-era table anticipated: `$git_proj` (slice 1's
own tagless fixture) is itself a real repository (`git init -q`, no tags), so
repo-ness answers steady-state for it too, not only for the `v1.2.3` and
`vnext`/`v1.2` fixtures. Measured directly (`git rev-parse --git-dir` on a
fresh, zero-commit `mktemp -d` repo exits 0). Full failure set under B2:

```
FAIL: version-guard no-tags reason: never-released wording: …
FAIL: version-guard no-tags reason: will-publish wording: …
FAIL: version-guard no-tags reason: no last-released wording: …
FAIL: version-guard vnext-tags reason: never-released wording: …
FAIL: version-guard vnext-tags reason: no last-released wording: …
```

(plus slices 5 and 6's baseline failures, unaffected by this mutation). So B2 is
over-determined here: caught by slice 1 itself as well as by slice 4's
`vnext`/`v1.2` half — not solely by the `v1.2.3` half the coverage node named,
which is a stronger result than that node's slice-1-only analysis predicted, not
a weaker one. Checksum after restore: `3a7e923a452966bfe5c87d9795806e39`.

## Lint

`bash -n tests/hook-test.sh`: OK. `shellcheck tests/hook-test.sh`: clean.
`tests/hook-test.sh` is 419 lines; the 400-line cap (`tests/docs-test.sh`)
applies to `docs/` and `plans/`, not `tests/`, so this is not a cap violation.

## Not run

`just precommit` was not run — RED mode edits only `tests/hook-test.sh`, and the
full gate includes `format-docs`/doc checks unrelated to this change; `bash -n`
and `shellcheck` above are the mechanical checks this dispatch asked for.
Nothing was staged or committed.
