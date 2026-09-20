# Review: Item 1.1 slice 1 — GREEN-phase code (`b68cede`)

**Scope**: `toolkit/release.sh` as changed by `b68cede` — `release_tags`,
`semver_tags`, `origin_release_tags` and their comments, plus the two call sites
`release_preflight` and `resume_preflight` (verified unchanged). **Date**:
2026-09-20 **Mode**: review + fix

## Summary

The implementation matches the item's Change clause by clause: `release_tags` is
capture-then-filter with `|| return 1`, `local listing` is declared on its own
line so the capture's status is not masked, both call sites are untouched, and
the moved hazard note now lives on `semver_tags`. M2 is satisfied and verified
empirically with `pipefail` off. Two comment defects were found and fixed — a
paragraph on `semver_tags` whose middle clause asserted the opposite of its own
argument, and a circular cross-reference between `release_tags` and
`origin_release_tags`.

**Overall Assessment**: Ready

## Clause-by-clause verification

### 1. Capture-then-filter with `|| return 1`

```sh
local listing
listing=$(git tag --list 'v*' --sort=-v:refname) || return 1
printf '%s\n' "$listing" | semver_tags
```

`return`, not `die` — correct: a `die` would run in the caller's command
substitution subshell and print a second `error:` line into `resume_preflight`'s
deliberately non-fatal hint ladder without aborting the script. No pipe from
`git tag --list`. Matches `origin_release_tags`'s shape.

### 2. Interfaces contract and both call sites

- `release_preflight` (`release.sh`, `release_tag_list=$(release_tags) \`) still
  carries
  `|| die "could not list this plugin's release tags — nothing was done"`,
  unchanged, and still correct: `release_tags` now returns 1 from the capture
  rather than relying on `pipefail`, so the `die` fires on strictly more
  failures than before, never fewer.
- `resume_preflight`
  (`if release_tag_list=$(release_tags) && [ -z "$release_tag_list" ]; then`)
  unchanged. A failed listing leaves `no_local_tags=0` and falls through to the
  last branch, exactly as its comment requires ("whose advice is safe either
  way").
- A status-2 grep error inside `semver_tags` still reaches the caller: the
  filter returns 1, and with `pipefail` the pipeline's status is the filter's.
  The `resume_preflight` comment's claim about that path survives.

Verified empirically with the functions extracted from the file (lines 286-330)
and a `git` stub failing `tag --list`, run under `set -eu` (pipefail stripped):

```
stub fail
GOOD: release_tags returned nonzero with pipefail OFF
```

### 3. Empty-listing case — status 0, not 1

`local listing` is on its own line, so the trap where `local x=$(…)` makes `$?`
the status of `local` rather than of the substitution does not apply here; the
bare assignment's status is `git tag --list`'s.

Probed in a fresh tagless repo, then with tags added:

```
status=0 stdout_bytes=0
release_tags status 0 on tagless repo
--- now with tags ---
status=0 stdout_bytes=21
v1.10.0
v1.2.3
v1.0.0
```

Tagless: status 0 with empty stdout, so `first_release` handling is intact
(`printf '%s\n' ""` emits one empty line, `grep` matches nothing, status 1 is
absorbed, and `$( )` strips the trailing newline so `[ -z … ]` holds). With
tags: newest-first order preserved and `notsemver` dropped.

### 4. Comment placement

Correct as committed: the no-longer-depends-on-`pipefail` note sits on
`release_tags`; the "absorbs a no-match grep's status" hazard note is now the
single home on `semver_tags`; `origin_release_tags` keeps only the ls-remote
reaches-the-network argument; the `Verified both ways (bash 5.2, git 2.47.3)`
line travelled onto `semver_tags` and sits immediately after the argument it
supports, not orphaned. Two defects in the moved prose are fixed below.

### 5. Whitespace safety

No splitting introduced. `printf '%s\n' "$listing"` is quoted; `$listing` is
never word-split or globbed, and `IFS` is irrelevant to the pipeline. Ref names
cannot contain space, tab or newline (git refuses all three), and the existing
note on `origin_release_tags`'s `cut -f2` states that residual.

### 6. Citation convention

No `<script>.sh:<line>` citation introduced anywhere in the edited region (lines
286-358). `rg '\.sh:[0-9]+'` over the file finds exactly one hit, at line 254
(`# (release.sh:780-785)`), which is outside the edited region and untouched by
this change — it belongs to the later citation item, not here, and is not
flagged.

## Issues Found

### Critical Issues

None.

### Major Issues

None.

### Minor Issues

1. **`semver_tags`'s moved paragraph asserted the opposite of its own argument**
   - Location: `toolkit/release.sh`, `semver_tags()`, the paragraph beginning
     "Both release_tags and origin_release_tags capture their listing"
   - Problem: the middle clause read "…rather than piping the listing command
     straight in — so this absorbed status 1 is the only place either caller's
     safety **would be at risk** from a listing failure hiding behind an
     empty-input success here." Having just said both callers capture, it then
     located a live risk in the very design that removes it, and the
     self-reference ("here") made the sentence circular. The hazard being
     documented is the *counterfactual* one: were a caller to pipe, this
     filter's exit 0 on empty input would hide the listing's failure.
   - Fix: rewrote the paragraph to state the counterfactual directly — the
     absorption is *why* neither caller pipes — keeping the pipefail argument
     and the evidence line verbatim and in place.
   - **Status**: FIXED

2. **Circular cross-reference between the two listing functions**
   - Location: `toolkit/release.sh`, `origin_release_tags()`, "…the same shape
     release_tags uses"
   - Problem: `release_tags`'s new comment points at `origin_release_tags` ("the
     same shape origin_release_tags uses", required by the item), and
     `origin_release_tags` was edited to point back at `release_tags`. Neither
     end anchors the argument, which now lives on `semver_tags`.
   - Suggestion: point `origin_release_tags` at `semver_tags`'s comment instead
     — the same referencing idiom `resume_preflight` already uses ("the
     fail-open read semver_tags's comment warns against").
   - **Status**: FIXED

3. **Comment line over the file's comment wrap**
   - Location: `toolkit/release.sh`, `origin_release_tags()`, "release_tags
     uses, rather than piping it straight into cut/sed/semver_tags." — 81
     columns, where every other comment line in the file wraps at or under 79
   - Note: reflowed as part of fix 2. No line in 286-358 now exceeds 79.
   - **Status**: FIXED

## Fixes Applied

- `toolkit/release.sh` `semver_tags()` (lines 295-305) — rewrote the moved
  hazard paragraph so it states the counterfactual it means: the absorption is
  why neither caller pipes; a piped listing's failure would hide behind this
  filter's exit 0 on empty input, and only `pipefail` would carry it. The
  `Verified both ways (bash 5.2, git 2.47.3)` line is unchanged and still
  directly follows that argument.
- `toolkit/release.sh` `origin_release_tags()` (lines 347-349) — replaced the
  back-reference to `release_tags` with a reference to `semver_tags`'s comment,
  where the shared argument now lives; reflowed to ≤79 columns.

No code lines were changed by this review — the fixes are comment-only.

## Mutated-SUT run

Mutation: restored the pipe body in `release_tags` —
`git tag --list 'v*' --sort=-v:refname | semver_tags` — leaving comments and
everything else untouched, in place. Tests were not relocated.

`bash tests/release-test.sh` (foreground), tail:

```
=== the origin probes fail closed with pipefail stripped ===
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
EXIT=1
```

The slice-1 scenario redded on two assertions — the `die` message and the
absence of the lost-tags hint. Note for the record, since it bears on what the
scenario proves: its third assertion, `assert_eq "$rc" "1"`, stayed green under
the mutation, because the fixture's origin holds tags and the lost-tags guard
refuses anyway. Exit status alone does not discriminate here; the two message
assertions are what carry the detection, and they do. (The test file itself is
out of this dispatch's scope — reviewed in `item-1-1-s1-test-review`.)

**Restore confirmed.** The file was copied to `$TMPDIR` before mutating and
copied back afterwards; `git diff --quiet -- toolkit/release.sh` printed
`RESTORED: git diff --quiet clean` (exit 0) against the unmodified commit,
before this review's own comment fixes were applied.

## Post-fix verification

- `shellcheck toolkit/release.sh` → clean
- `bash -n toolkit/release.sh` → clean
- `bash tests/release-test.sh` (foreground) → `all release scenarios passed`,
  exit 0, including `pipefail-stripped release_tags failure refuses`
- No line in `toolkit/release.sh` 286-360 exceeds 79 columns

Nothing was committed; `toolkit/release.sh` is left modified in the worktree for
the orchestrator. `.claude/handoff-*.md` and the `memory` gitlink were not
touched.

## Requirements Validation

| Requirement | Status | Evidence |
|-------------|--------|----------|
| M2 | Satisfied | `release_tags()` returns non-zero on a failed `git tag --list` under `set -eu` with `pipefail` stripped — probed directly with a failing `git` stub, and asserted by the committed scenario |

## Positive Observations

- `local listing` declared separately from the assignment — the one subtlety
  that would have silently broken the contract, and it is right.
- The moved hazard note genuinely belongs on `semver_tags`: the absorption is
  the filter's property, and after this change neither caller can demonstrate it
  locally.
- `origin_release_tags`'s ls-remote-specific argument was correctly kept where
  it was rather than moved wholesale.
- The evidence line travelled with the argument it supports instead of being
  dropped as "already proven".

## Refactoring signals

None. No module split or new abstraction is warranted by this change.
