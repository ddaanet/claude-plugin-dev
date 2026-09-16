# Item 1.2, slice 6 — code review

Scope: `toolkit/release.sh` only, at `6ed1206`. `tests/release-test.sh` and
every other file out. Nothing committed.

Verdict: the branch is behaviourally right — the flag is set exactly where the
probe proves the fact, both mutations of it are caught, and the
`manifest_version` move is provably inert. **One real defect, fixed:** the new
`jq` capture had no status check, and because `set -e` *is* in force where it
sits, a reachable failure aborted the run with jq's status and
**no `error:` line at all** — an observability regression against `6ed1206^`.
Two message corrections applied besides. `bash tests/release-test.sh` green (48
scenarios), `just precommit` green.

## §2 first — `set -e` inside `cmd || { … }`, measured

The answer decides §1, so it comes first. Probe, bash 5.2.37:

```sh
set -euo pipefail
( false || {
    v=$(false)
    echo "A: continued, v=[$v]"
  }
  echo "A: after group" ) ; echo "A subshell status=$?"
```

Verbatim result:

```
--- A: failing non-final cmd substitution assignment inside || { } group ---
OUTER RC=1
GNU bash, version 5.2.37(1)-release (x86_64-pc-linux-gnu)
```

`A: continued` never printed and the probe died at the first case — the later
cases never ran. **`set -e` is active for commands *inside* the brace group.**
POSIX suppresses errexit for the non-final *elements of the AND-OR list*; that
suppression does not reach inside the final element's body. The reading that
looks obvious — "it's in a `||`, so errexit is off" — is wrong. Consequence: the
`jq` capture at `:343` could not "silently continue" past a failure; it aborted
the whole script.

## §1 — the unguarded `jq` capture. Reachable, and it was a regression. Fixed.

Two questions: what it prints, and whether that state is reachable.

**What it prints when the entry is absent.** `jq -r` on a no-match filter prints
one empty line and exits 0, so `market_version=""` and the hint reads
`no release is recorded at 0.1.0 or  — …` with a hole. Reproduced below.

**What it does when jq fails.** Given §2, it aborts immediately with jq's
status. Traced with `bash -x` on a malformed `marketplace.json`:

```
82:+ bash /tmp/…/plugin-dev/check-version.sh
83:jq: parse error: Invalid literal at line 1, column 7
86:++ jq -r --arg n fixture '.plugins[] | select(.name==$n) | .version' /tmp/…/marketplace.json
87:jq: parse error: Invalid literal at line 1, column 7
88:+ market_version=
```

The run's whole output at `6ed1206` was three copies of that parse error and
**rc=5 — no `error:` line at all**. The same fixture against `6ed1206^`:

```
rc=1
jq: parse error: Invalid literal at line 1, column 7
jq: parse error: Invalid literal at line 1, column 7
hint: `just resume-release` completes a release that landed partially.
error: fix the version drift above before releasing
```

So the slice turned a refusal that said `error: …` and exited 1 into a mute
abort at an unfamiliar status. The pre-slice-6 hint was *misleading* on that
fixture (it offered resume for a broken JSON file), but it was present.

### Reachability — established empirically, three routes

`check-version.sh` exits non-zero on more than drift. Its `exit 1` drift branch
does require an entry, but `set -euo pipefail` makes any failing `jq` in it
fatal at jq's own status, and that reaches the same `|| { … }`.

| Fixture | check-version.sh | at `6ed1206` | route |
|---|---|---|---|
| `marketplace.json` = `{ this is not json` | parse error, exit 5 | **rc=5, silent** | jq fails |
| `marketplace.json` = `{"foo": 1}` (no `.plugins`) | `Cannot iterate over null`, exit 5 | **rc=5, silent** | jq fails |
| valid JSON, `.plugins: []`, entry absent | `no fixture entry … — skip`, **exit 0** | not reached | — |

Row 3 is the important negative: with a *valid* marketplace file and no entry,
`check-version.sh` skips, so the plain "entry absent" state cannot reach this
branch. Verbatim:

```
check-version rc=0 out=[check-version: no fixture entry in /tmp/…/marketplace.json — skip]
```

Rows 1 and 2 are reachable and were both silent. `common_preflight` does not
intercept them: its `jq -e … any(.plugins[])` at `:180` runs inside an `if`
condition, so a parse error (exit 2) reads as *false* and merely sets
`marketplace_entry_exists=0`.

**There is also one reachable route to the empty (not failed) value**, which is
why I guarded it rather than commenting it away. `release.sh` resolves
`$manifest` against the **CWD**; `check-version.sh` with no arguments resolves
its default against the **toolkit's own parent**. Run `release.sh` from a plugin
root other than the one vendoring it and the two read different manifests, so
`$plugin_name` differs and `jq` matches nothing. Probe P11 (plugin `other` in
the CWD, toolkit vendored by plugin `fixture`) at `6ed1206` printed
`hint: no release is recorded at 0.1.0 or  — this plugin has never been` — the
dangling clause the dispatch predicted, reproduced. The CWD/toolkit divergence
itself is pre-existing and out of scope; this is one of its symptoms.

### Fix applied

```sh
            market_version=$(jq -r --arg n "$plugin_name" \
                '.plugins[] | select(.name==$n) | .version' "$marketplace_json") \
                || die "could not read $plugin_name's entry in $marketplace_json — nothing was done"
            [ -n "$market_version" ] \
                || die "no $plugin_name entry in $marketplace_json to compare against — nothing was done"
```

Two dies rather than one, because the two states have different diagnoses. Both
carry the comment the dispatch asked for: the errexit measurement and why the
capture rule bites here, and the reachability argument for the emptiness guard
(so the next reader does not delete it as dead code).

After the fix, the same three fixtures:

```
P9  malformed marketplace.json     rc=1  error: could not read fixture's entry in /tmp/…/marketplace.json — nothing was done
P10 marketplace.json, no .plugins  rc=1  error: could not read fixture's entry in /tmp/…/marketplace.json — nothing was done
P11 cross-plugin invocation        rc=1  error: no other entry in /tmp/…/marketplace.json to compare against — nothing was done
```

jq's own parse error still reaches the user above each `error:` line — it is the
only thing that says *why* — and nothing is suppressed.

## §3 — `verifiably_unpublished`'s placement. Correct; both mutations caught.

Every path through `if [ -z "$release_tag_list" ]`:

| path | flag on exit | right? |
|---|---|---|
| `origin_release_tags` fails | `die` at `:300`, never read | n/a |
| origin listing non-empty | `die` at `:312`, never read | n/a |
| origin listing empty | falls through to `verifiably_unpublished=1` | yes |
| whole block skipped (local tags exist) | stays `0` | yes |

There is no route that leaves the flag `0` with both listings empty, and none
that sets it where a tag exists. The assignment being *last* in the block is not
load-bearing (both earlier branches `die`), but it is the position at which the
comment's claim — "reached only when the probe above found nothing either" — is
true, so it is the honest place for it.

Mutations, run independently, full suite each time:

```
##### MUTATION: init verifiably_unpublished=1 instead of 0 #####
FAIL: released-drift still offers resume — a release did land partially here: output did not contain 'just resume-release'
1 failure(s)

##### MUTATION: assignment verifiably_unpublished=1 -> =0 #####
FAIL: initial-entry-disagrees hint names the manifest version: output did not contain '0.1.0'
FAIL: initial-entry-disagrees hint names the marketplace entry version: output did not contain '1.2.3'
FAIL: initial-entry-disagrees says neither version has a recorded release: output did not contain 'no release is recorded at'
FAIL: initial-entry-disagrees points at the marketplace entry as the one to correct: output did not contain 'correct the marketplace entry'
FAIL: initial-entry-disagrees offers editing the manifest instead, if 1.2.3 is the intended version: output did not contain 'set .version in .claude-plugin/plugin.json'
FAIL: initial-entry-disagrees must not offer resume — nothing was ever released to resume: output contained 'just resume-release'
6 failure(s)
```

Each side of the branch is caught by its own scenario and by nothing else — the
test review's guard scenario is doing exactly the work it was added for.
`git diff --stat toolkit/release.sh` was empty after the restore, before any
real fix was applied.

## §4 — `manifest_version` moved earlier. Inert, proved on a fixture the suite lacks.

The only way the move could be observed is a `jq -r .version "$manifest"` that
fails, which under errexit would now abort *before* `check-version.sh` instead
of after. That state is unreachable: `common_preflight:176` already runs
`plugin_name=$(jq -r .name "$manifest")` at the top level of the script, so a
malformed manifest is fatal well before `release_preflight` is entered.

Probe P6, malformed `plugin.json`, both refs, same fixture:

```
6ed1206^ rc=5 out=[jq: parse error: Invalid numeric literal at line 2, column 0]
6ed1206  rc=5 out=[jq: parse error: Invalid numeric literal at line 2, column 0]
```

Byte-identical, and a *single* jq error — i.e. both die at `:176` and never
reach either position of the moved line.

The `check-version.sh` path itself is unchanged, P7 (drift on a plugin with a
real tag, the resume side), both refs:

```
check-version: version drift — plugin.json=1.2.4 marketplace.json=1.2.3
  bump both to the same value before release.
hint: `just resume-release` completes a release that landed partially.
error: fix the version drift above before releasing
```

And the later first-release branch still reads the same value — P12, a genuine
first release through the moved read:

```
first release: publishing the manifest version 0.1.0 as-is (no bump)
… tag=v0.1.0 market=0.1.0, Release v0.1.0 complete
```

`manifest_version` itself is still captured without a status check — unchanged
by the slice (unchecked at its old position too) and justified by the paragraph
above: `:176` is the equivalent check, one jq call earlier on the same file.

## §5 — message quality against Decision 1. Two corrections.

The hint at `6ed1206`, on the real fixture:

```
hint: no release is recorded at 0.1.0 or 1.2.3 — this plugin has never been
      published under either version, so there is nothing to resume.
      correct the marketplace entry to match plugin.json (a successful
      first release would write 0.1.0 there anyway), or if 1.2.3 was the
      intended version, set .version in .claude-plugin/plugin.json
      to it and commit that edit, then re-run.
```

**Right:** all four of decision 1's clauses are present in its order — both
versions, no release recorded at either, the entry as the default correction
with `bump_marketplace`'s reason in parentheses, the manifest as the alternative
when the entry's version was intended, and no resume. Remedy ordering (entry
first, manifest second) matches. Continuation indentation is six spaces under
`hint: `, the file's convention at `:308-311` and `:368-370`. All to stderr.

**Correction 1 — the message claimed more than the probe established.** "this
plugin has never been published under either version" is a claim about
*publication*; what the code proved is that no `^v[0-9]+\.[0-9]+\.[0-9]+$` tag
exists locally or on origin. The outline's Scope section records exactly that
gap as a live residual — "a plugin released only under non-semver or non-`v`
tags, with an entry, would now republish its manifest version" — so the hint
must not deny the state. Decision 1's own words are "says no release is recorded
at either": the first line carries that and is accurate, the second overreached.
Rewritten to what was measured:

```
hint: no release is recorded at 0.1.0 or 1.2.3 — this plugin has no
      release tag at all, here or on origin, so there is nothing to resume.
```

This is also *stronger* advice, not weaker: it names the evidence the maintainer
can check.

**Correction 2 — a pronoun two lines from its referent.**
`set .version in .claude-plugin/plugin.json / to it` — "it" is `1.2.3`, four
words and a path earlier, and is briefly readable as `plugin.json`. Now:

```
      intended version, set .version in .claude-plugin/plugin.json
      to 1.2.3 and commit that edit, then re-run.
```

Every assertion over this hint still holds —
`set .version in .claude-plugin/plugin.json` stays contiguous, and
`no release is recorded at`, `correct the marketplace entry`,
`0.1.0`/`1.2.3`-in-`hint_only` and the
`assert_not_contains "just resume-release"` are untouched. Suite green.

**Wrapping, measured rather than eyeballed.** Rendered lengths of the six hint
lines after the fixes, real fixture: `69, 75, 70, 72, 66, 49`. All under 80; the
longest *fixed* line is 75, and `$manifest` is a constant so only the two
version strings vary. The pre-fix wrap put the longest at 77, and my first
attempt at correction 2 pushed it to 86 — caught by measuring, and rewrapped.
**Recorded gap:** with a deliberately long entry version (`10.20.30-rc.1`) the
first hint line reaches 81. `check-version.sh`'s own drift line reaches 81 on
that same fixture and `:310`'s `$origin_newest` hint has the property too, so
interpolation-driven overflow is the file's existing behaviour; I did not
restructure for it.

## Standing criteria

**The capture rule, every site the slice added or moved.**

| Site | Shape | Verdict |
|---|---|---|
| `:329` `manifest_version=$(jq -r .version "$manifest")` (moved) | no status check | correct — `common_preflight:176` is the equivalent check on the same file, one call earlier; proved by P6 |
| `:343` `market_version=$(jq …)` (new) | **was unchecked** | **fixed** — `\|\| die`, plus a `[ -n … ] \|\| die` for the empty result |
| `:322` `verifiably_unpublished=1` | assignment, not a capture | n/a |

No new `git` or `ls-remote` call site. No `[ -z "$(f)" ]` / `[ -n "$(f)" ]`
shape anywhere on the path. The three pre-existing `ls-remote | cut` captures at
`:438`, `:466`, `:562` are untouched, per the dispatch.

**`die` in a command substitution.** None. The two new `die`s are the right-hand
side of `||` in the enclosing shell; grep confirms no `$( … die … )` was added.
Verified live: P9/P10/P11 all exit 1 from `release.sh` itself.

**Whitespace safety.** Every new expansion is double-quoted: `"$plugin_name"`,
`"$marketplace_json"`, `"$market_version"`, `"$manifest_version"`,
`"$manifest"`, including inside the two `die` strings and inside
`[ -n "$market_version" ]`. The jq program is single-quoted and the name passes
through `--arg`, never through the program text. No new word-splitting site, no
new `cut`/`read` without `-r`. `shellcheck` clean.

**One recorded gap, not fixed: duplicate marketplace entries.** Two entries with
the same `name` make `jq` emit two lines, and the hint breaks mid-sentence:

```
check-version: version drift — plugin.json=0.1.0 marketplace.json=1.2.3
9.9.9
  bump both to the same value before release.
hint: no release is recorded at 0.1.0 or 1.2.3
9.9.9 — this plugin has never been
```

Reachable, and the new guard does not catch it (non-empty value, jq exits 0).
**Not fixed here, deliberately:** `check-version.sh`'s own drift line garbles
identically and that file is explicitly OUT of this item's scope, so narrowing
only `release.sh`'s half would make the hint name a different version from the
line above it — worse than the symmetric garble. `jq … | head -1` is not the
fix; deduplicating at the source is, and that is a marketplace-validation
concern, not this branch's.

**Comment honesty.** Every comment the slice added, checked against behaviour.
`:314-321` "reached only when the probe above found nothing either" and
"captured as a flag rather than re-running the probe … status is read exactly
once" are both true (§3's path table; no second `ls-remote` exists on the path).
`:325-328` "needed below regardless of which branch fires … read it once here"
is true, both readers confirmed (P8's hint, P12's first release). `:335-341`'s
decision-1 rationale matches `outline.md`'s conclusion clause for clause,
including "a successful first release would write $manifest_version there anyway
via bump_marketplace" — P12 shows `marketplace: entry created at 0.1.0`. The one
failure was in the hint text, not a comment: "never been published under either
version", rewritten in §5. No surviving comment asserts something the code does
not do.

**Hook/output channels.** Every `printf` in the branch ends `>&2`; `die` prints
`error:` to stderr. `hint:` opener with six-space continuations. Nothing
redirects or suppresses stderr — jq's diagnosis is what makes the two new `die`s
actionable, and it is left visible. No `# shellcheck disable=SC2016` needed in
the new code: the branch contains no literal backtick inside a single-quoted
string (the resume hint below it keeps its own, still load-bearing).

**File length. 676 lines. Do not split — unchanged recommendation.** 602 at
`3794941`, 654 at `6ed1206`, 676 after this review. My change is `+26 / -4`; 20
of the 26 added lines are comment, 6 are code.

No change to the seam analysis, plus one new observation. The prior reviews'
cost argument stands unchanged: a second file is a new *shipped* path, so
`tests/dist-tree-test.sh`'s list and CLAUDE.md's Layout list move with it and
consumers pick up a file name they did not ask for. What is new is that this
slice's code is not in the named seam at all — it sits inside
`release_preflight`, reading `$plugin_name`, `$marketplace_json`,
`$manifest_version` and `$verifiably_unpublished`, four variables set in three
different places in the same file. Moving the `semver_tags` / `release_tags` /
`origin_release_tags` cluster out would not shrink this function by a line. The
growth is accumulating inside `release_preflight`, so the honest seam, when
someone takes that decision, is *that function* and not the tag helpers. Still a
recorded open decision for the Phase 1 boundary. **Still declined.**

**Item 1.3 / 1.4 — flagged, not built.** `resume_preflight` still has no origin
probe and its no-tag hint ladder is untouched; nothing in this pass moved toward
either.

## Nothing UNFIXABLE

Every defect found in scope was fixed in this pass. The duplicate-entry garble
above is recorded rather than unfixable: it is fixable, but only together with
`check-version.sh`, which this item's scope excludes.

## State on exit

- `toolkit/release.sh` — **modified, uncommitted.** `git diff --stat` reads
  `1 file changed, 26 insertions(+), 4 deletions(-)`, all of it §1's two guards,
  §5's two message corrections, and their comments. `git status --short` shows
  that file and nothing else.
- Every throwaway mutation restored. The two `verifiably_unpublished` mutations
  were applied from a saved copy and reverted from it in the same shell
  invocation, and `git diff --stat toolkit/release.sh` was verified empty before
  any real fix was applied.
- `bash tests/release-test.sh` — green, `all release scenarios passed`, 48
  scenarios (`grep -c '^echo "=== '` on the suite).
- `just precommit` — green, `ok`. `bash -n`, `shellcheck`, `_import-check`,
  `tests/hook-test.sh`, `tests/release-test.sh`,
  `tests/update-plugin-dev-test.sh`, `tests/dist-tree-test.sh`
  (`dist tree ok (9 files, no gitlink)`), `tests/docs-test.sh`
  (`docs ok (cap 400 lines, pointers resolve)`), `tests/doc-sync-test.sh`
  (`doc sync ok (5 shared command blocks, Layout matches toolkit/)`).
- **Nothing committed.** Nothing staged.
- `$TMPDIR` was unset in this dispatch shell; every probe and scratch file went
  to `/tmp/claude-1000/s6cr/`. Nothing left in the repo root.
- Note for whoever commits this: `tests/docs-test.sh`'s cap check reads
  `git ls-files`, so an untracked report is not measured. This file is 398 lines
  after `format-docs`, under the 400 cap, but the gate only says so once it is
  staged.
