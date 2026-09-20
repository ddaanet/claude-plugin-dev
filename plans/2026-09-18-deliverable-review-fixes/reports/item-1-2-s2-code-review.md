# Item 1.2 / slice 2 — code review

**Scope:** `toolkit/release.sh` as changed by `a69c97f` — `resume_preflight`'s
hint ladder membership test and its comment. **Date:** 2026-09-20 **Mode:**
review + fix

## Verdict

**Ready.** No issues found; no fixes applied. The change is exactly the
herestring form the runbook names, at the right site, with `-qxF --` carried
over unchanged. Semantics are identical to the pipe form across every listing
shape checked, the mutation reds the `at 1MB` scenario on both its assertions,
and the file was restored byte-for-byte.

N1 is satisfied: the membership test no longer contains a pipe, so no `printf`
SIGPIPE status exists for `pipefail` to promote, at any listing size.

## Evidence

### 1. The replacement, and no pipe left behind

`git show a69c97f -- toolkit/release.sh` is a single hunk, 7 lines, one
deletion, inside `resume_preflight`'s `|| { … }` hint ladder:

```sh
-        if printf '%s\n' "$origin_tag_list" | grep -qxF -- "$tag"; then
+        if grep -qxF -- "$tag" <<<"$origin_tag_list"; then
```

`-qxF --` carried over verbatim.
`grep -n '|[[:space:]]*grep' toolkit/release.sh` returns nothing — no `… | grep`
remains anywhere in the file. The four surviving `printf … |` pipes (lines 329,
358, 400, 514) are `semver_tags`/`cut`/`sed -n` stages inside `semver_tags`,
`release_tags`, `origin_release_tags` and `release_preflight` — none is a
membership test, none is in this ladder, and all are Item 1.1 territory, already
reviewed and out of scope. No new pipe was introduced; the hunk adds one
herestring and nothing else.

### 2. Semantics preserved, not just the happy path

`$(…)` strips trailing newlines, so `$origin_tag_list` never ends with one; both
`printf '%s\n' "$x"` and `<<<"$x"` then append exactly one. The "last line has
no newline" case therefore cannot arise, and the empty case is the same single
empty line under both forms — which is what the pre-existing `-x` comment above
the site already relies on. Verified against `/usr/bin/grep` (not the ugrep
shell wrapper) over empty / single-entry / three-entry listings crossed with hit
/ miss / last-entry-hit tags:

```
list=''                             tag=v1.0.0 pipe=1 here=1 SAME
list=''                             tag=v9.9.9 pipe=1 here=1 SAME
list=''                             tag=v2.0.0 pipe=1 here=1 SAME
list=v1.0.0                         tag=v1.0.0 pipe=0 here=0 SAME
list=v1.0.0                         tag=v9.9.9 pipe=1 here=1 SAME
list=v1.0.0                         tag=v2.0.0 pipe=1 here=1 SAME
list=$'v1.0.0\nv1.1.0\nv2.0.0'      tag=v1.0.0 pipe=0 here=0 SAME
list=$'v1.0.0\nv1.1.0\nv2.0.0'      tag=v9.9.9 pipe=1 here=1 SAME
list=$'v1.0.0\nv1.1.0\nv2.0.0'      tag=v2.0.0 pipe=0 here=0 SAME
empty list, empty tag:                         pipe=0 here=0 SAME
```

The empty-list/empty-tag row is the one shape where `-x` matches the lone empty
line — and it matches identically under both forms, so the swap introduces
nothing. It is unreachable in any case: `tag="v$V"` is never empty. No ladder
branch depends on the empty-list return of this test: the next branch re-tests
`[ -n "$origin_tag_list" ]` on the variable directly.

### 3. The comment

It names the mechanism (`grep -q` exits on first match, `printf` dies on
SIGPIPE, `pipefail` promotes 141 over 0) and cites `toolkit/version-guard.sh`'s
tag filter with a short quoted fragment, `grep -E '…' <<<"$listing"`. No
`<script>.sh:<line>` form. The cited site is at version-guard.sh's top level —
`abspath()` is that file's only function — so "tag filter" plus the fragment is
the strongest symbolic handle available there, and it is unambiguous: that is
the file's only `grep -E … <<<` line. Correct as written.

### 4. Cost and `$TMPDIR`

bash 5.2. Above the pipe-buffer threshold a herestring spills to a temp file, so
a 1 MB listing is a real write. Measured over a 1,208,889-byte listing with
`/usr/bin/grep`: **43 ms** on a first-line hit, **44 ms** on a full-scan miss.
Negligible against the `git ls-remote` the same ladder already paid for, and ~1
MB against a 2 G `/tmp` tmpfs is not a pressure point. No `$TMPDIR` or scratch
path is baked into `release.sh`; bash resolves it, and the file already had a
herestring at line 208 (`done <<<"$push_values"`) plus the whole of
`version-guard.sh` on the same footing, so this adds no new assumption.

### 5. Whitespace safety

Both operands are quoted: `grep -qxF -- "$tag" <<<"$origin_tag_list"`. No word
splitting, no glob expansion, and the `--` still stops a `$tag` beginning with
`-` from being read as an option. Exposure is identical to the pipe form — a
whitespace-bearing `$V` yields a `$tag` that `-x` simply cannot match, before
and after alike.

### 6. Item 1.1's functions undisturbed

The commit's `toolkit/release.sh` diff is the single hunk above. `release_tags`,
`semver_tags` and `origin_release_tags` are untouched.

## Mutation run

Saved the file, restored the pipe in place, ran `bash tests/release-test.sh` in
the foreground once.

```
=== the origin probes fail closed with pipefail stripped ===
=== pipefail-stripped release_tags failure refuses ===
=== pipefail-stripped release_tags failure publishes nothing ===
=== resume hint names the tag already on origin ===
=== resume hint names the tag already on origin at 1MB ===
FAIL: resume hint names the tag already on origin at 1MB: output did not contain 'origin already has v1.2.3'
  --- output ---
hint: origin has release tags, but none matching v1.2.3.
      run `git fetch --tags`, then run `just release <bump>`.
error: no tag v1.2.3 for plugin.json version 1.2.3
  --------------
FAIL: resume hint names the tag already on origin at 1MB must not advise a fresh release: output contained 'just release'
  --- output ---
hint: origin has release tags, but none matching v1.2.3.
      run `git fetch --tags`, then run `just release <bump>`.
error: no tag v1.2.3 for plugin.json version 1.2.3
  --------------

2 failure(s)
```

Both of the `at 1MB` scenario's discriminating assertions redded, and the
failure output is the exact wrong-branch symptom the item predicts: the
membership test returned non-zero despite origin holding `v1.2.3`, so the ladder
fell through to the "none matching" branch and advised a fresh release. Every
other scenario stayed green, including slice 1's small-listing
`resume hint names the tag already on origin` — expected, since below the pipe
buffer `printf` completes before `grep` exits and there is no SIGPIPE to
promote. That is the polarity the runbook states, confirmed empirically.

Restore:

```
$ cp "$TMPDIR/release.sh.bak" toolkit/release.sh
$ git diff --quiet -- toolkit/release.sh && echo "RESTORE OK: git diff --quiet exit 0"
RESTORE OK: git diff --quiet exit 0
$ git status --porcelain -- toolkit/release.sh
(no output)
$ ls -l toolkit/release.sh
-rwxr-xr-x 1 david david 49789 Sep 20 18:44 toolkit/release.sh
```

Clean, and the executable bit is preserved. Tests were never relocated.

## Independent checks

- `shellcheck -S style toolkit/release.sh` — clean.
- `bash -n toolkit/release.sh` — ok.

## Issues found

None. Nothing to fix, nothing deferred, nothing unfixable.

## Refactoring flags

None. `REFACTOR-NEEDED` is not raised: the change is one line inside an existing
ladder and introduces no structure.

## Positive observations

- The new comment merges into the existing flag-rationale block above the site
  rather than opening a parallel one, so the `-F` / `-x` / herestring reasons
  read as one argument about the same statement.
- Argument order was flipped to put `-- "$tag"` before the redirect, which is
  the only order a herestring permits and matches `version-guard.sh`'s form.
- The item's warning against locating the site by `:577` was heeded — the site
  is at 595 after Item 1.1, and the change landed on it.
