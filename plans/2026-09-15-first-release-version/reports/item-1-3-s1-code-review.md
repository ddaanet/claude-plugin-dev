# Item 1.3, slice 1 — code review

Scope: `toolkit/release.sh` only, at `5fa9e0d`. `tests/release-test.sh` and
every other file out. Nothing committed.

Verdict: the predicate, the placement and the `$?` reading are all correct, and
the `master`-default protection is real — each verified by running, not by
reading. **Two defects fixed:** the read was `--get` on a key git treats as
multi-valued, which made the refusal name one of several values and advise a
recovery command that *fails*; and the two loop variables leaked into the global
scope. `bash tests/release-test.sh` green (49 scenarios), `just precommit`
green.

## §1 — multi-valued `pushurl`. The premise was wrong; a different defect was real. Fixed.

**The dispatch's prediction does not hold.** `git config --get` on a
multi-valued key does *not* fail. Scratch repo, two `pushurl` lines, git 2.47.3:

```
--- git config --get (capture stdout only) ---
status=0 out=[/tmp/two.git]
--- same, stderr visible ---
/tmp/two.git
rc=0
--- --get-all ---
/tmp/one.git
/tmp/two.git
rc=0
```

`--get` prints the **last** value and exits **0**. So the two-`pushurl`
repository never reached the `elif`; it hit the refusal branch and died with a
correct refusal. There was no `could not read git config …` malfunction. (The
ret=5 "multiple values" error is git's behaviour for `--unset`/set, not for
`--get`.)

Confirmed end to end against the real script at `5fa9e0d`, on a fixture with two
`pushurl` values:

```
### two pushurls set; run release.sh patch
rc=1
error: push route diverges from origin: remote.origin.pushurl is set to /tmp/…/mirror two.git; unset it or point it at origin
```

**But a real defect was underneath it.** The message names one of two URLs and
tells the maintainer to "unset it". That command refuses:

```
### the recovery the message advises:
warning: remote.origin.pushurl has multiple values
unset rc=5
```

A correct refusal handing back a recovery that does not work, on a *more*
diverged route than the one-value case — exactly the shape the dispatch was
worried about, arriving by a different mechanism. Pushing to several mirrors is
a documented, supported arrangement, so this is reachable configuration and not
a pathology.

A second, pre-existing symptom of the same read: a value containing a newline is
settable (git escapes it as `\n` in the file and returns a real newline), and
the single-line message already garbled on it at `5fa9e0d`:

```
error: push route diverges from origin: remote.origin.pushurl is set to aa
bb; unset it or point it at origin
```

### The read chosen — `--get-all`, not `-z --get-regexp`

`--get-all` takes a **literal** key name, lists every value one per line, and
still exits **1** when the key is unset (measured: `status=1 out=[]`), so the
absorption rule is unchanged.

`-z --get-regexp` is the whitespace-robust form the shared conventions name as
the default, and I rejected it here for a specific reason: its argument is a
**regex over the key name**, and one of the three keys interpolates `$branch`
into the key. Branch names legitimately contain regex metacharacters —
`git check-ref-format` forbids `~ ^ : ? * [ \` and space but permits `.`, `+`,
`$`, `(`, `)`, `|`, `{`, `}` — so a default branch named `release.1.x` or `a+b`
would need the branch name escaped into a regex before it could be matched.
`--get-regexp` also lowercases the variable part of the key in its output, so
`pushRemote` would have to be matched case-insensitively. That is strictly more
hazard than the NUL-delimiting buys, and NUL-delimiting cannot be had anyway:
`git config -z` output would have to survive `$( … )`, and bash discards NUL
bytes in command substitution.

### The other two keys

Neither is multi-valued in git's semantics — `branch.<name>.pushRemote` and
`remote.pushDefault` are last-one-wins. But a config file can physically hold
several lines of either, and `--unset` refuses those identically (measured on
two `branch.main.pushRemote` lines: `warning: … has multiple values`, `rc=5`),
so all three are read the same way. `git config --get` on that file returns
`beta` for `alpha`/`beta`, matching what git itself resolves.

### Fix applied

```sh
    local push_key push_values push_value
    for push_key in remote.origin.pushurl "branch.$branch.pushRemote" remote.pushDefault; do
        if push_values=$(git config --get-all "$push_key"); then
            printf 'hint: %s is set to:\n' "$push_key" >&2
            while IFS= read -r push_value; do
                printf '        %s\n' "$push_value" >&2
            done <<<"$push_values"
            printf '      unset it (git config --unset-all %s) or point it at\n' "$push_key" >&2
            printf '      origin, then run the same command again.\n' >&2
            die "push route diverges from origin: $push_key is set"
        elif [ "$?" -ne 1 ]; then
            die "could not read git config $push_key"
        fi
    done
```

Values go one per line in a `hint:` block rather than interpolated into the
`die`, which is `report_dirty`'s established idiom in this same file for exactly
this problem — a list of values, any of which may hold a space. A `pushurl`
holding a space must not read as two entries, and it cannot here.

Same fixture, after:

```
### two pushurls set; run release.sh patch
rc=1
hint: remote.origin.pushurl is set to:
        /tmp/claude-1000/s1cr/master/mirror one.git
        /tmp/claude-1000/s1cr/master/mirror two.git
      unset it (git config --unset-all remote.origin.pushurl) or point it at
      origin, then run the same command again.
error: push route diverges from origin: remote.origin.pushurl is set
```

The advised command is verbatim-runnable and actually clears the state —
verified rather than assumed:

```
--unset-all rc=0
post-unset --get-all rc=1
```

`--unset-all` is also correct on a single-valued key (`rc=0`), so the one
wording covers both cases.

**Key and value(s) are both still named** — the dispatch's requirement (c) and
the test review's finding. `run_in` captures `2>&1`, so the `hint:` lines land
in `$out` alongside the `error:` line; all three `names the value` assertions
still pass. The `die` line alone names the key, which matches `report_dirty`'s
caller (`die "uncommitted changes"` after a detailed hint) — the file's own
convention for a terse `error:` under a specific hint.

## §2 — `$?` after a failed `if` condition. Measured. The GREEN's claim holds.

The GREEN report's reasoning was right, but it was reasoning. Probe, bash
5.2.37, the exact `if v=$(cmd); then … elif [ "$?" -ne 1 ]` shape with a command
substitution in the condition:

```
exit0  : THEN branch, v=[hello]
exit1  : ELIF false -> $? was 1
exit2  : ELIF true  -> $? was NOT 1
exit128: ELIF true  -> $? was NOT 1
```

And directly, `if v=$(sh -c 'exit 7'); then …; elif [ "$?" -ne 1 ]; then` →
`ELIF fired, correct for 7`. The whole probe ran under `set -euo pipefail` and
did not abort, confirming the `if`-condition exemption as well.

Then the same question against the **literal shipped code**, `--get-all`,
`printf` block and all, with a `git` function stubbed to return an arbitrary
status:

```
--- stub status=0   --- rc=1  hint: … / error: push route diverges …
--- stub status=1   --- rc=0  LOOP COMPLETED — all three absorbed
--- stub status=2   --- rc=1  error: could not read git config remote.origin.pushurl
--- stub status=5   --- rc=1  error: could not read git config remote.origin.pushurl
--- stub status=128 --- rc=1  error: could not read git config remote.origin.pushurl
```

**Status 1 and only status 1 is absorbed**, on the code as it now stands. This
is the discipline the test review proved no fixture can pin, and it is now
pinned by measurement instead. The comment was rewritten to state what was
measured (`exit 2 and exit 128 both reach the elif body, exit 1 does not`)
rather than to argue from POSIX.

## §3 — scoping. Both variables leaked. Fixed.

`common_preflight` declares **no** `local` at all, by design: `branch`,
`main_branch`, `marketplace_json`, `marketplace_dir`, `plugin_name` and
`marketplace_entry_exists` are read by later functions. `push_key` and
`push_value` joined that set by accident and persisted after the function
returned.

No downstream reader collides — `grep -n 'push_key\|push_value'` over
`toolkit/release.sh` and `tests/release-test.sh` finds only the loop itself — so
this was latent rather than live. Fixed regardless:
`local push_key push_values push_value`. The file's convention is visible at
`:289` (`local listing`), `:330`, `:382` and `:492`, and mid-function `local`
inside a block is already used at `:330` and `:382`, so the placement matches.

## §4 — standing criteria

### (a) Predicate is "any of the three is SET" — correct

`outline.md` decision 3: "refuses when **any of the three is set**, before any
side effect and on both `release` and `--resume`, naming the setting and its
value." The loop tests set-ness via exit status alone and never compares URLs.
No divergence comparison anywhere. The comment's justification (URL identity is
not decidable in shell) matches the outline's rejected alternative.

### (b) `branch.$branch.pushRemote`, on a real `master` repo — protected

`$branch` is bound at `:144` and validated at `:149`; the loop is at `:192`, so
`$branch` is non-empty by construction (a detached HEAD gives `branch=""` and
dies at `:149` against a non-empty `$main_branch`, which falls back to `main`).

The suite cannot reach this — every fixture repo is `git init -b main` — so I
built a `master`-default plugin fixture by hand (origin bare repo on `master`,
`remote set-head origin master`, marketplace on `master`, the gh stub, the
toolkit vendored under `plugin-dev/`):

```
### derived branch/main_branch:
  branch=master
  main_branch=master

### run release.sh patch on a master-default repo with branch.master.pushRemote set
rc=1
hint: branch.master.pushRemote is set to:
        pushtarget
      unset it (git config --unset-all branch.master.pushRemote) or point it at
      origin, then run the same command again.
error: push route diverges from origin: branch.master.pushRemote is set
-----------
v1.2.4 tag: no
gh log: []
```

The derived key is `branch.master.pushRemote`, it refuses, no tag is created and
`gh` is never called. A hardcoded `branch.main.pushRemote` would have released
this repo straight into the redirect target.

### (c) Message names key and value — see §1

### Status absorption — see §2. Absorbs 1 only, measured.

### Whitespace safety

Every expansion in the block is quoted: `"$push_key"` at all four sites,
`"$push_values"` in the herestring, `"$push_value"` in the `printf`, and the
interpolated key inside `"branch.$branch.pushRemote"`. `read -r` with `IFS=` —
no backslash mangling, no leading/trailing-space trimming. Values are passed as
`printf` *arguments*, never as a format string. `shellcheck` clean.

The spaced `pushurl` path is exercised end to end by the fixture and by my
two-mirror probe above, and prints as one entry.

**A newline in a value is reachable** — probed directly:

```
=== newline value ===
set rc=0
--- raw ---
7:      pushurl = aa\nbb
status=0 out=[aa
bb]
```

What it does now: prints across two indented lines in the hint block, which
under-counts the entries. This is the same residual bound `report_dirty` records
at `:118-121` for a path containing a newline, and it is recorded in the new
comment for the same reason. It is *better* than at `5fa9e0d`, where the value
broke the single `error:` line mid-sentence. Eliminating it entirely is not
available: `git config -z` output cannot survive `$( … )` (bash discards NUL),
and `--get-regexp` is ruled out by §1's branch-name argument.

A branch name cannot contain a space (`git check-ref-format`), so the
interpolated key is single-token regardless; the quoting is correct anyway.

### Placement — before any side effect, both modes

The loop sits between the branch validation and the first `MARKETPLACE_DIR`
check, so it precedes `check_marketplace_writable` (the first thing in the run
that writes anything) and every `git` mutation. `common_preflight` is called
unconditionally at `:714`, **before** the `if [ "$mode" = "release" ]` branch,
so `--resume` reaches it. Confirmed by running, not by reading — same fixture,
`--resume`:

```
rc=1
hint: branch.master.pushRemote is set to:
        pushtarget
      …
error: push route diverges from origin: branch.master.pushRemote is set
```

Slice 2 will assert this; it already holds.

### Comment honesty — one stale reference found and removed

- **`(:342-ish)` was wrong by 200 lines.** `push_branch`'s unqualified
  `git push` is at `:542` and `push_tag`'s is at `:565` (`grep -n 'git push'`).
  The number came from the outline's pre-Item-1.2 numbering. Removed rather than
  corrected — the sentence already names both functions, which is the reference
  that does not rot.
- "`git config --get` exits 1 when the key is unset" — true, but the claim now
  describes `--get-all`, with the measured multi-value finding beside it.
- The `$?` paragraph now states the measurement (§2) instead of arguing from
  POSIX.
- "in both `release` and `--resume` modes (common_preflight runs in both)" —
  verified by running `--resume` (above), not only by reading the call site.
- "`$branch` (not a hardcoded "main")" — verified by the `master` fixture.
- The decision-3 paragraph matches `outline.md` clause for clause.

No surviving comment in the block asserts something the code does not do.

### Rendered message widths, measured

`hint:` opener 38–41 cols; the two continuation lines 73–79 and 46 cols. All
under 80. The longest is the `branch.<name>.pushRemote` form; a long default
branch name pushes it over, which is the interpolation-driven overflow the slice
6 review recorded as this file's existing behaviour (`check-version.sh`'s drift
line and `:310`'s hint have the same property). Continuation indent is six
spaces under `hint: `, the file's convention. Everything goes to stderr.

### File length — 731 lines. Observation added. Not split.

676 at the slice 6 review, 708 at `5fa9e0d`, **731** after this pass. My change
is `+33 / -10`; 23 of the 33 added lines are comment, 10 are code.

New observation, and it cuts against the tag-listing seam the two prior reviews
declined: the growth has now moved into `common_preflight` as well. That
function is 103 lines at `5fa9e0d` and 126 now, and it has accumulated four
unrelated preflight concerns — tree cleanliness, branch identity, push route,
marketplace reachability — none of which share a variable with the tag helpers.
So the file now has *two* functions growing independently of the named seam,
`release_preflight` (slice 6's observation) and `common_preflight`. Splitting
out `semver_tags`/`release_tags`/`origin_release_tags` would shrink neither. If
the Phase 1 boundary takes the decision, the honest seam is a per-concern split
of the preflight functions, not the tag listers — and that is a larger change
than "move three helpers to a second file", which is itself a new *shipped* path
dragging `tests/dist-tree-test.sh` and CLAUDE.md's Layout list with it.
**Still a recorded open decision. Still declined here.**

### Slice 2 / Item 1.4 — flagged, not built

`resume_preflight` is untouched. No `--resume`-specific assertion was added and
no Item 1.4 work was started. The `--resume` behaviour observed above is a
consequence of `common_preflight`'s existing call site, not new code.

## Nothing UNFIXABLE

Every defect found in scope was fixed in this pass. The newline-in-a-value
display bound is recorded, not unfixable-but-ignored: it is a genuine limit of
`git config`'s output format under command substitution, it is strictly improved
over `5fa9e0d`, and it is documented inline where the next reader meets it.

## State on exit

- `toolkit/release.sh` — **modified, uncommitted.** `git diff --stat` reads
  `1 file changed, 33 insertions(+), 10 deletions(-)`, all of it §1's read and
  message change, §3's `local`, and their comments. `git status --short` shows
  that file and nothing else.
- No SUT mutation was applied to `toolkit/release.sh`. The status-absorption
  probe ran against a **copy** of the loop in a scratch script with a stubbed
  `git` function, so the file was never in a mutated state.
- `bash tests/release-test.sh` — green, `all release scenarios passed`, **49**
  scenarios (`grep -c '^echo "=== '`). All 18 assertions in the
  diverged-push-route block pass.
- `just precommit` — green, `ok`. `bash -n`, `shellcheck`, `_import-check`,
  `tests/hook-test.sh`, `tests/release-test.sh`,
  `tests/update-plugin-dev-test.sh`, `tests/dist-tree-test.sh`
  (`dist tree ok (9 files, no gitlink)`), `tests/docs-test.sh`
  (`docs ok (cap 400 lines, pointers resolve)`), `tests/doc-sync-test.sh`
  (`doc sync ok (5 shared command blocks, Layout matches toolkit/)`).
- **Nothing committed. Nothing staged.**
- `tests/release-test.sh` untouched; the `pushtarget` fixture not renamed; the
  `ls-remote | cut` captures at `:438,466,562` not touched.
- `$TMPDIR` was unset in this dispatch shell; every probe, fixture and scratch
  file went to `/tmp/claude-1000/s1cr/`. Nothing left in the repo root.
