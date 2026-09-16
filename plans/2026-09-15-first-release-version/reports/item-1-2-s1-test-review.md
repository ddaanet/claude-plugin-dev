# Item 1.2, slice 1 — test review

Verdict: the slice is genuinely red and pins what the runbook says it pins. One
change applied, to `lose_tag`'s signature and comment. Two runbook-assigned
discriminations (origin-tag identity, probe-before-`check-version.sh`) are
confirmed *not* pinned here — they belong to slices 2 and 4, and I did not
invent work for them.

## 1. Mechanical check

`bash tests/release-test.sh` against unchanged `toolkit/release.sh`
(`git diff --stat toolkit/release.sh` empty before and after each run). Five
failures, all inside this slice's two scenarios, every one of them a failed
assertion — no `ERROR` during setup, no scenario outside the slice moved. The
diff against `HEAD` is purely additive (43 insertions, 0 deletions before my
change), so no existing scenario is weakened, skipped or rewritten. The three
protected Phase-1 scenarios all appear in the run as passing headers with no
failure beneath them.

Verbatim, from the final run (after the change in section 6):

```
=== release: a first release refuses an explicit bump ===
=== release: a marketplace entry does not disqualify a first release ===
=== release: a marketplace entry does not exempt a first release from refusing a bump ===
=== release: an explicit bump on a lost local tag refuses as unverifiable, not as a first release ===
FAIL: lost-tag-bump names the fetch remedy: output did not contain 'git fetch --tags'
  --- output ---
check-version: in sync (1.2.3)
hint: a first release publishes the manifest version as-is — there is no
      previous release to bump forward from. Re-run with no bump argument
      to publish v1.2.3.
      to publish some other version instead, set .version in .claude-plugin/plugin.json
      to it and commit that edit, then re-run with no bump argument. That
      edit is the one the version-guard hook refuses from an agent: it is
      the maintainer who decides what a plugin first ships as.
error: 'patch' bump refused: this plugin has never been released
  --------------
FAIL: lost-tag-bump must not read as a first release: output contained 'never been released'
  --- output ---
[the same output, elided]
  --------------
=== release: a lost local tag with no bump argument refuses as unverifiable, not published as a first release ===
FAIL: lost-tag-no-bump names the fetch remedy: output did not contain 'git fetch --tags'
  --- output ---
check-version: no fixture entry in <sandbox>/marketplace/.claude-plugin/marketplace.json — skip
first release: publishing the manifest version 1.2.3 as-is (no bump)
tag: v1.2.3 created locally (manifest already at 1.2.3)
To <sandbox>/plugin-origin.git
   89abafc..7b8e731  main -> main
branch main: pushed
error: v1.2.3 on origin points at 8580c175…, not 7937ab41… — refusing to move a published tag
  --------------
FAIL: lost-tag-no-bump created no local tag: expected '', got 'v1.2.3'
FAIL: lost-tag-no-bump did not advance origin main: expected '89abafc5…', got '7b8e731b…'
=== release: non-semver v tags are not releases ===
=== release: a non-semver v tag above the release tag does not read as the latest ===
=== release: a non-semver v tag above the release tag does not suppress the drift check ===
=== release: tags with no marketplace entry is not a first release ===
=== release: a manifest ahead of the newest tag names the invariant it broke ===
=== release: a refused commit rolls the manifest back ===
=== release: a refused marketplace commit rolls the bump back and says what is public ===
=== release: a non-v tag nearer than the release tag does not read as the latest release ===
=== release: refuses a detached-HEAD marketplace before anything is published ===

5 failure(s)
```

Suite exit status 1. `bash -n` and `shellcheck` on `tests/release-test.sh` both
clean.

## 2. Mutation table

Seven throwaway implementations were written into `toolkit/release.sh`, the full
suite run under each, and the file restored from a pre-run copy immediately
after (verified: `git diff --stat toolkit/release.sh` empty). Each carries the
same `origin_release_tags()` the runbook specifies
(`git ls-remote --tags --sort=-v:refname origin | cut -f2 | sed 's|^refs/tags/||' | semver_tags`);
they differ only in where and how the refusal is taken.

| # | Mutation | Scen. 1 (`patch`) | Scen. 2 (no arg) | Rest of suite | Caught by slice 1? |
|---|---|---|---|---|---|
| M0 | Correct: probe first in `release_preflight`, any semver tag on origin, status captured | pass | pass | pass (0 failures) | — (baseline) |
| M1 | Probe fires only when origin carries `v$manifest_version`, not any semver tag | pass | pass | pass (0 failures) | **no** — slice 2's job |
| M2 | Correct probe, but placed *after* `check-version.sh` | pass | pass | pass (0 failures) | **no** — slice 4's job |
| M3 | Correct probe, but placed at the top of `push_branch` | fail (2) | fail (3) | pass | yes |
| M3b | Correct probe, but called after `bump_commit_tag` | fail (2) | fail (3) | pass | yes |
| M4 | Refusal with no origin guard: fires on any empty local listing | fail (2) | pass | **fail (20)** | yes, and loudly |
| M5 | Capture-rule violation: `[ -z "$list" ] && [ -n "$(origin_release_tags)" ]` | pass | pass | pass (0 failures) | **no** — slice 5's job |
| M6 | Correct probe, but inside the `first_release` branch *after* the explicit-bump refusal | **fail (2)** | pass | pass | yes, by scenario 1 alone |

Readings:

- **M6 is the one the runbook's "that absence is load-bearing" sentence is
  about, and it holds.** Scenario 1 is the only thing in the suite that catches
  a probe sitting behind the bump refusal: it fails on both `git fetch --tags`
  and `never been released`, while scenario 2 (no bump argument, so the refusal
  never fires) goes green. The absent-`never been released` assertion is doing
  real work, not decoration.
- **M3 / M3b collapse into a no-op rather than a late refusal**, which is worth
  recording: once `bump_commit_tag` has created the local tag, `release_tags` is
  non-empty, so a probe reading it there never fires at all. Both produce
  byte-identical failure sets to unchanged code. Scenario 2's
  `created no local tag` and `did not advance origin main` are what catch them;
  scenario 1 catches them too, via the bump refusal still firing first.
- **M4 is caught by the standing scenarios, not by this slice.** Scenario 1
  passes it, scenario 2 passes it, and 20 assertions across four pre-existing
  first-release scenarios fail
  (`a first release publishes the manifest version verbatim`,
  `a first release refuses an explicit bump`,
  `a marketplace entry does not disqualify a first release`,
  `non-semver v tags are not releases`). That is the right division: the "does
  not fire when origin genuinely has no tags" property is a standing contract,
  and the standing scenarios own it.
- **M1 and M2 are correctly out of scope.** In scenario 1 the manifest version
  and the lost origin tag are the same string `1.2.3`, so
  `assert_contains "$out" "v1.2.3"` cannot tell "names the origin tag" from
  "names the manifest version" — slice 2's `new_sandbox "1.3.0"` fixture, where
  the two differ, is what separates them. Likewise `check-version.sh` *passes*
  in scenario 1 (`in sync (1.2.3)`) and *skips* in scenario 2 (no entry), so
  neither fixture can observe the probe's position relative to it — slice 4's
  drift fixture is what does. No work to add here.
- **M5 and slice 5: slice 1's assertions are compatible and need no change.**
  Both scenarios run against a working origin, where the bare substitution
  yields the same value as the captured one. Slice 5 exercises a *broken* origin
  (bad URL, and no remote), a fixture slice 1 does not touch and does not
  constrain — nothing in these two scenarios would have to be rewritten for
  slice 5 to land. The gap is real and it is slice 5's to close, as the runbook
  assigns it.

## 3. The pass-today assertions

Judged against "could a plausible green implementation break this?", using the
mutations above as the evidence rather than reading.

| Assertion | Scenarios | Verdict |
|---|---|---|
| `rc` is 1 | both | **Keep, weak.** True today for the wrong reason in both. Never discriminating alone — the runbook says so — but a green that refused with exit 0 is a real (if unlikely) mistake and this is the only thing that would catch it. |
| output names `v1.2.3` | both | **Keep, weak in scenario 1, real in scenario 2.** In scenario 1 it is satisfiable by naming the manifest version (M1 passes it that way). In scenario 2 today's satisfier is `push_tag`'s die message — once the probe lands, only the hint can satisfy it. |
| `never been released` absent | scenario 1 | **Discriminating.** The sole catcher of M6. |
| `never been released` absent | scenario 2 | **Keep, weak.** No path in this fixture emits the phrase today and none of M0-M6 made it. Symmetry guard; cheap, so not worth removing. |
| `git tag --list 'v*'` empty | scenario 1 | **Keep, weak.** The refusal dies in `release_preflight` before any tagging under every mutation tried. It only becomes load-bearing if a future implementation moves the probe past `bump_commit_tag`, which scenario 2 already catches. |
| `git tag --list 'v*'` empty | scenario 2 | **Discriminating.** Fails today and under M3/M3b. |
| origin `refs/heads/main` unmoved | scenario 1 | **Keep, weak.** Nothing in scenario 1 reaches `push_branch` under any mutation tried. |
| origin `refs/heads/main` unmoved | scenario 2 | **Discriminating.** Fails today and under M3/M3b — this is the assertion that proves today's code *publishes* before refusing. |
| `$GH_LOG` empty | both | **Keep, weak.** Reachable only past `push_tag`, which the tag assertions already fence. Zero-cost; it states the refusal is side-effect-free, which is the property the slice is about. |
| marketplace untouched | scenario 1 | **Keep, weak.** Same reasoning; also partly tautological, since a first release at `1.2.3` against an entry already at `1.2.3` would be a no-op bump anyway. |
| marketplace untouched | scenario 2 | **Keep, real.** Here the entry does *not* exist, so a run that got as far as `bump_marketplace` would **create** one and the assertion would see `1.2.3` instead of `""`. Not tautological. |

Nothing in the list is noise worth deleting: the weak ones are one line each and
every one of them names a side effect the probe must not have.

## 4. The helper

`lose_tag` verified empirically against a live fixture rather than by reading
(script at `/tmp/claude-1000/s1probe.sh`, built from the suite's own helper
prologue so it exercises the real `new_sandbox`):

```
origin tag v1.2.3 refs before lose_tag: 1
local tags after lose_tag: []
origin tag v1.2.3 refs after lose_tag: 1
```

- **Does what its comment says.** Origin still advertises `refs/tags/v1.2.3`
  after the call; the local tag list is empty. The contrast with `make_virgin`
  (which also runs `git push origin :refs/tags/v1.2.3`) is real.
- **Fails loudly when the tag is absent.** A second `lose_tag "$plugin"` in a
  subshell gives `error: tag 'v1.2.3' not found.` on stderr and status 1; under
  the suite's `set -e` that aborts the run rather than continuing against a
  fixture that is not in the state the scenario claims. The `>/dev/null`
  redirects stdout only (git's `Deleted tag …` chatter), so the diagnosis
  survives.
- **No whitespace splitting.** Both `local` initialisers are quoted and both
  expansions are quoted at use. Verified against a repo path containing a space
  (`$sandbox/has space`): the tag is deleted, no error. A whitespace tag *name*
  is not a reachable case — `git tag "spaced tag"` is refused by git itself
  (`fatal: 'spaced tag' is not a valid tag name.`).

## 5. Fixture honesty

The "one unpushed commit on `main`" was verified live in both fixtures, not
assumed:

```
--- scenario 1 fixture: new_sandbox 1.2.3 ---
local HEAD=ba0b31ea…
origin main=96a8b319…
origin behind by: 1 commit(s)
--- scenario 2 fixture: new_sandbox '' ---
origin tag v1.2.3 refs: 1
local tags: []
origin behind by: 1 commit(s)
market_version: []
```

Origin really is behind in both, so `did not advance origin main` is a guard
that something could fail — and does fail, today, in scenario 2. Not a false
guard. Scenario 2's `market_version` baseline of `""` was confirmed too, so the
`assert_eq … ""` is comparing against the fixture's actual starting state.

## 6. What I changed, and why

One change, to `lose_tag`'s signature and comment
(`tests/release-test.sh:215-225`):

```sh
local repo="$1" tag="${2:-v1.2.3}"
```

was `local repo="${1:-$plugin}" tag="${2:-v1.2.3}"`.

The `$1` default was unusable: shellcheck's SC2119 fires on the bare `lose_tag`
call, which is why both call sites already pass `"$plugin"` explicitly (the RED
report records discovering this). A documented default that no caller may take
is a false affordance in a helper three more slices will read before writing
against it. `$1` is now required — a caller that forgets it gets
`$1: unbound variable` under `set -u`. The `$2` default stays; slices 3 and 4
need the tag parameter.

The comment gained the two facts I had to establish empirically, so the next
slice does not have to: that `$1` is required on purpose, and that deleting an
absent tag aborts the run rather than passing silently.

No call site changed. `shellcheck` and `bash -n` still clean; the suite still
fails exactly the same five assertions (re-run in section 1 is the post-change
run).

Nothing else touched. In particular I did not add scenarios for the origin-tag
identity (slice 2), the probe's position relative to `check-version.sh` (slice
4) or the failed-listing case (slice 5).

## 7. Noted, not acted on

- `assert_contains` greps its needle as a BRE, so `v1.2.3` also matches
  `v1X2X3`. Harmless against these messages, and the helper is shared with the
  whole suite — changing it to `grep -qF` is a suite-wide change, out of this
  slice's scope.
- `tests/release-test.sh` is past the 400-line cap. Recorded open item, out of
  scope per the dispatch.

## State on exit

- `toolkit/release.sh` — **untouched**. `git diff --stat toolkit/release.sh` is
  empty; every mutation was restored from `/tmp/claude-1000/orig-release.sh` by
  the runner immediately after each suite run, and the final state was
  re-verified after the last run.
- `tests/release-test.sh` — modified and uncommitted (the RED dispatch's two
  scenarios and `lose_tag`, plus the section-6 change).
- **Nothing committed.** No other file in the repo was written except this
  report and the "Amended by the test review" section appended to
  `plans/2026-09-15-first-release-version/reports/item-1-2-s1-red.md`.
