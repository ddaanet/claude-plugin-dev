# Phase 1 boundary checkpoint — corrector report

**Scope:** `toolkit/release.sh`, `tests/release-test.sh`, `scripts/self-release.sh`,
`tests/self-release-test.sh` across `af72c2a..HEAD` (Items 1.1, 1.2, 1.3).
**Date:** 2026-09-20. **Mode:** review + fix.

## Verdict

**Ready.** M2, N1 and N2 are each satisfied by landed code, not merely by a
report's claim. The three items compose cleanly: the "absorbs a no-match grep's
status" hazard note has exactly one home (`semver_tags`), `release_tags` and
`origin_release_tags` each carry only their own site note and defer to it, and
`scripts/self-release.sh` states its failure modes in its own words with the
duplication argued as intentional.

Four issues found, **all fixed**: two comments asserting a mechanism that is
verifiably not the one the code uses, one fail-open status conflation in the
new `self-release.sh` filter, and two stale `<script>.sh:<line>` citations
standing in Phase-1-edited files. `just precommit` re-run in the foreground
after the fixes: green, closing line `ok`, all eight suites.

Nothing is UNFIXABLE. Nothing found required a design decision.

## Issues found

### Major

1. **`self-release.sh`'s new comment names the wrong mechanism for `dist-v*`**
   - Location: `scripts/self-release.sh`, `release_preflight`, the
     "Lists every v* tag and filters it down" block.
   - Problem: it claimed "the dist-v* lineage sorts as text after "v" and is
     dropped there, not by the glob" — the opposite of what happens.
     `git tag --list 'v*'` fnmatches from the start of the tag name, so
     `dist-v0.2.0` is never listed and never reaches the X.Y.Z filter.
     Measured directly in a scratch repo carrying `v0.1.0`, `vnext` and
     `dist-v0.2.0`: the listing is `vnext`, `v0.1.0`. The runbook's own Item
     1.3 note says the same ("the `v*` glob still excludes `dist-v*`"), so the
     landed comment contradicts the change that produced it. Same block: "the
     nearest tag of ANY name" overstates `describe --match 'v*'`, which is
     pattern-restricted — the `vnext` example survives, the claim does not.
   - Fix: restated — the filter's job is `vnext` and other non-release names
     the glob admits; the dist lineage never reaches it because the glob
     anchors at the start of the name.
   - **Status:** FIXED

2. **The filter folds a grep error into "no release tag yet"**
   - Location: `scripts/self-release.sh`, `release_preflight`,
     `latest_tag=$(grep -m1 -E … <<< "$tags") || latest_tag=""`.
   - Problem: `||` absorbs every non-zero status, not only grep's clean
     no-match 1. A real filter error (status 2) left `$latest_tag` empty, which
     skips the drift guard below and releases from whatever `toolkit/VERSION`
     holds over a listing the function could not read — the same fail-open
     class Item 1.1 exists to close, one stage further down the same function
     Item 1.3 rewrote. `toolkit/release.sh`'s `semver_tags` draws the
     distinction explicitly with `[ "$?" -eq 1 ]`; this site did not.
   - Fix: `|| { [ "$?" -eq 1 ] || die …; latest_tag=""; }`, with the reason in
     the comment. Status 1 keeps today's behaviour exactly; only a real error
     now refuses. Idiom probed for `$?` fidelity inside the group before
     applying, and the suite re-run.
   - **Status:** FIXED

### Minor

3. **The dist-squatting scenario's restated comment repeats mechanism 1**
   - Location: `tests/self-release-test.sh`, above the
     `tag dist-v0.2.0 already exists` scenario.
   - Note: Item 1.3's required restatement replaced a true reason (`describe
     --match 'v*'` ignores it) with a false one ("the X.Y.Z filter over the
     `v*` listing excludes it"). Rewritten to name the glob.
   - **Status:** FIXED

4. **Two `<script>.sh:<line>` citations left standing in Phase-1 files**
   - Location: `toolkit/release.sh` (`release.sh:780-785`, in the marketplace
     `jq -e` block) and `tests/release-test.sh` (`release.sh:138`, in the
     version-drift scenario's negative-assertion note).
   - Note: both predate Phase 1 and both are stale. `release.sh:780-785` did
     not point at the mode dispatch it names even at `af72c2a` (those lines are
     `bump_marketplace`'s commit-failure hint), and Phase 1's ~25 added lines
     moved the real dispatch further still. Converted to the convention this
     pass establishes: enclosing symbol plus a short quoted fragment.
   - **Consequence for Item 3.5:** its citation gate will now find **three**
     stale citations, not five. Both converted ones are outside
     `plans/`; no frozen dated artifact was touched.
   - **Status:** FIXED

## Fixes applied

- `scripts/self-release.sh` `release_preflight` — comment restated (glob vs
  filter, `describe --match` precision); grep status 1 separated from a real
  error, which now `die`s.
- `tests/self-release-test.sh` — dist-squatting comment restated.
- `toolkit/release.sh` `bump_marketplace`'s jq-parse note — line citation
  replaced by "the mode dispatch at the foot of this file … the `else
  resume_preflight` branch".
- `tests/release-test.sh` version-drift note — line citation replaced by
  "its own `tree_is_clean "."` guard".

Behaviour changed in exactly one place (fix 2, the error branch).
`just precommit` re-run in the **foreground** afterwards: green.

## Requirements

| Req | Status | Evidence in landed code |
|---|---|---|
| M2 | Satisfied | `toolkit/release.sh` `release_tags`: `listing=$(git tag --list 'v*' --sort=-v:refname) \|\| return 1` then `printf … \| semver_tags` — the listing's own status reaches the caller with no `pipefail` involvement. Both call sites unchanged: `release_preflight`'s `release_tag_list=$(release_tags) \|\| die "could not list this plugin's release tags …"` and `resume_preflight`'s `if release_tag_list=$(release_tags) && [ -z … ]`. Pinned by two scenarios run against a `set -eu` (pipefail-stripped) copy with a `git` wrapper failing only `tag --list`: the refusal fires, and on a `make_virgin` fixture the local tags, origin tags and `$GH_LOG` are all unchanged. |
| N1 | Satisfied | `resume_preflight` hint ladder: `grep -qxF -- "$tag" <<<"$origin_tag_list"` — no pipe, so no SIGPIPE for `pipefail` to promote. The cited in-repo precedent is real (`toolkit/version-guard.sh`, `release_tags="$(grep -E '…' <<<"$listing")"`). Pinned at both sizes; the ≥1 MB scenario measures the **post-filter** listing through the same `cut \| sed \| grep` chain `origin_release_tags` applies and asserts `≥1048576` bytes, so a later shrink of the fixture fails loudly instead of silently ceasing to exercise the hazard. |
| N2 | Satisfied | `scripts/self-release.sh` `release_preflight`: `tags=$(git tag --list 'v*' --sort=-v:refname) \|\| die …` then a first-match X.Y.Z filter over a here-string — no `git describe`. Pinned both directions: `vnext on ancestry` (v0.1.0 on `HEAD~`, `vnext` on `HEAD`) releases with no drift refusal, and `release tag off ancestry` (v0.9.0 on a deleted branch) still refuses naming `(v0.9.0)`, with the reachability split itself asserted in both directions so the fixture cannot silently collapse. |

## Cross-item checks that came back clean

- **`toolkit/release.sh` as one artifact.** The hazard note lives only on
  `semver_tags`; `origin_release_tags` defers to it in one sentence;
  `release_tags` states only its own site's property. The `Verified both ways
  (bash 5.2, git 2.47.3)` evidence line moved with its argument and is not
  duplicated. `ls_remote_sha` (untouched) already uses the capture-and-die
  shape and does not contradict the new text.
- **`self-release.sh` against `release.sh`.** The comment states its failure
  modes in its own words, and argues the three-line duplication from the file's
  own separation header rather than pointing at `release.sh`. No cross-file
  line citation was introduced.
- **The two suites as wholes.** Each new scenario opens with its own
  `new_sandbox`, so `$sandbox`, `$plugin`, `$GH_LOG` and `$GH_RELEASES` are
  fresh; no assertion reads a `$GH_LOG` truncated by a later sandbox; no
  scenario depends on the one before it. Each `git` wrapper computes
  `real_git` before prepending itself to `PATH` and restores `$saved_path`
  immediately after `run_in`, so no wrapper can shadow the next scenario's
  `command -v git`. The wrapper matches `ls-remote`/`tag --list` positionally
  on `$1`/`$2`; the one other `ls-remote` call site is `git -C … ls-remote`,
  which delegates to the real binary — checked, not assumed.
- **Whitespace safety.** Every capture and expansion added by Phase 1 is
  quoted. The one unquoted expansion, `$(seq 4 100003)`, splits by design and
  emits only digits and newlines; the comment says so. `cut -f2` over
  `ls-remote` output splits on TAB, and the residual is already documented on
  `origin_release_tags`.
- **Citations.** After fix 4, no `<name>.sh:<digits>`, `<name>.just:<digits>`
  or `justfile:<digits>` remains in any of the four files.

## Not flagged

The four `git`-wrapper stub blocks repeat ~10 lines of installation idiom
across scenarios. That matches the suites' existing convention of inline
per-scenario fixtures, and each body and its attached argument differ, so it is
not raised as a finding.

Scope OUT was honoured: nothing is reported about Item 2.1's four fixtures,
Phase 3's under-asserting refusals or `version-guard-test.sh`, Phase 4's prose
targets, `release.sh`'s comment volume, the `memory` gitlink, the staged
handoff files, or the ≥1 MB fixture's wall time.
