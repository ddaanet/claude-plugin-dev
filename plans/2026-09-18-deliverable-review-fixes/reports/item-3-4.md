# Item 3.4 — execution report

`tests/version-guard-test.sh`: `assert_contains` and `assert_not_contains`
converge on the `grep -q --` form (N8).

## Call-site count

Counted at HEAD (after Items 3.2's and 3.3's landed additions), by
`grep -n 'assert_contains\|assert_not_contains' tests/version-guard-test.sh`
minus the two definitions:

- **8** `assert_contains` call sites (lines 254, 343, 344, 397, 433, 453, 474,
  497 pre-conversion — same lines post-conversion since the diff adds no line
  above them)
- **12** `assert_not_contains` call sites (257, 258, 345, 357, 372, 398, 420,
  434, 439, 455, 476, 499 pre-conversion)
- **20 total**, matching the task's measured census exactly.

`assert_no_escape_hatch`'s body carries **3** of these twenty call sites: one
`assert_contains` (the no-bypass sentence) and two `assert_not_contains`
(`settings.json`, `version-guard`) — not three `assert_not_contains` as the
task's summary sentence could be read; the task's own three-item bullet list for
this hazard confirms the same breakdown (one contains + two not-contains). No
count discrepancy — proceeded without stopping.

## The two helper bodies

**Before:**

```sh
assert_contains() {
    # $1=haystack $2=needle $3=label. Match against a specific extracted
    # field (e.g. permissionDecisionReason alone), never the whole payload
    # blob -- an unrelated line can satisfy a needle and hide the miss.
    if [[ "$1" != *"$2"* ]]; then
        fail "$3: expected to contain '$2', got '$1'"
    fi
}
assert_not_contains() {
    # $1=haystack $2=needle $3=label
    if [[ "$1" == *"$2"* ]]; then
        fail "$3: expected NOT to contain '$2', got '$1'"
    fi
}
```

**After** (converged on the `grep -q --` form and failure-output shape used by
`release-test.sh`, `self-release-test.sh` and `update-plugin-dev-test.sh`; the
haystack-constraint comment on `assert_contains` survives unchanged):

```sh
assert_contains() {
    # $1=haystack $2=needle $3=label. Match against a specific extracted
    # field (e.g. permissionDecisionReason alone), never the whole payload
    # blob -- an unrelated line can satisfy a needle and hide the miss.
    if ! printf '%s' "$1" | grep -q -- "$2"; then
        fail "$3: output did not contain '$2'"
        printf '  --- output ---\n%s\n  --------------\n' "$1" >&2
    fi
}
assert_not_contains() {
    # $1=haystack $2=needle $3=label
    if printf '%s' "$1" | grep -q -- "$2"; then
        fail "$3: output contained '$2'"
        printf '  --- output ---\n%s\n  --------------\n' "$1" >&2
    fi
}
```

Verified this matches the other three suites' bodies and diagnostic shape by
reading `tests/release-test.sh:30-43`, `tests/self-release-test.sh:34-47` and
`tests/update-plugin-dev-test.sh:32-45` — all four now identical.

## Two-axis needle re-read (all 20 call sites, plus the needles 3.2/3.3 added)

| Line | Helper | Needle | BRE-live chars | Widens to | Still matches | Spans a newline |
|---|---|---|---|---|---|---|
| 254/256 | assert_contains | `Do not bypass this guard, modify the recipe, or alter version state by` | none | — | yes (literal) | no — cut before the heredoc's own line break, see hazard 3 below |
| 257/259 | assert_not_contains | `settings.json` | `.` (dot) | any-char | yes, still matches (absence asserted; widening only risks false-failure here, which is the loud direction) | no |
| 258/260 | assert_not_contains | `version-guard` | none | — | yes | no |
| 343/345 | assert_contains | `never been released` | none | — | yes | no |
| 344/346 | assert_contains | `will publish` | none | — | yes | no |
| 345/347 | assert_not_contains | `last released version` | none | — | yes | no |
| 357/359 | assert_not_contains | `9.9.9` | `.` `.` | any-char | yes | no |
| 372/374 | assert_not_contains | `just release` | none | — | yes | no |
| 397/399 | assert_contains | `last released version` | none | — | yes | no |
| 398/400 | assert_not_contains | `never been released` | none | — | yes | no |
| 420/422 | assert_not_contains | `tag${US}--list` (raw \037 byte) | none (BRE metachars none; the \037 byte is not a BRE metacharacter) | — | yes, verified empirically (hazard 1 below) | no — single log line (hazard 2 below) |
| 433/435 | assert_contains | `never been released` | none | — | yes | no |
| 434/436 | assert_not_contains | `last released version` | none | — | yes | no |
| 439/441 | assert_not_contains | `just release` | none | — | yes | no |
| 453/455 | assert_contains | `never been released` | none | — | yes | no |
| 455/457 | assert_not_contains | `last released version` | none | — | yes | no |
| 474/476 | assert_contains | `last released version` | none | — | yes | no |
| 476/478 | assert_not_contains | `never been released` | none | — | yes | no |
| 497/499 | assert_contains | `last released version` | none | — | yes | no |
| 499/501 | assert_not_contains | `never been released` | none | — | yes | no |

Across all 20, the only BRE-live characters are the dots in `9.9.9` and in
`settings.json`, confirming the runbook's claim exactly — both widen to any-char
and both still match their intended text, so no needle needed escaping. No
needle among the pre-existing eighteen or the two 3.2/3.3 added
(`assert_no_escape_hatch "$reason" "…vnext-tags reason"` and
`assert_not_contains "$reason" "just release" "…vnext-tags reason: …"`, both
reusing already-tabulated needle text) or the one 3.3 added (`"tag${US}--list"`)
spans a newline.

## The three hazards, resolved individually

**1. The raw Unit Separator byte in Item 3.3's needle (`"tag${US}--list"`)
survives the shell round-trip into `grep -q --`'s pattern argument.** Verified
empirically, not assumed: built a two-line log in the same `\037`-joined shape
the recording stub produces and ran
`printf '%s' "$haystack" | grep -q -- "tag${US}--list"`:

```
$ bash -c '
US="$(printf "\037")"
tmp="$(mktemp)"
printf "%s\037%s\037%s\037\n" "-C" "/tmp/x" "tag" >> "$tmp"
printf "%s\037%s\037\n" "tag" "--list" >> "$tmp"
haystack="$(cat "$tmp")"
if printf "%s" "$haystack" | grep -q -- "tag${US}--list"; then echo MATCH; else echo NOMATCH; fi
rm -f "$tmp"
'
MATCH
```

The byte 037 is not a BRE metacharacter, so `grep -q --` treats it as an
ordinary literal byte in the pattern, exactly as the glob form did — the needle
still matches. Confirmed further by the live mutation gate below, where the
recorded log line for a real hook-triggered `git tag --list` invocation matched
the needle under the post-conversion `grep -q --` form (see Gate 1, "same set"
below — the N5 scenario passed identically before and after conversion, and Item
3.3's own mutation gate — reproduced verbatim in its report — already showed the
identical failure line (`-C/tmp/.../tag--listv*--sort=-v:refname`, a display
artifact of the non-printing separator) firing correctly under the
pre-conversion glob form; this item's before/after comparison confirms the same
needle still fires identically under `grep -q --`).

**2. That assertion's haystack (`$(cat "$guard_recordgit_log")`) is multi-line,
and the needle lies within a single line.** The recording stub
(`tests/version-guard-test.sh:189-192`, unchanged by this item) writes one line
per `git` invocation, each line built as
`printf '%s\037' "$@" >> log; printf '\n' >> log` — arguments joined by `\037`
within a line, then a real newline terminates that line before the next
invocation's fields start. `tag` and `--list` are two arguments of the *same*
single `git -C <project> tag --list v* --sort=-v:refname` call, so both fall
inside one `printf '\037'`-joined burst that ends with a single `\n` — the
needle `tag${US}--list` cannot span two `git`-invocation lines by construction,
only two arguments of the same invocation, which stay on one physical line.
Under the glob form (which matches across newlines) this needle would have
matched a hypothetical case where `tag` ended one invocation's line and `--list`
began the next; that case cannot arise here because `tag` and `--list` are two
words of one `git` command, but the newline-span axis is exactly the property
that would have differed silently if it could. Verified by reading the stub's
write loop and by the `assert_not_contains` gate's own behaviour below (its
failure line under the runbook's mutation shows the recorded invocation as one
continuous `-C … tag--listv*--sort=-v:refname` string with no gap corresponding
to a line break).

**3. `assert_no_escape_hatch`'s positive needle**
(`"Do not bypass this guard, modify the recipe, or alter version state by"`)
still lands within one physical line after Items 3.2 and 3.3, which touched only
`tests/version-guard-test.sh`, not `toolkit/version-guard.sh`. Read the current
production file directly:

```
$ grep -n 'Do not bypass\|modify the recipe\|alter version state' toolkit/version-guard.sh
156:Do not bypass this guard, modify the recipe, or alter version state by
171:file. Do not bypass this guard, modify the recipe, or alter version state by
```

Both occurrences (the initial-release branch at 148-158 and the steady-state
branch at 162-173) still break the sentence exactly after "...alter version
state by" / before "other means." on the next physical heredoc line — the needle
is deliberately cut there and both call sites (line 256 for the initial-release
reason via `assert_no_escape_hatch`, and line 399/439 for the steady-state and
vnext reasons) still match under `grep -q --`, which reads line-by-line: the
needle's final word "by" is the last token on its line, so no reason text was
rewrapped under it and the cut remains correct.

## Gate 1 — the runbook's own gate: before/after scenario-set comparison

**Before conversion** (pre-existing glob form):

```
$ bash tests/version-guard-test.sh 2>&1 | tail -3
=== version-guard (semver filter fails: steady-state wording) ===

all version-guard scenarios passed
```

15 `===` scenario lines printed, all passing.

**After conversion** (`grep -q --` form):

```
$ bash tests/version-guard-test.sh 2>&1 | tail -3
=== version-guard (semver filter fails: steady-state wording) ===

all version-guard scenarios passed
```

Same 15 `===` scenario lines, identical text. Confirmed with
`diff before.log after.log` → `IDENTICAL` (byte-for-byte, both full captured
runs). Same set, not just same count.

**Weakened positive-needle probe.** Added one extra character to a positive
`assert_contains` needle:

```diff
-assert_contains "$reason" "never been released" "version-guard no-tags reason: never-released wording"
+assert_contains "$reason" "never been releasedX" "version-guard no-tags reason: never-released wording"
```

```
$ bash tests/version-guard-test.sh 2>&1 | grep -A2 FAIL
FAIL: version-guard no-tags reason: never-released wording: output did not contain 'never been releasedX'
  --- output ---
plugin.json version edit refused: 1.2.3 -> 9.9.9.
```

Failed under the new form, as required. Reverted:

```
$ git diff -- tests/version-guard-test.sh | grep -A3 -B3 'never been released'
(no output -- line matches HEAD exactly)
$ bash tests/version-guard-test.sh 2>&1 | tail -3
=== version-guard (semver filter fails: steady-state wording) ===

all version-guard scenarios passed
```

## Gate 2 — additive falsifiability sweep on the shared initial-release
`agent_reason` heredoc

Per the runbook, this item adds no assertions, so the sweep targets a production
mutation instead: the shared initial-release `agent_reason` heredoc in
`toolkit/version-guard.sh` (the mechanism Item 3.2 identified), run against the
file **before** and **after** conversion.

**Mutation** (same edit Item 3.2's own sweep used, reproduced verbatim):

```diff
 first ships as is the maintainer's call and their edit to make.
+run 'just release {patch|minor|major}' when ready.
```

Actual applied form (line 154 area):

```
first ships as is the maintainer's call and their edit to make -- run
'just release {patch|minor|major}' when ready.
```

**Pre-conversion red set** (test file at the glob-form HEAD, obtained via
`git stash` to isolate the two states, then popped back):

```
$ bash tests/version-guard-test.sh 2>&1 | grep FAIL
FAIL: version-guard no-tags reason: initial-release branch names no recipe invocation: expected NOT to contain 'just release', got 'plugin.json version edit refused: 1.2.3 -> 9.9.9.
FAIL: version-guard vnext-tags reason: initial-release branch names no recipe invocation: expected NOT to contain 'just release', got 'plugin.json version edit refused: 1.2.3 -> 9.9.9.
```

Exactly 2 failures: the no-tags and vnext-tags
`assert_not_contains … "just release"` assertions.

**Post-conversion red set** (test file with the `grep -q --` conversion
restored, same production mutation reapplied):

```
$ bash tests/version-guard-test.sh 2>&1 | grep FAIL
FAIL: version-guard no-tags reason: initial-release branch names no recipe invocation: output contained 'just release'
FAIL: version-guard vnext-tags reason: initial-release branch names no recipe invocation: output contained 'just release'
```

Exactly the same 2 failures, same two labels — only the diagnostic message text
differs (expected, since the two helpers' failure-output shape changed as part
of this item). **Same set before and after.** No check that redded before failed
to red after, and no other check redded that hadn't before.

Reverted the production mutation and confirmed:

```
$ git diff --quiet -- toolkit/version-guard.sh && echo clean
clean
$ bash tests/version-guard-test.sh 2>&1 | tail -3
=== version-guard (semver filter fails: steady-state wording) ===

all version-guard scenarios passed
```

No production defect found; both mutation probes (weakened-needle and
shared-heredoc) fully reverted before committing.

## `just precommit`

Green on the run immediately before committing (all nine suites,
`_import-check`, 400-line cap, doc-sync, `whitespace`, `format-docs`).

The pre-commit hook's own `just precommit` run hit the runbook's named
known-intermittent: `tests/release-test.sh` failed two scenarios
(`staged frame: HEAD is the release commit` and
`first-release 'minor' names committing the version edit`) — not the
identically-named "first-release 'major' names the remedy for wanting another
version" flake in the task's warning, but the same file and the same class of
symptom (a `release-test.sh` scenario failing in a combined run and not
reproducing standalone). Re-ran `tests/release-test.sh` standalone immediately
after:

```
$ bash tests/release-test.sh 2>&1 | tail -3
=== resume hint names the tag already on origin at 1MB ===

all release scenarios passed
```

All scenarios passed standalone. Confirmed
`git diff --quiet -- toolkit/version-guard.sh` and
`git diff --quiet -- tests/release-test.sh` both clean at that point — no stray
change from this item's mutation probes was in the tree. Per the runbook's
instruction, not investigated further — out of scope, this item's own file
(`tests/version-guard-test.sh`) is unrelated to `release-test.sh`. The
subsequent full `just precommit` run (immediately before the successful commit)
was green with no `release-test.sh` failure.

## Commit

`f597b1c18d7a60a691e4b441e67d7339ac10925a` — "✅ Item 3.4 — version-guard
assertions converge on grep -q --" (the pre-commit gitmoji hook prepended the
emoji).

```
$ git show --stat HEAD
commit f597b1c18d7a60a691e4b441e67d7339ac10925a
Author: David Allouche <david@ddaa.net>
Date:   Sun Sep 20 21:06:47 2026 +0200

    ✅ Item 3.4 — version-guard assertions converge on grep -q --

 tests/version-guard-test.sh | 10 ++++++----
 1 file changed, 6 insertions(+), 4 deletions(-)
```

`git show --stat HEAD | grep -i claude` matched nothing — `.claude/` appears
nowhere in the commit. `git status --short` after the commit still shows
`.claude/handoff-task.md` and `.claude/handoff-todo.md` staged (pre-existing,
untouched by this commit), plus this sandbox's usual untracked dotfile masks.
`memory` needed no `git add`: `git status --short` shows no `memory` line,
`git -C memory status --short` is clean, and `git ls-tree HEAD memory`
(`332096d346009349b3ac690ecf5edfc34b17e1dc`) already equals
`git -C memory rev-parse HEAD`.

## Diff (full, as landed)

```diff
diff --git a/tests/version-guard-test.sh b/tests/version-guard-test.sh
index 9eafbfd..de0b8f7 100644
--- a/tests/version-guard-test.sh
+++ b/tests/version-guard-test.sh
@@ -37,14 +37,16 @@ assert_contains() {
     # $1=haystack $2=needle $3=label. Match against a specific extracted
     # field (e.g. permissionDecisionReason alone), never the whole payload
     # blob -- an unrelated line can satisfy a needle and hide the miss.
-    if [[ "$1" != *"$2"* ]]; then
-        fail "$3: expected to contain '$2', got '$1'"
+    if ! printf '%s' "$1" | grep -q -- "$2"; then
+        fail "$3: output did not contain '$2'"
+        printf '  --- output ---\n%s\n  --------------\n' "$1" >&2
     fi
 }
 assert_not_contains() {
     # $1=haystack $2=needle $3=label
-    if [[ "$1" == *"$2"* ]]; then
-        fail "$3: expected NOT to contain '$2', got '$1'"
+    if printf '%s' "$1" | grep -q -- "$2"; then
+        fail "$3: output contained '$2'"
+        printf '  --- output ---\n%s\n  --------------\n' "$1" >&2
     fi
 }
```

Only the two helper bodies changed — no call site, no comment beyond the one
comment (the haystack-constraint note on `assert_contains`) that survived
unchanged as instructed. Item 3.5 (not run here) still has comment-citation work
to do in this file.
