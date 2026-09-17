# Phase 2 checkpoint — Item 2.1 composed

Scope: `f2d5f25..24423ad`, the two files Item 2.1 touches —
`toolkit/version-guard.sh` and `tests/hook-test.sh`. Both read whole, not as a
diff.

## Verdict

The composed item meets its spec. Three defects found, all fixed in the working
tree; none of them was a wrong decision, and the governing exit-status invariant
is intact under every mutation tried.

The headline result is a coverage hole, not a code bug:
**the no-bypass property of both deny messages was entirely unasserted.**
Deleting the no-bypass sentence from either branch, or adding "disable the hook
in `.claude/settings.json` and retry the edit" to either, left the suite green.
That is the one thing the guard exists to hold, and it is prose, so only an
assertion holds it.

### Fixes applied (not staged, not committed)

1. **Major — `tests/hook-test.sh`: no assertion on the no-bypass property.**
   Four mutations survived (M15, M16, M17, M22 — table below). Added
   `assert_no_escape_hatch`, applied to both the initial-release and the
   steady-state reason: the no-bypass sentence must be present, and neither
   reason may name `settings.json` or `version-guard`. All four now die. The
   residual bound (a route described without naming a file still passes) is
   stated in the helper's comment.
2. **Major — `toolkit/version-guard.sh:99` cited `tests/hook-test.sh`.** Same
   class as the two plan-document citations already removed, and the same
   consequence: `tests/` is not in the dist tree, so a consumer reading the
   shipped hook is pointed at a file they do not have. Confirmed by
   `grep -rn "tests/\|outline\.md\|reports/\|plans/\|runbook" toolkit/` — after
   the fix the only remaining hit in the whole toolkit is
   `toolkit/release.sh:151`, which is known and out of scope. The justification
   the runbook asks for stays inline; only the path is gone.
3. **Minor — `tests/hook-test.sh:176-184`, `run_guard`'s doc comment was stale
   by composition.** Written in slice 1, it said "none of today's scenarios need
   one" of the extra-env mechanism and "every current call site passes no `$3`"
   — both made false by slice 5, which passes `GIT_DIR=…` at what is now `:372`.
   The second one matters beyond tidiness: it is the stated justification for
   the bash-3.2-safe array idiom. Corrected to name the one caller. Exactly the
   kind of drift a per-slice review cannot see.

Nothing else was changed. No other file was touched.

## Mutation testing

23 mutations, each applied to a clean copy of `toolkit/version-guard.sh`, suite
run, file restored from a pristine copy, hash re-verified before the next one.
The runner aborts on a restore mismatch; it never fired.

| # | Mutation | Verdict | First killing assertion |
| --- | --- | --- | --- |
| M1 | drop `[[ "$grep_status" -eq 1 ]] \|\| listing_failed=1` | KILLED | filter-failure: steady-state wording |
| M2 | else-branch collapsed to `release_tags=""` alone | KILLED | filter-failure: steady-state wording |
| M3 | listing failure folded into emptiness (`\|\| true`, no flag) | KILLED | git-listing-failure: steady-state wording |
| M4 | drop the whole `unset GIT_*` list | KILLED | git-dir-leak: never-released wording |
| M4b | unset everything **except** `GIT_DIR` | KILLED | git-dir-leak: never-released wording |
| M5 | predicate = `^v` (tag-list emptiness), not semver | KILLED | vnext-tags: never-released wording |
| M6 | `systemMessage` branches on release state | KILLED | systemMessage byte-identical |
| M7 | drop `2>/dev/null` on the listing | KILLED | Edit-bump: wrote to stderr |
| M8 | a statement inserted **before** `grep_status=$?` | KILLED | no-tags exit code 1, no stdout |
| M9 | drop `\|\| true` on the initial-release heredoc read | KILLED | no-tags exit code 1, no stdout |
| M10 | listing in a bare top-level substitution (errexit-live) | KILLED | Edit-bump exit code 128, no stdout |
| M11 | filter as `\|\| [ "$?" -eq 1 ]` (the outline's shape) | KILLED | filter-failure exit code 1, no stdout |
| M12 | branch swapped (initial-release when semver tags exist) | KILLED | no-tags: never-released wording |
| M13 | initial-release body names `just release` | KILLED | no-tags: names no recipe invocation |
| M14 | initial-release body offers `$proposed` as a route | KILLED | no-tags: proposed not offered as a route |
| M18 | `grep_status=$?` moved one line down | KILLED | no-tags: never-released wording |
| M19 | fold inverted to `-ne 0` | KILLED | filter-failure: steady-state wording |
| M20 | listing `if`/`else` branches swapped | KILLED | no-tags: never-released wording |
| M15 | no-bypass sentence deleted, initial-release body | **SURVIVED** → KILLED after fix 1 |  |
| M17 | no-bypass sentence deleted, steady-state body | **SURVIVED** → KILLED after fix 1 |  |
| M16 | `.claude/settings.json` escape hatch added, steady-state | **SURVIVED** → KILLED after fix 1 |  |
| M22 | `.claude/settings.json` escape hatch added, initial-release | **SURVIVED** → KILLED after fix 1 |  |
| M21 | restructure (a), fold ported to `-le 1` | SURVIVED — by design, see below |  |
| M23 | restructure (a), fold left at `-eq 1` | SURVIVED — by design, see below |  |

M21 and M23 are the structural probe the team lead asked for, not defects; M21
and M23 surviving means the restructure is suite-equivalent to what ships.

### M1's kill verified independently

M1 is the mutation the newest commit closed. Re-run here from a clean copy: it
dies on both filter-failure assertions. Its siblings were hunted and all die —
M2 (the whole fold and capture removed), M18 (the capture displaced by one line,
which is the failure mode the "must stay the first statement" comment warns
about), M19 (the comparison inverted), M20 (the listing's own branches swapped).
No surviving sibling.

### The exit-status invariant holds

The four mutations that re-open a fail-open path — M8, M9, M10, M11 — all die,
and they die the right way: `exit code: expected '0', got 1/127/128` with no
stdout, which is exactly the signature of the silent total bypass. M11 is the
shape `outline.md` originally prescribed and the contract report flagged as the
hazard for slice 6; the suite refuses it.

Every statement between the deny at `:80` and the `jq -nc` at `:183` is either
inside an `if` condition (errexit suspended), an `unset` (cannot fail on
unset-but-not-readonly names), an assignment, or a `read … || true`. The one
statement the contract report lists as pre-existing and unguarded — the final
`jq -nc` — is unchanged and remains out of scope.

## Composition against the Item 2.1 spec (runbook.md:271-327)

| Spec clause | Status |
| --- | --- |
| deny reason branches on the same predicate as `release.sh` | Yes — `^v[0-9]+\.[0-9]+\.[0-9]+$` and `git tag --list 'v*' --sort=-v:refname` are byte-identical to `release.sh:269,282` |
| listing runs only after the deny is established | Yes — deny at `:80`, listing at `:123` |
| clears repo-local `GIT_*` | Yes — M4/M4b both die |
| failed listing captured separately from an empty one | Yes — M3 dies |
| a failed listing yields the steady-state wording | Yes |
| `2>/dev/null` justification inline | Yes — `:96-100`, path citation removed by fix 2 |
| header comment restated for both cases | Yes — `:3-7` covers released and pre-release |
| initial-release branch keeps the no-bypass sentence, no escape hatch | Yes in code; **was unasserted** — fix 1 |
| accepted bound (non-repo dir nested in a repo) in a comment | Yes — `:101-103`, and measured: it answers STEADY |
| `unset $(git rev-parse --local-env-vars)` at the top of the suite | Yes — `:14` |
| `run_guard` gains a project arg defaulting to `$proj`, plus extra env | Yes — comment was stale, fix 3 |
| existing `$proj` scenarios pass unchanged | Yes — they are the listing-failure fallback and are green |

Slices 2, 3 and 4 ran as batched characterization guards, so their GREEN was
never proven by a failure against unchanged code. Checked by mutation, each is
load-bearing: slice 2 by M13 and M14, slice 3 by M6, slice 4 by M5. None is
decorative.

## Channel separation

`systemMessage` is a single unconditional assignment at `:176` and does not
branch; M6 confirms the assertion that holds that. `permissionDecisionReason`
carries both wordings, and neither offers a route the agent could authorise for
itself:

- initial-release names no recipe (M13 dies) and no version beyond the opening
  refusal (M14 dies) — it routes at the maintainer, which is a human, not a
  self-authorisation;
- steady-state names `just release {patch|minor|major}`, which is legitimate
  there and is the action a human takes.

Both now carry an asserted no-bypass sentence. The channels have not blurred.

## Shipped boundary

`toolkit/version-guard.sh` cites no plan document and, after fix 2, no
repo-internal path at all. The sweep over all of `toolkit/` leaves exactly one
hit — `toolkit/release.sh:151` (`decision 3, outline.md`), known and out of
scope.

## Whitespace and hostile input — run, not reasoned

All probes executed against the shipped script:

- **Project path containing spaces, a `$`, and single quotes**, tagless repo:
  `rc=0 decision=deny wording=INITIAL stderr=empty`. Same path tagged `v1.2.3`:
  `wording=STEADY`. Every expansion on the path is quoted.
- **Hostile tag names.** `git` itself refuses any tag containing a space or `*`.
  It accepts `v$(id)`, `` v`id` ``, `v1.2.3;id`, `v1.2.3&&id`, `v1.2.3|id`,
  `v$IFS`, `v1.2.3#c`, `v1.2.3'q'`, `v1.2.3"d"`, `v9/v1.2.3`. All were created
  and listed. No substitution, no injection, stderr empty: the listing is only
  ever fed to `grep` through a here-string and tested with `-z`. `v9/v1.2.3`
  correctly fails the anchored filter.
- **Non-repo project dir nested inside a `v3.0.0` repo**: `STEADY`, deny
  unchanged — the accepted bound the comment at `:101-103` documents, confirmed
  rather than assumed.
- `git` refuses a tag containing CR, so no tag name can break the line-oriented
  filter.

## The two open structural questions — recommendation only, not implemented

### (a) Restructure the filter's status capture

**Recommend doing it.** Evidence: ported as

```sh
grep_status=0
release_tags="$(grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' <<<"$listing")" || grep_status=$?
[[ "$grep_status" -le 1 ]] || { listing_failed=1; release_tags=""; }
```

the whole suite is green (M21), including the two failure scenarios, so it is
behaviour-preserving. What it buys is the removal of M18's entire class: today
`grep_status=$?` is correct only because it is positionally first in an
errexit-live branch body, a constraint that needs a five-line comment to state
and that a later editor can break by inserting one line. Under the `||` form
`grep_status` is assigned on every path and there is no `$?` to preserve. The
suite kills M18 either way, so this is defence in depth rather than a fix.

Two notes on the port. The fold must become `-le 1` (or `-gt 1`), because 0 is
now a reachable value of `grep_status` — but I measured the naive port that
leaves it at `-eq 1` (M23) and it is also green, and in fact observably
equivalent: when `grep` matches, `release_tags` is non-empty, so the final
predicate `[[ "$listing_failed" -eq 0 && -z "$release_tags" ]]` ignores
`listing_failed` entirely. So the `-le 1`/`-eq 1` choice is a readability
question, not a correctness one; `-le 1` says what is meant. Second, the `||`
must stay on the assignment — `{ …; }` grouping or splitting it across two
statements reintroduces the errexit exposure.

Cost: the `:` no-op and the "must stay the first statement" comment go away; the
comment block at `:106-122` needs one sentence rewritten, since it currently
explains the `if`-condition shape specifically.

### (b) Splitting `tests/hook-test.sh`

**Recommend not splitting it in Phase 2, and splitting by script-under-test when
it is done.** It is 498 lines after my fixes, past CLAUDE.md's soft 400. Two
things to weigh:

- No gate measures it (`tests/docs-test.sh` caps `docs/` and `plans/` only) and
  no hard-wrapping formatter runs over `tests/`, so the count is not yet the
  honest number CLAUDE.md's cap assumes. Roughly 45% of the file is comment, and
  that density is this repo's house style rather than padding.
- The natural seam is the script under test: the file already covers two, and
  the `check-version` scenarios (`:438-492`) are self-contained apart from
  `$proj` and `assert_eq`. Moving them to `tests/check-version-test.sh` leaves
  ~440 — still over, because the bulk is version-guard's own six fixtures and
  fourteen scenarios. A second cut inside version-guard (payload and path
  resolution vs. release-state wording) would land both halves near 220, but the
  two halves share `$proj`, `run_guard`, `assert_deny` and `assert_allow`, so it
  costs a sourced helper file — a new test-tree path and a fragmented read for a
  cap nothing enforces.

Doing it inside Phase 2 also means renaming the thing `just precommit` invokes
by name at `justfile:9` and `:11`, which widens a checkpoint into a refactor.
Better as its own item, where the helper extraction can be reviewed on its own
terms.

## Green

All run after the fixes, from `/Users/david/code/claude-plugin-dev`:

- `bash -n toolkit/version-guard.sh` — clean.
- `shellcheck toolkit/version-guard.sh tests/hook-test.sh` — clean.
- `bash tests/hook-test.sh` — 19 scenarios, `all hook scenarios passed`.
- `just precommit` — `ok` (import-check, release-test, update-plugin-dev-test,
  dist-tree-test, docs-test, doc-sync-test, format-docs all green).

## Mutation hygiene

Every mutation was applied to a copy restored from
`/tmp/claude-1000/p2c/version-guard.sh.pristine` and restored immediately after,
with `sha256sum` checked against the expected digest before the next run; the
runner exits 99 on a mismatch and never did. Final state, verified:

```
0404d9d1a33d11d45f0cbaf8e09f91431ce26fca1663456e2b17fda64912b5d2  toolkit/version-guard.sh
22e5b27c6854cc54a40f7d74d1026ef254a1a4c5902a7bc0f9cbe21c04a08e54  tests/hook-test.sh
```

`git status --porcelain -- toolkit tests` lists those two files as modified and
nothing else. Nothing is staged.
