# Deliverable review — test suites (Layer 1)

Scope: `tests/release-test.sh`, `tests/version-guard-test.sh`,
`tests/check-version-test.sh`, `tests/hook-test.sh` (deleted),
`tests/self-release-test.sh`, over `6550fb7~1..HEAD`.

Method: read every suite in full, read `outline.md` and `runbook.md` in full,
read `toolkit/release.sh`, `toolkit/version-guard.sh`,
`toolkit/check-version.sh` and `scripts/self-release.sh` for the code the
assertions pin. Cheap probes only: `shellcheck -S style` on all four suites
(clean), one `git diff --quiet HEAD` pathspec probe in a scratch repo, and
`git show 6550fb7~1:tests/hook-test.sh` for the split comparison.
**No suite was executed.** Every "would pass / would fail" claim below is
derived from reading the script under test unless it says "probed".

Headline: the plan's own deliverables (`release-test.sh`,
`version-guard-test.sh`, the `hook-test.sh` split) conform closely — every
enumerated scenario is present, the three load-bearing negatives are written,
and several scenarios exceed their contract with ordering and
membership-vs-newest guards that the runbook did not ask for. The defects are
concentrated in `self-release-test.sh`, the follow-up work outside the plan's
outline, which carries two tests that cannot fail.

## Critical

None.

## Major

### M1. `self-release-test.sh:267-271` — the `.claude/` exclusion test is vacuous

Axis: vacuity.

```sh
mkdir -p "$repo/.claude"
printf 'task frame\n' > "$repo/.claude/handoff-task.md"
run minor
assert_eq "$rc" 0 ".claude/ is excluded from the clean check"
```

The frame is written **untracked**. `scripts/self-release.sh:56` is
`git diff --quiet HEAD -- . ':(exclude).claude' ':(exclude)memory'`, which sees
tracked paths only. Probed in a scratch repo: with an untracked
`.claude/handoff-task.md` present, that command exits 0
**both with and without** the `':(exclude).claude'` pathspec.

Concrete wrong implementation that still passes: delete `':(exclude).claude'`
from `scripts/self-release.sh:56` outright. The assertion stays green, and the
suite no longer guards the exclusion it names.

`tests/release-test.sh` already solved exactly this, and documents why, at
`tests/release-test.sh:179-192` (`stage_handoff_frame`): "*`git diff HEAD` sees
only tracked paths — an untracked frame never reached the check in the first
place*", hence commit-then-rewrite-and-stage. The self-release fixture needs the
same shape. The `memory` half of the same comment (`self-release-test.sh:267`)
has no fixture at all — the gitlink-ahead-of-HEAD state is never constructed, so
`':(exclude)memory'` is entirely uncovered.

### M2. `self-release-test.sh:210-222` — "resume after later work" never runs a split, and its comment claims it does

Axis: vacuity, specificity.

```sh
new_sandbox; block_push; run minor; unblock_push
commit_in_repo docs.md "written after the release commit"
run --resume
assert_tag dist-v0.2.0 origin "resume after work"
assert_eq "$(git -C "$repo" show dist-v0.2.0:VERSION)" "0.2.0" "resume after work: dist VERSION"
```

`ensure_dist_tag` (`scripts/self-release.sh:183-184`) short-circuits on
`refs/tags/$dist_tag` existing locally. The blocked `run minor` already created
`dist-v0.2.0` locally, so the `--resume` here takes the "already created
locally" branch and **`git subtree split` never runs**. The
`show dist-v0.2.0:VERSION` assertion therefore re-reads a tree cut before the
later commit existed; it is green by construction.

The comment is worse than the gap:
"*What it proves is that the split ran against the tagged commit at all*" is
false — no split ran. It also concedes "*docs.md is outside toolkit/*", which
means even if a split had run from `HEAD` the tree would be identical.

Consequence:
**nothing in the suite discriminates split-from-tag from split-from-HEAD.** The
happy path (`:143-162`) splits when `HEAD` *is* the tagged commit, so it cannot
either. Mutate `self-release.sh:203` to
`git subtree split -q --prefix=toolkit HEAD` and the whole suite stays green.

Fix shape: the later work must land **inside `toolkit/`**, and the local dist
tag must be absent when resume runs (`git tag -d dist-v0.2.0` after the blocked
bump, as the dead-origin scenario at `:325` already does), then assert
`git show dist-v0.2.0:` does not carry the later file.

### M3. `self-release-test.sh` — refusal scenarios assert a message and nothing else

Axis: coverage, specificity. Brief item 2.

Nine refusals assert neither the exit status nor any absence of side effect.
`$GH_LOG` is never asserted empty anywhere in this suite, so no refusal is
pinned as having happened before `gh` was reached — unlike `release-test.sh`,
which asserts it on essentially every refusal.

| Site | Asserts | Missing |
|---|---|---|
| `:231-235` no dist tag on origin | message, `refute_tag` | `rc` |
| `:244-249` resume, no tag anywhere | two messages | `rc`, tag absence |
| `:262-265` dirty tree | message | `rc`, `refute_tag v0.2.0`, VERSION unchanged |
| `:273-276` wrong branch | message | `rc`, tag absence, VERSION unchanged |
| `:278-287` malformed / padded VERSION | message | `rc`, tag absence |
| `:289-294` hand-written bump | two messages | `rc`, tag absence |
| `:296-301` dist tag squatting | message | `rc`, `refute_tag v0.2.0` |
| `:303-309` bad arg / option / extra arg | message | `rc`, tag absence |

Concrete wrong implementation: make `common_preflight`'s dirty-tree branch
`printf 'uncommitted changes\n' >&2` and fall through instead of `die`. The
`:262-265` scenario stays green while the release proceeds on a dirty tree. The
wrong-branch and squatting scenarios have the same hole.

## Minor

### m1. `release-test.sh:935-947` and `:949-964` — two refusals with no side-effect assertions

Axis: conformance to `outline.md:172-173` ("*Unless stated otherwise a refusal
asserts: the named hint, no local tag created, origin `main` not advanced, `gh`
not called, marketplace untouched*").

The origin-sort scenario (Item 1.2 slice 3) asserts `rc`, `v1.11.0` present,
`v1.10.0`/`v1.9.0` absent. The probe-before-drift scenario (Item 1.2 slice 4)
asserts `rc` and four message needles. Neither asserts tag absence, `$GH_LOG`,
origin `main`, or the marketplace. Both runbook slices enumerate only the
message assertions, so this is a deviation from the outline's blanket rule
rather than from the slice contract, and both refusals reach `die` on the same
code path already covered by `:876-890` — hence Minor, not Major. Four lines
each closes it.

### m2. `version-guard-test.sh:355` — `tagless_sysmsg` depends on an undocumented ordering

Axis: independence.

`tagless_sysmsg="$(jq -r '.systemMessage' <<<"$guard_out")"` reads the
`guard_out` left by the no-tags run at `:315-317`, forty lines earlier, across
two intervening assertion blocks. `:324-332` documents that `$reason` is
deliberately reused; the `guard_out` reuse at `:355` does not carry the same
note. A scenario inserted between `:349` and `:355` silently retargets the
byte-identity comparison and the slice-3 guard stops guarding. One sentence in
the slice-3 comment, or a re-invocation, removes the trap.

### m3. `version-guard-test.sh` — no allow scenario runs against a git-repo fixture

Axis: coverage.

All three git fixtures (`$git_proj`, `$git_tagged_proj`, `$git_vnext_proj`) are
exercised by deny scenarios only; every `assert_allow` uses `$proj`, which is
deliberately not a repo. `version-guard.sh:80` is what keeps an allow from
reaching the listing at all, and `outline.md:130` states that as a property ("*It
runs only after the deny is established (after `:78`), so an allowed edit pays
nothing for it*"). Nothing pins it. A mutation hoisting the listing above `:80`
— the shape that matters, since a hook exiting non-zero for any reason but 2 is
non-blocking and the edit proceeds — passes the suite. One `assert_allow` on an
unrelated-field Edit against `$git_proj`, and one against the 127-`git` stub,
would cover it cheaply.

### m4. `version-guard-test.sh:374-381` — slice 4's vnext half omits `assert_no_escape_hatch`

Axis: consistency. Slices 1 (`:349`) and the tagged steady-state (`:365`) both
call it; the `vnext`/`v1.2` initial-release reason does not. Same branch as
slice 1's, so nothing is currently lost, but it is the one initial-release
reason not pinned against a bypass route.

### m5. `self-release-test.sh:149` — "tree left dirty" cannot see an untracked leftover

Axis: specificity. `git -C "$repo" diff --quiet HEAD` is tracked-only (same
mechanism as M1). A release that left an untracked scratch file behind passes.
`git status --porcelain` compared to empty is the honest form.

## Verified clean

- **Brief item 1 — the three load-bearing negatives are all written.** Item 1.2
  slice 1's "does NOT name `never been released`": `release-test.sh:885` and
  `:901`, and it is genuinely load-bearing — `release.sh:475` prints
  `to publish v%s` so the *bump refusal* also names `v1.2.3`, which is exactly
  what the negative separates. Item 1.4 slice 1's "does not contain
  `just release <bump>`": `release-test.sh:392`, paired with the positive
  `'just release`'` needle at `:391` whose backtick-immediately- after-`release` anchor cannot collide with the bump form (`release.sh:602` vs `:610` — confirmed by reading both). Item 2.1 slice 2's `$proposed` absence: `version-guard-test.sh:333-335`, implemented as an excision of the one legitimate `1.2.3
  -> 9.9.9` mention rather than a first-line drop — strictly better than the
  runbook's positional formulation, and the comment says why (a positional read
  "*fires on a legitimate refusal whose opening merely wraps, and misses a route
  that lands on line 1*").

- **Brief item 3 — the ordering fixture is correct.** `release-test.sh:938` uses
  `v1.9.0 v1.10.0 v1.11.0` (not a `v1.2.3`/`v1.10.0` pair), pushed and dropped
  locally, over an origin that also keeps `v1.2.3`. Lexicographic refname order
  puts `v1.10.0` first and `v1.9.0` last, so
  **both ends of an unsorted listing are wrong** — genuinely red without
  `--sort=-v:refname`. `:945-947` assert `v1.11.0` present and both others
  absent.

- **Brief item 4 — byte-identical `systemMessage`.** `version-guard-test.sh:355`
  / `:366-368`, `assert_eq` on `jq -r '.systemMessage'` from the tagless and
  `v1.2.3` fixtures with the same payload. (See m2 for the ordering caveat.)

- **Brief item 5 — the `GIT_DIR` leak points at a second, tagged fixture.**
  `version-guard-test.sh:389-391` invokes against `$git_proj` (tagless) with
  `GIT_DIR=$git_tagged_proj/.git`. Without `version-guard.sh:91-93` the `-C` is
  overridden and the listing finds `v1.2.3` → steady-state; the test demands
  initial-release. Genuinely red.

- **Brief item 6 — the 127 stub and the tagless fixture.**
  `version-guard-test.sh:148-153` writes a `git` exiting 127 *after* a line on
  stderr; `:408-411` prepends it to `guard_path`, which `run_guard` passes as
  `PATH` to the hook, and runs against `$git_proj` (tagless). The guard calls
  `git` exactly once (`version-guard.sh:124`), so the stub cannot disturb the
  deny decision. The tagless fixture is what discriminates — an implementation
  folding failure into emptiness answers initial-release here. The stderr-noisy
  stub is what makes `assert_deny`'s stderr check load-bearing for the
  `2>/dev/null`; `guard_path` is restored at `:412` *before* `assert_deny` at
  `:413`, so the harness's own `grep` is unaffected. The extra failing-*filter*
  scenario (`:420-441`, `grep` stubbed to exit 2 against the **tagged** fixture)
  is beyond the runbook and correctly reasoned: dropping the `grep_status -le 1`
  fold at `version-guard.sh:144` makes a released plugin read as never-released,
  and only the tagged fixture shows it.

- **Brief item 7 — harness hygiene.** `unset $(git rev-parse --local-env-vars)`
  present in `release-test.sh:13`, `version-guard-test.sh:19`,
  `self-release-test.sh:17`, each with the pre-commit-hook rationale.
  `check-version-test.sh:6-9` explicitly documents its absence; verified —
  `grep '\bgit\b' toolkit/check-version.sh` returns nothing, so there is no git
  command for a leaked `GIT_DIR` to redirect. Correct.

- **Brief item 8 — the `hook-test.sh` split lost nothing.** Compared against
  `6550fb7~1:tests/hook-test.sh` line by line. All eight version-guard scenarios
  survive in `version-guard-test.sh:238-308` (Edit-bump, Edit-bare-value,
  Edit-unrelated allow, Write-bump, unrelated-file allow, drifted-cwd,
  relative-path, BSD-realpath allow) with assertions unchanged; all five
  check-version scenarios survive in `check-version-test.sh:46-98`
  (MARKETPLACE_DIR unset, file missing, no entry, in sync, drift) with
  assertions unchanged. The harness was duplicated per file as CLAUDE.md
  requires, not sourced. `version-guard-test.sh` additionally hardened the
  shared harness: `assert_contains` moved from `grep` to `[[ == *…* ]]` (glob,
  needle quoted — no BRE surprises), and every temp dir is allocated ahead of
  the `trap` with the `set -u`/unbound-name rationale at `:56-71`.

- **Brief item 9 — whitespace safety.** `shellcheck -S style` clean on all four
  suites. Every command substitution feeding an assertion is quoted; the
  spaced-path scenario at `release-test.sh:645-654` asserts the path arrives
  whole via a leading-indent anchor; the diverged-push-route fixture puts a
  space in the redirect target's path *on purpose* (`:1002-1005`) and asserts
  the value verbatim; `push_target_refs` at `:1148` is a bare assignment, not a
  substitution inside the assertion, so a failing `for-each-ref` aborts loudly
  instead of passing vacuously (comment says so). `run_guard`'s
  `${extra_env[@]+"${extra_env[@]}"}` is the bash-3.2-safe form and the inner
  expansion is quoted. No `grep`-BRE needle in `release-test.sh` carries a
  metacharacter that could produce a false *pass*; the `.` in `v1.10.0` /
  `v1.9.0` / `$other` can only widen a positive match, and cross-checking the
  three ordering needles against each other finds no accidental match.

- **Brief item 10 — guards are marked and do discriminate.** Every
  green-when-landed scenario carries a comment naming the mutation it catches,
  and in several cases the measurement: `release-test.sh:477-496` (ladder order
  — "*measured — that permutation passes the four-scenario suite whole*"),
  `:498-518` (membership vs newest —
  "*a newest-only implementation passes them all (measured)*"), `:851-858`
  (drift-on-a-released-plugin — "*verified by mutation*"), `:1190-1193` (which
  end of the listing `latest_tag` takes), `:1200-1218` (the filter must not
  suppress the drift check — "*verified by mutation*"), `:1092-1101` (naming the
  value alone is satisfiable by the very push the check prevents —
  "*measured*"), `version-guard-test.sh:221-236` (`assert_no_escape_hatch`, with
  the residual bound stated), `:426-429` (filter-failure). These are not
  decoration.

- **Load-bearing extras beyond the runbook**, all sound:
  `release-test.sh:1104-1153` asserts the redirect target's ref list is empty on
  a resume that genuinely had work to do — the only assertion in the suite that
  separates "refused before any side effect" from "refused before `gh`";
  `:1427-1448` runs a `pipefail`-stripped copy of `release.sh` and asserts the
  probes still fail closed, with `grep -qx 'set -eu'` proving the rewrite
  landed.

## Scenario conformance table

`outline.md` `## Tests` — `tests/release-test.sh`

| Enumerated scenario | Site | Status |
|---|---|---|
| Entry at 1.2.3, no tags, no argument → publishes v1.2.3 | `release-test.sh:777-791` | covered |
| Same state with `patch` → refused | `:793-810` | covered (+ manifest, HEAD, origin main) |
| Lost tags, entry present | `:876-890` | covered |
| Lost tags, no entry | `:892-906` | covered |
| Lost tags, hand-advanced | `:908-933` | covered |
| Lost tags, origin newest ≠ lexicographic first | `:935-947` | covered; see m1 |
| Lost tags over a half-landed release | `:949-964` | covered; see m1 |
| Origin unreachable | `:966-975` | covered |
| Origin absent | `:977-986` | covered |
| Diverged push route × 3 settings | `:1016-1055` | covered |
| Only non-semver `v` tags on a virgin `0.1.0` | `:1155-1175` | covered |
| `vnext` beside `v1.2.3`, `patch` | `:1177-1198` | covered (+ `v1.0.0` end-pinning) |
| `--resume` on a virgin repo | `:376-393` | covered |
| `--resume`, tag dropped locally only | `:395-410` | covered (rewritten in place) |
| `--resume`, origin holds a semver tag ≠ `v$V` | `:412-431` | covered |
| `<bump>` hint on a new fixture | `:433-454` | covered (guard) |
| Bump-refusal loop + commit instruction | `:760-775` | covered |
| Initial release, entry disagrees with manifest | `:812-849` | covered |
| `make_virgin` comment loses the conjunct phrase | `:194-213` | covered |
| `lose_tag` helper (drop locally, keep on origin) | `:215-228` | covered |
| Unchanged `:592`, `:634`, `:721` | now `:739`, `:742`, `:1220` | intact |

`outline.md` `## Tests` — guard suite (now `tests/version-guard-test.sh`)

| Enumerated scenario | Site | Status |
|---|---|---|
| `unset $(git rev-parse --local-env-vars)` at top | `version-guard-test.sh:19` | covered |
| `run_guard` gains a project argument | `:177-198` | covered (+ extra-env) |
| Existing `$proj` scenarios pass unchanged | `:238-308` | covered |
| `git init` fixture, no tags → initial-release wording | `:310-322` | covered |
| `$proposed` nowhere beyond the refusal | `:324-335` | covered (excision form) |
| `systemMessage` byte-identical | `:355`, `:366-368` | covered; see m2 |
| Same fixture, only `vnext` → initial-release | `:370-381` | covered; see m4 |
| Same fixture tagged `v1.2.3` → steady-state | `:357-365` | covered (guard) |
| `GIT_DIR` leak → initial-release | `:383-397` | covered |
| Git absent (127 stub) → steady-state | `:399-418` | covered |

`runbook.md` per-slice contracts

| Slice | Site | Status |
|---|---|---|
| 1.1/1 (3 tests) | `:777`, `:793`, `:768-771` | covered |
| 1.1/2 | `:1155-1175` | covered |
| 1.1/3 | `:1177-1198` | covered |
| 1.2/1 (2 tests) | `:876-890`, `:892-906` | covered |
| 1.2/2 | `:908-933` | covered |
| 1.2/3 | `:935-947` | covered; m1 |
| 1.2/4 | `:949-964` | covered; m1 |
| 1.2/5 (2 tests) | `:966-975`, `:977-986` | covered |
| 1.2/6 | `:812-849` | covered |
| 1.3/1 (loop ×3) | `:1016-1055` | covered |
| 1.3/2 | `:1057-1102` | covered (+ `:1104-1153` extra) |
| 1.4/1 | `:376-393` | covered |
| 1.4/2 | `:395-410` | covered |
| 1.4/3 | `:412-431` | covered |
| 1.4/4 (2 tests) | `:433-454`, `:456-475` | covered (+ `:477-518` extra) |
| 2.1/1 | `version-guard-test.sh:310-322` | covered |
| 2.1/2 | `:324-349` | covered |
| 2.1/3 | `:355`, `:366-368` | covered; m2 |
| 2.1/4 | `:357-365`, `:370-381` | covered; m4 |
| 2.1/5 | `:383-397` | covered |
| 2.1/6 | `:399-418` (+ `:420-441`) | covered |

`tests/self-release-test.sh` — no outline or runbook contract (follow-up work
outside the plan). Reviewed against the axes only; findings M1, M2, M3, m5.
