# Item 1.3 / Slice 2 — test review

**Scope:** `tests/self-release-test.sh`, the new
`=== release tag off ancestry still triggers drift guard ===` scenario, plus
`reports/item-1-3-s2-red.md`. **Date:** 2026-09-20 **Mode:** review + fix

## Verdict

**Ready.** The scenario is genuine evidence: green on the current tree, and
under the item's named mutation both its assertions fail on values (exit status
`1` vs `0`, and the missing refusal string), with the captured `$out` showing a
full release running to completion — the guard was skipped, which is precisely
the defect slice 1 fixed. The RED report's claims reproduced verbatim.
`scripts/self-release.sh` ends byte-identical (`git diff --quiet` exit 0).

One major gap fixed: the fixture asserted its reachability split by construction
only. Three fixture guards now pin it, because a collapsed fixture would make
the scenario pass under the mutation it exists to reject.

## Issues found

### Major

1. **The reachability split was unpinned — collapse would be silent, and
   vacuous**
   - Location: `tests/self-release-test.sh`, the `ancestry` scenario, between
     `git branch -q -D abandoned` and `run minor`
   - Problem: the scenario's whole discriminating property is that `v0.9.0` is
     *not* reachable from `HEAD` while `v0.1.0` is. Nothing checked it. Were a
     future edit (or a git behaviour change around `checkout -b` / `branch -D`)
     to leave `v0.9.0` on `HEAD`'s ancestry, `git describe` would answer
     `v0.9.0` too — the drift guard would refuse naming `v0.9.0`, both
     assertions would pass, and the scenario would go green under the very
     implementation shape it exists to reject. That is the "fixture unreachable
     from the write path" shape inverted: a fixture whose defining property can
     quietly stop holding.
   - Fix applied: three guards, a positive and a negative over the same fixture,
     each acting as the other's control for `merge-base --is-ancestor`'s
     polarity:
     ```sh
     assert_tag v0.9.0 local "ancestry fixture"
     git -C "$repo" merge-base --is-ancestor v0.1.0 HEAD \
         || fail "ancestry fixture: v0.1.0 is not reachable from HEAD"
     if git -C "$repo" merge-base --is-ancestor v0.9.0 HEAD; then
         fail "ancestry fixture: v0.9.0 is reachable from HEAD"
     fi
     ```
     The `assert_tag` line also closes `--is-ancestor`'s error-status hole: a
     vanished or unresolvable `v0.9.0` exits `128`, which the `if` reads as "not
     an ancestor" and would pass silently. `v0.1.0`'s reachability is
     load-bearing too — it is what makes the mutation *proceed* rather than
     refuse for some other reason, so the mutation's shape depends on it. The
     negative guard is written as `if … then fail; fi` rather than
     `cmd && fail`, which under the file's `set -euo pipefail` would abort the
     suite on the passing path.
   - **Status: FIXED**

### Minor

1. **The RED report's quoted snippet now under-quotes the scenario**
   - Location: `reports/item-1-3-s2-red.md`, "What was written"
   - Note: the snippet predates the three fixture guards above.
   - **Status: DEFERRED** — a dated write-time record is correct because it is
     dated; this review is its companion record and carries the final form.

## Checks that passed

- Green on the current tree, new scenario included (run 1 below).
- FAILs on assertions, not errors, under the named mutation (run 2).
- The mutated failure is the *right* failure: `$out` shows the release
  publishing `v0.2.0` end to end, so the guard passed and the release proceeded
  — not an unrelated preflight refusal.
- The unmutated pass is the *right* pass: `assert_contains` pins
  `does not match latest tag (v0.9.0)`, naming the off-ancestry tag rather than
  "some drift". `(` `)` are literal in BRE, so the parenthesised version is
  matched as written.
- `v0.1.0` kept, per the runbook's closing sentence;
  `require_prior_release_published`'s prior-tag path is intact and untouched.
- No other scenario disturbed: the diff is one contiguous insertion between
  slice 1's `vnext` scenario and
  `=== an unfinished release refuses a new one ===`. Slice 1's scenario, the
  dist-tag-squatting comment, and the four fixtures Item 2.1 will strengthen are
  unmodified — `git status` shows `tests/self-release-test.sh` as the only
  changed file under `tests/`.
- Whitespace safety: no unquoted expansion and no whitespace splitting in the
  added lines; every `$repo` / `$out` reference is quoted.
- Citation convention: the added comment cites no `<script>.sh:<line>`; it names
  behaviour (`describe`, the drift guard) in prose.
- `bash -n` and `shellcheck tests/self-release-test.sh` clean.
- `scripts/self-release.sh` restored byte-for-byte;
  `git status --short -- scripts/` empty.

## My own run output

### 1. Baseline — current tree, unmutated

```
$ cd /Users/david/code/claude-plugin-dev && bash tests/self-release-test.sh
=== happy path: minor bump publishes everything ===
=== bump arithmetic ===
=== vnext on ancestry is not the latest tag ===
=== release tag off ancestry still triggers drift guard ===
=== an unfinished release refuses a new one ===
=== resume finishes it ===
=== resume is idempotent ===
=== resume after later work on main ===
=== a partially published release still refuses a bump ===
=== resume refusals ===
=== never moves a published tag ===
=== preflight refusals ===
=== an unreadable origin refuses rather than proceeds ===
self-release.sh: ok
EXIT=0
```

### 2. Mutated in place — `release_preflight` reverted to `git describe`

```diff
-    tags=$(git tag --list 'v*' --sort=-v:refname) || die "git tag --list failed"
-    latest_tag=$(grep -m1 -E '^v[0-9]+\.[0-9]+\.[0-9]+$' <<< "$tags") || latest_tag=""
+    latest_tag=$(git describe --tags --abbrev=0 --match 'v*') || latest_tag=""
```

Run with the fixture guards in place (abridged to the two scenarios; the
remaining eleven sections ran and were silent):

```
=== vnext on ancestry is not the latest tag ===
FAIL: vnext: exit status: expected '0', got '1'
FAIL: vnext: local tag v0.2.0 missing
FAIL: vnext: no drift refusal: output contained 'does not match latest tag'
  --- output ---
hint: toolkit/VERSION holds the LAST released version. `just release` bumps from there.
      revert any manual VERSION bump and re-run.
error: toolkit/VERSION (0.1.0) does not match latest tag (vnext)
  --------------
=== release tag off ancestry still triggers drift guard ===
FAIL: ancestry: exit status: expected '1', got '0'
FAIL: ancestry: names off-ancestry tag: output did not contain 'does not match latest tag (v0.9.0)'
  --- output ---
VERSION + tag: v0.2.0 created locally
dist tag dist-v0.2.0: created locally
To /tmp/claude-1000/tmp.sMyw3Zi6NO/repo-origin.git
   7de5e8c..edd7693  main -> main
branch main: pushed
...
github release v0.2.0: created
Release v0.2.0 complete (consumers pull dist-v0.2.0)
  --------------
5 self-release check(s) failed
EXIT=1
```

No fixture-guard FAIL appears — the split holds; the two scenario assertions are
the only ones this slice contributes, and both fail on values. Both slices go
red under the one mutation, as the runbook predicts.

### 3. Restore and re-run

```
$ cp "$TMPDIR/self-release.sh.orig" scripts/self-release.sh \
    && git diff --quiet -- scripts/self-release.sh \
    && echo "RESTORE_OK: git diff --quiet exit 0"
RESTORE_OK: git diff --quiet exit 0
$ git status --short -- scripts/     # (no output)
$ bash tests/self-release-test.sh
… all thirteen sections silent …
self-release.sh: ok
EXIT=0
```

## Not run

`just precommit` — the orchestrator owns the commit and its gate; nothing was
committed and no branch was touched.
