# Item 1.4 — code review

Two defects found in `resume_preflight`'s new ladder, both fixed in
`toolkit/release.sh`. The `ls-remote` call count the test review could not
assert is **1 per branch, all four branches** — the design is met, and H2 is
ruled out by measurement. Suite green (56 scenarios, not 52 — see Mechanical),
`just precommit` green, nothing committed.

## 1. `release_tag_list=$(release_tags)` — the unread status. CONFIRMED, FIXED

The suspicion was right, and it is worse than a tidiness issue: the run does not
merely lose the hint, it loses the refusal.

**Semantics, measured** (`bash 5.2.37`): `set -e` is in force inside a
`git rev-parse … || { … }` group's body. A capture whose status goes unread
aborts the script there, with the failing command's own status:

```
script exit: 3          # from `x=$(boom)` inside the group, no further output
```

**End to end, measured** on a release-test-shaped fixture with a `git` shim that
fails `git tag --list` (status 128), running `release.sh --resume` on the virgin
`0.1.0` state:

```
=== scenario=virgin shim=tagfail rc=128 ===
fatal: simulated git tag failure
```

That is the whole output. No `hint:`, no
`error: no tag v0.1.0 for plugin.json version 0.1.0`. A clean, already-decided
refusal became a bare crash with git's exit status.

**Second reachable trigger**, also measured: a real (status 2) `grep` error
inside `semver_tags`. `semver_tags` absorbs only status 1, so status 2 leaves
the filter at 1, `release_tags` returns 1 under pipefail, and the group aborts
at exit 1 — indistinguishable from a clean refusal *except* that no `error:`
line is printed at all:

```
=== scenario=virgin shim=grepfail rc=1 ===
grep: simulated error
grep: simulated error
```

(Two lines: the first is `origin_release_tags`' filter, correctly absorbed by
`|| origin_tag_list=""`; the second is `release_tags`', fatal.)

Same defect class as the Item 1.2 slice 6 `jq` capture, and it contradicted the
block's own comment, which said a failed read is absorbed "into the empty case
instead of dying" — true of `origin_tag_list`, false of `release_tag_list`.

### The fix, and why not `|| release_tag_list=""`

Absorbing to empty — what the test review's variant A used — is the wrong
absorption, not merely a different one. Branch 3 is the only branch that makes a
positive claim about this plugin's history ("never released", so `just release`
with no bump). Feeding a *failed* listing into the empty case makes silence
assert that claim. That is exactly the read `semver_tags`' own comment forbids:
"an empty result is a value (no matching tags) and a real grep error still exits
non-zero. That distinction only reaches the caller if the caller reads the
status."

Dying instead (`release_preflight`'s shape) was also rejected: the refusal is
already decided, and replacing `no tag $tag …` with a probe-failure message
makes the run refuse *harder* for a reason that has nothing to do with why it
refused — the thing the block's first comment exists to prevent.

Landed shape — the status is read, and only a **successful empty** listing sets
the flag:

```bash
local origin_tag_list release_tag_list no_local_tags=0
origin_tag_list=$(origin_release_tags) || origin_tag_list=""
if release_tag_list=$(release_tags) && [ -z "$release_tag_list" ]; then
    no_local_tags=1
fi
```

Branch 3's test becomes `elif [ "$no_local_tags" = 1 ]`. A failed listing falls
to branch 4, whose advice is safe either way: `just release <bump>` on a plugin
that turns out never to have been released meets `release_preflight`'s
first-release refusal and its hint. The `if`-condition form matters — a bare
`release_tag_list=$(release_tags) && [ -z … ]` as a statement would itself abort
under errexit whenever the test is false.

Verified after the fix, both shims, both a virgin and a local-tags-present
fixture:

```
=== scenario=virgin shim=tagfail rc=1 ===
hint: no release was started at this version.
      run `just release <bump>` instead.
error: no tag v0.1.0 for plugin.json version 0.1.0
```

The comment now states the residual honestly, cross-referencing the errexit
argument already written at the `jq` capture rather than restating it.

### Every other capture the ladder introduced

- `origin_tag_list=$(origin_release_tags) || origin_tag_list=""` — status read.
  Correct, and it is the only `origin_release_tags` call in the function.
- `printf … | grep -qxF -- "$tag"` — the pipeline is an `if` condition, so its
  status is consumed and errexit is suppressed. A status-2 grep error there
  routes to branch 2, which still advises the fetch; no crash, no false "never
  released". Acceptable, and there is no third listing to read.

No other capture exists in the block.

## 2. `ls-remote` call count — 1 per branch. Design met; H2 ruled out

Counted, not read: a `git` shim on the fixture `PATH` logging every invocation
and `exec`ing the real git. Each row is one full `release.sh --resume` run.

| Branch | Fixture | `ls-remote` calls |
|---|---|---|
| 3 (virgin, empty origin) | tag dropped both sides, `$V`=0.1.0 | **1** |
| 1 (origin has `v$V`) | local-only `tag -d` | **1** |
| 2 (other semver on origin) | manifest advanced to 1.3.0 | **1** |
| 4 (local tag kept) | origin's tag deleted, `$V`=1.2.4 | **1** |
| 3 via **failed** probe | `remote remove origin` | **1** |

One read, reused by branches 1 and 2. No branch issues more than one.

The count discriminates, which is what makes it evidence rather than a
formality. The same measurement against variant **H2**
(`[ -n "$(origin_release_tags)" ]` in test context, the form test review §1.3
recorded as UNFIXABLE):

| Branch | H2 `ls-remote` calls |
|---|---|
| 3 virgin | 2 |
| 1 origin has `v$V` | 1 |
| 2 other semver | 2 |
| 4 local tag kept | 2 |
| 3 via failed probe | 2 |

And H2 passes the whole suite: **0 failures**, re-confirmed here. So §1.3's
claim holds exactly — output cannot separate A from H2, the call count can, and
the landed code is A. Test review §1.3 is **resolved, not a defect**.

## 3. Ladder variants C and I — the test review's loop closed

Both gap variants re-applied as throwaway mutations to the landed code and the
full suite run, then `release.sh` restored and `git diff --stat` verified.

- **C** (local-tags-present branch tested first): **3 failures**, all in
  `resume: origin's copy of v$V outranks a local tag this clone still has` —
  missing `git fetch --tags`, missing `just resume-release`, and
  `just release <bump>` present. Matches the test review's post-addition matrix
  (C=3).
- **I** (`origin_newest = $tag` instead of membership): **2 failures**, both in
  `resume: v$V among origin's tags counts even when a newer tag sorts above it`.
  Matches the matrix (I=2).

Landed code confirmed as variant **A**: origin checked before local, membership
rather than "is the newest".

## 4. Empty listing, BRE metacharacters, `grep -x`. FIXED with `-F`

Measured:

- `printf '%s\n' ""` yields one empty line; `grep -qx -- "v1.2.3"` does not
  match it. The branch falls through correctly.
- `grep -x` **does** treat the pattern as a BRE: `v1x2y3` matches the pattern
  `v1.2.3`. Confirmed directly.

Against a `semver_tags`-filtered listing that could not false-positive, and the
argument is tight rather than empirical: pattern dots are any-char, pattern
digits cannot match a `.`, and both pattern and candidate carry exactly two dots
— so a matching line's dot positions must equal the pattern's, and every other
position is a pattern literal. The two strings are therefore identical.
`v11.2.3` and `v1.2.30` were checked as the near misses; neither matches.

The residual is not the listing, it is `$tag`. `$V` is `jq -r .version` over a
maintainer-authored manifest, with nothing between the read and the grep that
constrains its shape. A manifest version holding a real metacharacter turns the
pattern into one that matches tags it does not name — `v.*` matches `v1.2.3`,
measured.

Rather than state that bound in a comment, it is removed: `grep -qxF`. `-F`
makes `$tag` a fixed string, `-x` still pins the whole line, and the empty-line
behaviour is unchanged. Zero cost, portable, and the four branch outputs are
byte-identical before and after.

## 5. Whitespace safety

- The origin listing is newline-delimited and consumed line-wise by `grep -x`.
  Nothing splits on spaces: `printf '%s\n' "$origin_tag_list"` is quoted, and
  the only other read is `[ -n "$origin_tag_list" ]`, also quoted.
- The `printf '%s\n'` round-trip is faithful for a multi-line listing — `od -c`
  over a three-tag value shows the newlines preserved exactly, with one trailing
  newline added. Membership matches on a middle line.
- Ref names cannot carry space, tab or newline (documented and verified at
  `origin_release_tags`' own comment), so the listing cannot contain a
  whitespace-bearing entry in the first place.
- Full suite re-run under `TMPDIR="…/space dir"` after the fixes:
  **0 failures**, so every fixture path, `PATH` entry and repo root contained a
  space.

## 6. Comment honesty — three corrected

1. Block header claimed a failed read "is absorbed into the empty case instead
   of dying" — true of the origin probe, false of the local listing, which read
   no status at all. Rewritten to cover both listings and to say which branch
   each failure is absorbed into.
2. Branch 3's comment asserted "this plugin has never been released". It now
   says "verified, not merely unread", which is what the flag actually
   establishes.
3. Branch 4's comment said "Local tags exist, just not this one". After the fix
   it is also the branch a *failed* listing reaches, and the comment now says so
   — and says why that is the right landing place.

The remaining comments in the block (branches 1 and 2, the `origin_tag_list`
capture) were checked against measured output and are accurate.

Comment density was itself an issue with my first draft: the block reached 58
comment lines to 25 of code (2.3:1) against `release_preflight`'s 1.1:1 and the
file's 1.03:1. Trimmed to 48:25 by cross-referencing the errexit argument
already present at the `jq` capture instead of restating it.

## 7. Hint quality, read on real fixtures

All four hints were read as emitted by a real `--resume` run, not from source.
Each is accurate and actionable; continuation lines are six spaces, matching
every other hint in the file (the only 8-space continuations in `release.sh` are
the nested path lists at `:126,130,196`, deliberately).

Two quality observations, **not applied** — both would change wording the
outline and runbook froze, and neither is a defect:

- **Branch 2 does not name the tag it found.** `release_preflight`'s analogous
  lost-tags hint names `$origin_newest`; this one says only "origin has release
  tags, but none matching v1.3.0". A maintainer whose manifest was hand-advanced
  past a real release would learn more from seeing `v1.2.3` named. Naming it
  costs one `sed -n '1p'` over the already-captured listing.
- **Branches 3 and 4 print a byte-identical first line** and differ only by
  `<bump>`. Their situations differ meaningfully (no release tag here at all,
  versus earlier releases but not this version), and nothing in the output says
  which one the maintainer is in. A clause each would disambiguate — but branch
  3 is also the failed-probe landing site, so any added clause must not claim
  origin was checked, and branch 4's wording is pinned by the runbook as
  "unchanged".

## 8. Split decision — recommendation: do not split

Current state of `toolkit/release.sh`:

| Measure | Value |
|---|---|
| Total lines | **791** (771 at `0c8d3ce`; +20 from this review) |
| Comment / code / blank | 391 / 380 / 20 |
| `common_preflight` | 124 lines |
| `release_preflight` | 176 lines |
| `resume_preflight` | 73 lines |
| Tag-listing helpers (`semver_tags`, `release_tags`, `origin_release_tags`) | 61 lines |

Growth across this run, by commit:

| Ref | Total | `common` | `release` | `resume` |
|---|---|---|---|---|
| `4264cb6` (Item 1.2/1) | 602 | 69 | 114 | 13 |
| `e1b872d` (Item 1.2/2-5) | 619 | 69 | 119 | 13 |
| `2e644c4` (Item 1.2/6) | 676 | 69 | 176 | 13 |
| `f5d7521` (Item 1.3) | 731 | **124** | 176 | 13 |
| `0c8d3ce` (Item 1.4) | 771 | 124 | 176 | **53** |
| worktree | 791 | 124 | 176 | 73 |

**Recommendation: hold. Do not split, now or at the Phase 1 boundary.**

Three reasons, in order of weight:

1. **The growth is not at the seam.** The tag-listing helpers a split would
   extract are 61 of 791 lines — 8% — and they have not grown since Item 1.2/1.
   What grew is the three preflights, +189 lines between them, and they cannot
   move: they share `$V`, `$tag`, `$first_release` and `$acted` as globals with
   the top-level flow. A split that removes 8% and leaves the actual growth in
   place buys a rounding error.

2. **A second file is a permanent shipped path.** `tests/dist-tree-test.sh`, the
   CLAUDE.md Layout list, `install.sh`'s vendoring and `update.sh`'s migration
   range all gain an entry, and every consumer vendors it forever. Prior reviews
   declined the seam for this reason and nothing has changed it. The outline
   already settled the same trade the other way for `version-guard.sh`, which
   duplicates the semver filter rather than source a shared helper — "a shared
   helper would be a new shipped path … for one `grep -E` line".

3. **Half the file is argument, and it belongs where it is checked.** 391 of 791
   lines are comment. Splitting by function moves comments with their code and
   reduces nothing a reader must hold, because the ordering constraints the
   comments spend most of their length justifying are *between* the functions
   (the probe before `check-version.sh`, before any side effect). This run found
   five comments asserting what the code did not do, three of them in this item.
   In-place is where that gets caught.

If size must come down later, the first unit to look at is `release_preflight`
at 176 lines — but its two halves are sequenced by side-effect ordering, and
separating them puts that argument in a third place. Prefer moving
*argument prose* to `docs/references/release-flow.md` with pointers over a
shipped split. Revisit only if a fifth preflight concern lands.

## 9. Mechanical

- `bash tests/release-test.sh`: **0 failures**, all scenarios pass.
- **The suite has 56 scenarios, not 52.** `grep -c '^=== '` over the run output
  and `grep -c '^echo "=== '` over the file both give 56; `f5d7521` had 50, so
  Item 1.4 added 6 net (four new slices plus the test review's two, slice 2
  being an in-place rewrite). The GREEN report's "all 52 scenarios pass" and the
  dispatch's done-criteria both carry the wrong count. Nothing is missing — the
  number is simply understated.
- `bash -n toolkit/release.sh` and `shellcheck toolkit/release.sh`: clean.
- `just precommit`: green — shellcheck, `bash -n`, `_import-check` (plain,
  widened, missing-gate), `tests/hook-test.sh`, `tests/release-test.sh`,
  `tests/update-plugin-dev-test.sh`, `tests/dist-tree-test.sh` (9 files, no
  gitlink), `tests/docs-test.sh`, `tests/doc-sync-test.sh`, `format-docs`.

### Correction owed to the GREEN report

`item-1-4-green.md` justifies the unguarded capture as "consistent with how the
rest of the file treats that call", citing "the codebase's existing comment
(`:277-282`)" as documenting `git tag --list` as essentially never failing. Both
halves are wrong. The comment cited is `release_tags`' own, which says nothing
about failure; the "essentially never fails" line is in `origin_release_tags`
(`:298-300`) and is a *contrast* drawn to justify capturing `ls-remote`'s status
— not a licence to drop `git tag --list`'s. And the rest of the file is not
consistent with it: `release_preflight:330` guards the same call with
`|| die "could not list this plugin's release tags — nothing was done"`. The
report is untracked and out of this dispatch's scope; flagged for the
orchestrator.

## State on exit

- Modified: `toolkit/release.sh` only (`+35 / -15`). `git status --porcelain`
  shows `M toolkit/release.sh` and the pre-existing untracked
  `plans/…/reports/item-1-4-green.md`, plus this file.
- **Nothing committed.**
- All throwaway mutations (C, I, H2, and the harness's failure shims) were
  applied against a byte copy and restored; `git diff -- toolkit/release.sh` was
  verified to show only the intended fix after each.
- `tests/release-test.sh` untouched. The `ls-remote | cut` captures at
  `:438,466,562` untouched. No other file touched.
- Scratch under `/tmp/claude-1000/i14cr/` — sandboxes and the spaced-TMPDIR tree
  deleted; nothing left in the repo root.
- Nothing UNFIXABLE. Test review §1.3's UNFIXABLE-at-the-test-level item was
  settled here by measurement, as it asked.
