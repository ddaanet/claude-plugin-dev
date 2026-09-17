# Item 2.1, slices 5-6 — code review

Scope: `toolkit/version-guard.sh`'s post-deny block (`:82-173`) as it stands
after `68f6007`, read whole rather than as a diff. `tests/hook-test.sh` not
edited; one coverage gap in it is reported below.

**Verdict: the block is correct.** Both properties the GREEN claims hold, and I
re-derived them from my own harness rather than from its tables. Two
comment-only fixes applied; no executable change (`diff` of both files with
comment lines stripped is empty). One test-coverage gap and one structural
observation are reported, not fixed.

All rows below are measured with `/tmp/claude-1000/s5s6/drive.sh`, an
independent driver: it builds an `Edit` payload bumping `1.2.3 -> 9.9.9`, runs
the hook under `env CLAUDE_PROJECT_DIR=<fixture>`, captures stdout and stderr
separately, and reports rc, `permissionDecision`, which wording the
`permissionDecisionReason` carries, and whether `systemMessage` is present.

## 1. Property (a): a failed listing is told from an empty one

Fixtures built from scratch: `nonrepo` (no repo anywhere up the tree), `tagless`
(`git init`, one commit, no tags), `tagged` (same plus `v1.2.3`).

| Fixture / forced failure | wording | correct? |
| --- | --- | --- |
| `tagless` — listing succeeds, empty | INITIAL | yes |
| `tagged` — listing succeeds, `v1.2.3` | STEADY | yes |
| `nonrepo` — git exits 128 | STEADY | by design, see §6 |
| stub git exits 127 (writes to stderr) | STEADY | yes |
| stub git `kill -KILL $$` (137) | STEADY | yes |
| stub git prints `v9.9.9` on **stdout**, exits 128 | STEADY | yes |
| stub grep exits 2 | STEADY | yes |
| `grep` absent from `PATH` entirely (127) | STEADY | yes |
| `.git` chmod 000 | STEADY | yes |
| `.git` replaced by a garbage file | STEADY | yes |
| `$project` a symlink to `tagless` / `tagged` | INITIAL / STEADY | yes |

Two of these the GREEN did not cover and the dispatch asked for:

- **git writing to stdout before failing does not contaminate `$listing`.** The
  stub prints `v9.9.9` — a string that would flip the wording to STEADY through
  the filter — then exits 128. `listing` does hold `v9.9.9`, but
  `listing_failed=1` short-circuits the whole filter block, so nothing crafted
  on git's stdout can reach `grep`. Answer is STEADY either way here, so I also
  confirmed the mechanism by reading: `release_tags` is assigned only inside
  `if [[ "$listing_failed" -eq 0 ]]`.
- **`grep` absent from `PATH` is 127, not 2**, and the code handles it because
  the fold is `[[ "$grep_status" -eq 1 ]] || listing_failed=1` — *anything* but
  1 is a failure, not just 2. Measured on the `tagless` fixture (truth:
  INITIAL): answer STEADY, the restrictive one. rc 0, deny JSON intact.

**Crafted tag names cannot reach anything.** git's own refname rules refuse a
space, a `;`, a `$(`, and a newline — I tried to create all four and git refused
each. Tags it *does* accept that contain shell metacharacters (`` v1.0.0`id` ``,
`v1.0.0'"`) were created and listed: no execution, no misclassification, and
adding a real `v3.0.0` alongside them still yields STEADY. `$listing` is only
ever expanded as `<<<"$listing"` and `$release_tags` only inside `[[ -z ... ]]`,
so there is no unquoted expansion to exploit.

**Whitespace.** A project dir at `.../pro ject dir/with space` answers INITIAL
with no tags and STEADY with `v2.0.0`. `$project` is quoted at every use
(`git -C "$project"`, and the pre-deny `abspath`/`manifest` construction).

**Dangling symlink `$project`.** rc 0, no stdout, **allow** — the manifest test
at `:23` fails first, so the hook never reaches the deny. Correct: there is no
manifest to guard.

## 2. Property (b): nothing after the deny reaches `set -e`

Every row in the §1 table exits **rc 0 with deny JSON on stdout**. Stderr is
empty for all but two:

- stub `grep` exiting 2 leaks the stub's own message;
- `grep` absent leaks bash's `grep: command not found`.

**Judgement: leave both unsilenced.** The `2>/dev/null` on the listing is
justified in the code by git's "not a repository" being an *expected* outcome
here rather than a diagnostic. Neither grep case is expected — both mean a
broken environment — so a `--debug` run should show them. Neither is a bypass:
rc is 0 and the deny JSON is on stdout, which is all the exit-status contract
requires.

I also proved the block sits after the deny gate **by construction** rather than
by line number. Under four PATHs — real git, git killed by SIGKILL, git exiting
127, and a PATH containing only `cat/jq/git/bash/sh` (no grep) — four payloads
were run each time:

| payload | every PATH |
| --- | --- |
| version bump | rc 0, DENY, deny JSON |
| unrelated manifest field | rc 0, ALLOW, 0 bytes |
| unrelated file | rc 0, ALLOW, 0 bytes |
| same version | rc 0, ALLOW, 0 bytes |

Sixteen runs, no deviation. A catastrophically broken git changes neither the
allow nor the deny, only the wording.

### Mutation testing — what the suite does and does not catch

SUT patched in place, `bash tests/hook-test.sh` run, SUT restored from a
pristine copy each time; final `sha256sum` re-verified against the pre-probe
one.

| mutation | suite |
| --- | --- |
| M2 — `unset GIT_*` moved *after* the listing | **KILLED** (git-dir-leak scenario) |
| M3 — `unset GIT_*` removed | **KILLED** (git-dir-leak scenario) |
| M4 — failed listing folded back into an empty one | **KILLED** (listing-failure scenario) |
| M1 — drop `[[ "$grep_status" -eq 1 ]] \|\| listing_failed=1` | **SURVIVED** |

M2 and M3 together discharge dispatch item 3: the clearing is load-bearing and
its position before the listing is load-bearing, both enforced by the suite.

**M1 is a real coverage gap (major, test-side, reported not fixed).** Dropping
the fold makes every grep failure read as "no match". Measured under that
mutation with a grep stub exiting 2:

- `tagless` repo → INITIAL (was STEADY);
- **`tagged` repo → INITIAL** (was STEADY).

That second row is the failure slice 6 exists to prevent: the permissive "this
plugin has never been released, the first version is yours to choose" told to an
agent on a plugin that *has* released. The suite is green under it.
`tests/hook-test.sh` covers a failing **listing** (the 127 git stub) but never a
failing **filter**. A scenario prepending a `grep` stub that exits 2 to
`guard_path` — the same mechanism the existing 127 scenario uses for `git` —
would close it, asserting STEADY against the `$git_tagged_proj` fixture.

## 3. `$?` inside the `else` branch — correct, and now guarded by a comment

Confirmed by construction, not by reading: with `grep` forced to 2 against the
`tagless` fixture (truth INITIAL), the answer is STEADY. That is only reachable
through `listing_failed=1`, so `$?` is genuinely the grep pipeline's status and
the no-match path is not being taken.

The form is correct **and one edit away from a total bypass.** I inserted a
single `[[ -n "$listing" ]]` between `else` and `grep_status=$?`:

```
rc=1 decision= wording=OTHER stdout_bytes=0 stderr=[grep: stub error]
```

rc 1 with no stdout — a non-blocking error, the refused edit proceeds. Cause:
errexit is suspended for an `if` *condition* but a branch *body* is
errexit-live, so a failing statement there both clobbers `$?` and kills the
hook. Nothing in the file said so.

**Fix applied (minor):** a four-line comment directly above `grep_status=$?`
stating it must remain the first statement in the branch, why, and that the
consequence was measured.

**Flagged, not performed:** the structurally robust alternative is
`release_tags="$(grep … <<<"$listing")" || grep_status=$?` with `grep_status=0`
initialised above it. That binds the capture to the status in one statement, so
no insertion can separate them, and drops the `:` no-op then-branch. It rewrites
control flow that three reports document by shape, for no present behaviour
change, so it is the orchestrator's call rather than a review fix.

## 4. `<<<"$listing"` vs the old pipe

The herestring appends a trailing newline, so an empty `$listing` becomes one
empty line. `^v[0-9]+\.[0-9]+\.[0-9]+$` cannot match an empty line, so grep
returns 1 → no-match → `release_tags=""` with `listing_failed=0` → INITIAL.
Measured: `tagless` → INITIAL, no spurious match. A single-tag listing
(`tagged`, exactly `v1.2.3`) → STEADY. Both correct.

`pipefail` no longer participates: `grep -n '\bgit\b'` finds exactly one git
invocation in the file (`:123`) and it is not in a pipeline, and the filter is
not either. The remaining pipe in the file (`jq | jq` at `:50-51`) is pre-deny
and pre-existing — a failure there exits before any deny is decided, so it
cannot strand a refusal.

## 5. The hardcoded `GIT_*` list — no omission that can redirect the listing

`git rev-parse --local-env-vars` on this box (git 2.47.3) lists 15 names; the
hardcoded `unset` covers 8. The 7 it omits are `GIT_CONFIG`,
`GIT_CONFIG_PARAMETERS`, `GIT_CONFIG_COUNT`, `GIT_IMPLICIT_WORK_TREE`,
`GIT_NO_REPLACE_OBJECTS`, `GIT_REPLACE_REF_BASE`, `GIT_PREFIX`.

Measured rather than reasoned. Each was set to a value pointing at the `tagged`
fixture and the hook run against `tagless`; a redirect would show as STEADY.

| variable | redirects `git -C <dir> tag --list`? |
| --- | --- |
| all 7 omitted `--local-env-vars` names | **no** — INITIAL, unchanged |
| `GIT_CONFIG_COUNT`/`KEY_0`/`VALUE_0` trio (`core.worktree`, `safe.directory`) | **no** |
| `GIT_NAMESPACE`, `GIT_CEILING_DIRECTORIES`, `GIT_DISCOVERY_ACROSS_FILESYSTEM` (not in the list at all) | **no** |
| control, clearing removed (M3): `GIT_DIR` | **yes** — STEADY |
| control, clearing removed (M3): `GIT_WORK_TREE`, `GIT_COMMON_DIR`, `GIT_INDEX_FILE`, `GIT_OBJECT_DIRECTORY` | no |

So the hardcoded set has **no real omission**: on this git, `GIT_DIR` is the
only variable of any kind that redirects the listing, and it is cleared. The
list is over-broad — 7 of its 8 names are inert today — which costs nothing and
is the right side to err on.

The GREEN's reasoning for rejecting `unset $(git rev-parse --local-env-vars)`
holds: that discovery call is itself a `git` invocation, and slice 6's own
scenario is a `git` that exits 127. It would clear nothing in exactly the runs
where the listing is also unreliable. The comment states the residual bound ("a
future git adding another one is a gap here, not a silent one") rather than
implying coverage, which is the right form.

**`unset` is the right mechanism.** The variables matter only because `git`
inherits the hook's exported environment, and `git` is a child of this shell —
so removing them from the shell removes them from the child. `env -u` per call
would need repeating at every call site. Nothing later in the script is
affected: there is one `git` invocation in the file, and the final `jq` reads
none of these names.

## 6. Wording when the listing failed — judgement: acceptable as written

The steady-state reason now doubles as the "don't know" answer, and two of its
sentences can be false there: "The manifest version is the last released
version" and "The release recipe also refuses if plugin.json and the latest git
tag disagree".

The most common instance is not an exotic one. `nonrepo` → git exits 128 →
STEADY. A project dir with no enclosing repo provably has no tags, so the *true*
answer there is initial-release. Slice 1 (`df2c4c0`) answered INITIAL for it;
slice 6 flipped it to STEADY. Measured both, side by side, against the same
fixture.

That flip is **decided design, not drift.** `outline.md` decision 2 names "git
absent, not a repo" as one case and picks the steady-state message, rejecting
both the initial-release wording and a third wording true in both states. No
suite scenario asserts wording on the non-repo `$proj` fixture, which is why
nothing went red — but the end state is what the outline specified.

**My judgement: no qualifier. Ship it.**

1. The false sentences are false only where believing them is harmless. Both
   push the agent toward the recipe and away from editing; the guard refuses
   either way. The opposite error is not symmetric — telling an agent on a
   released plugin that the first version is the maintainer's to choose invites
   it to pick one, which is the whole failure Item 2.1 exists to prevent.
2. A qualifier converts a directive into a conditional the agent must resolve,
   and the only way it can resolve it is by doing the git work the hook just
   failed to do. Visible uncertainty in a deny reason reads as an opening to go
   look and then act. CLAUDE.md's dual-channel rule is explicit that the agent
   message must not be softenable into something readable as a way around the
   guard.
3. The operative sentences are unconditionally true in every state: "If the goal
   is to ship a release, invoke the recipe instead of editing this file. Do not
   bypass this guard, modify the recipe, or alter version state by other means."
   Those carry the deny; the two that can be false are context.
4. The item's rule that the header comment (`:3-7`) be restated for both cases
   is met — the steady-state text restates its first half ("manual edits desync
   the manifest from the latest tag"), the initial-release text its second.

A misleading-but-refusing message costs a maintainer one moment of "actually
this has never released"; a bypass costs a published version. The asymmetry is
large and one-directional.

## 7. Slice 3's invariant: `systemMessage` constructed once

Static: `human_msg=` appears once (`:175`), after `fi`, outside both heredocs,
and `jq -nc --arg s "$human_msg"` is the single unconditional emitter (`:182`).
Running: every row in §1 and §2 reports `sysmsg=true`, INITIAL and STEADY and
failure paths alike.

## 8. Steady-state byte-identity — verified against `df2c4c0^`

Not against the report's claim. `git show 'df2c4c0^:toolkit/version-guard.sh'`
extracted and diffed:

- steady-state heredoc body: **identical**, 425 bytes;
- `human_msg=` line: **identical**;
- last 9 lines (the `jq -nc` emitter and `exit 0`): **identical**.

## 9. Line count and structure — a helper is not yet warranted

`wc -l toolkit/version-guard.sh` → **184** after my comment edits (181 before),
against a 400-line cap. The post-deny block is ~92 lines of which ~19 are
executable; it is comment-dominated, not logic-dominated.

**Flagged, not performed:** a `released_state()` helper returning
`initial`/`steady` would shorten the main flow, but it would have to return
through stdout, and capturing a function's stdout in `$( )` under errexit
reintroduces a status boundary in the exact code whose invariant is "no status
escapes after the deny". It would relocate the comments rather than reduce them.
Revisit if a third wording or a second listing is ever added; today the
extraction costs more than the 19 lines it would move.

## 10. Fixes applied

Both comment-only. `diff` of the pre- and post-fix files with comment lines
stripped is empty, so the executable text is byte-identical to `68f6007`.

1. **`else`-branch errexit note** (§3) — four lines above `grep_status=$?`.
2. **Two references to this repo's internal plan documents removed from shipped
   code.** `toolkit/` is the dist boundary: a consumer vendors this file and
   reads `(see the hook-exit-status-contract report)` and
   ``  `outline.md`'s "only the filter's no-match status is absorbed" is read loosely here on purpose ``
   pointing at documents they do not have, and the second is a write-time note
   about deviating from a plan — changelog content, not source content. Replaced
   with the durable statement of the same fact: absorbing after the deny is
   fail-closed, propagating is fail-open. No technical content dropped. Net -2
   lines. (Precedent exists at `toolkit/release.sh:151`, which cites
   `outline.md` the same way; out of scope here, worth a sweep later.)

## 11. Green

- `bash -n toolkit/version-guard.sh` — OK
- `shellcheck toolkit/version-guard.sh` — clean
- `bash tests/hook-test.sh` — `all hook scenarios passed`, 18 scenarios
- `just precommit` — see the run recorded by the orchestrator; green at the time
  of writing
- SUT restored and verified: comment-stripped `diff` against `68f6007` empty;
  every mutation run followed by `cp` from a pristine copy and a `sha256sum`
  match before the next.

## Not fixed, for the orchestrator

- **Major (test-side):** no scenario covers a failing *filter*. M1 survives the
  suite and turns a released plugin's deny into the permissive wording. §2.
- **Minor:** the `|| grep_status=$?` restructuring that makes §3's hazard
  unreachable rather than commented.
- **Minor:** `toolkit/release.sh:151` cites `outline.md` from shipped code, the
  same issue as §10.2, outside this review's scope.
