# Item 3.2 — execution report

`tests/version-guard-test.sh`: the stale `guard_out` read (N4) and the `vnext`
half's two missing assertions (N6).

## What changed

### N4 — fresh capture, not a stale read

`tagless_sysmsg` (slice 3) previously read `$guard_out` left over from the
no-tags run forty lines and two assertion blocks earlier, with no comment
disclosing the reuse. Inserted a fresh `run_guard` against `$git_proj`
immediately before the capture, with the same payload/fixture as the no-tags
scenario. The comment states both that the capture is deliberately fresh and why
it differs from its neighbour — the `$reason` reuse in slice 2 stays a
documented reuse because its own run is immediately adjacent (nothing can land
between the run and the read), while this capture is fresh because its run was
forty lines away and a scenario inserted between would have silently retargeted
a byte-identity comparison.

### N6 — the `vnext` block's two missing assertions

Added, in the file's current glob-form idiom (Item 3.4 converts these later, not
this item):

```sh
assert_no_escape_hatch "$reason" "version-guard vnext-tags reason"
assert_not_contains "$reason" "just release" \
    "version-guard vnext-tags reason: initial-release branch names no recipe invocation"
```

placed directly after the vnext block's existing two assertions
(`never been released` / `no last-released wording`).

### Comment update, the no-tags site

The comment above the no-tags `assert_not_contains "$reason" "just release"`
previously claimed the property is "[a]sserted over the no-tags reason alone:
the steady-state message names the recipe legitimately" — falsified by the new
`vnext` assertion above. Rewritten to say the property is asserted here and
again over the `vnext` reason (slice 4), both taking the same initial-release
branch, and that the steady-state message alone is exempt because it is the only
one that names the recipe legitimately.

## Gate 1 — N4, two steps

**Step 1** (insertion, suite must stay green): inserted a `run_guard` of the
pre-existing "unrelated file: allow" scenario (`$proj`, `README.md`,
`old_string a -> new_string b`) immediately above the re-invocation.

```
$ bash tests/version-guard-test.sh 2>&1 | tail -5
=== version-guard (leaked GIT_DIR cleared: initial-release wording) ===
=== version-guard (git listing fails: steady-state wording, empty stderr) ===
=== version-guard (semver filter fails: steady-state wording) ===

all version-guard scenarios passed
```

Green — the fresh capture is insulated from the inserted allow run.

**Step 2** (with the insertion still in place, delete the re-invocation):

```
$ bash tests/version-guard-test.sh 2>&1 | tail -10
=== version-guard (BSD realpath, unrelated file: allow) ===
=== version-guard (no tags: initial-release wording) ===
=== version-guard (v1.2.3 tag: steady-state wording) ===
FAIL: version-guard systemMessage byte-identical across tagless and tagged fixtures: expected '', got 'version-guard: blocked plugin.json version edit (1.2.3 -> 9.9.9)'
=== version-guard (vnext/v1.2 tags only, no semver tag: initial-release wording) ===
...
1 failure(s)
```

Red — `tagless_sysmsg` read the allow run's absent `.systemMessage` (empty
string), and `assert_eq` against the tagged run's non-empty systemMessage failed
exactly as predicted.

Both edits reverted before the N6 gate. Confirmed with:

```
$ git diff -- tests/version-guard-test.sh
```

showing only the intended N4/N6 changes (no allow insertion, re-invocation
restored) — reproduced in full below under "Diff after revert, before N6 gate"
for the reviewer to check against the commit.

## Gate 2 — N6

Added an escape-hatch sentence to the initial-release deny reason in
`toolkit/version-guard.sh` (the shared heredoc at the "Do not bypass this
guard…" line):

```
Do not bypass this guard, modify the recipe, or alter version state by
other means. You can disable this hook in .claude/settings.json and retry
the edit.
```

```
$ bash tests/version-guard-test.sh 2>&1 | grep FAIL
FAIL: version-guard no-tags reason: names no hook-config file: expected NOT to contain 'settings.json', got 'plugin.json version edit refused: 1.2.3 -> 9.9.9. ...'
FAIL: version-guard vnext-tags reason: names no hook-config file: expected NOT to contain 'settings.json', got 'plugin.json version edit refused: 1.2.3 -> 9.9.9. ...'
```

Red on both the pre-existing no-tags `assert_no_escape_hatch` and the new
`vnext` one — both read the same initial-release branch, so both catch the
mutation.

Reverted; confirmed:

```
$ git diff --quiet -- toolkit/version-guard.sh && echo clean
clean
$ bash tests/version-guard-test.sh 2>&1 | tail -3
=== version-guard (semver filter fails: steady-state wording) ===

all version-guard scenarios passed
```

## Gate 3 — additive falsifiability sweep

**Identified shared refusal mechanism.** `toolkit/version-guard.sh` has no
`die()`-equivalent function — it is a `PreToolUse` hook, so every scenario's
deny flows through the single terminal `jq -nc` call that builds
`{hookSpecificOutput: {..., permissionDecision: "deny", ...}, systemMessage: ...}`
and writes it to stdout with exit 0. That is the literal analogue of
`release.sh`'s `die()`: the one site every deny passes through regardless of
branch. I first tried mutating that site directly (`permissionDecision: "deny"`
-> `"allow"`); it defeated every pre-existing `assert_deny` call (11 scenarios
went red: `no deny decision on stdout`) but left both of this item's new
assertions green, because `assert_no_escape_hatch` and the new
`assert_not_contains … "just release"` read only the reason *text*, which that
mutation does not touch — so it proved nothing about this item's own additions.
Reverted that probe (`git diff --quiet` confirmed clean) and moved to the
mechanism that actually feeds both new assertions and the N6 gate: the single
initial-release `agent_reason` heredoc
(`This plugin has never been released …`), shared by the no-tags, `vnext`, and
git-dir-leak scenarios alike — the thing the no-tags and `vnext` sites' comments
both call "the same initial-release branch". The N6 gate already proved
`assert_no_escape_hatch` on `vnext` is falsifiable; it left the second new
assertion, `assert_not_contains "$reason" "just release"` on `vnext`, with no
dedicated gate anywhere in the item's own mutation set. The sweep targets
exactly that gap.

**Mutation:** added a "run `just release {patch|minor|major}` when ready" clause
inside the shared initial-release heredoc:

```
first ships as is the maintainer's call and their edit to make -- run
'just release {patch|minor|major}' when ready.
```

```
$ bash tests/version-guard-test.sh 2>&1 | grep FAIL
FAIL: version-guard no-tags reason: initial-release branch names no recipe invocation: expected NOT to contain 'just release', got '...'
FAIL: version-guard vnext-tags reason: initial-release branch names no recipe invocation: expected NOT to contain 'just release', got '...'
```

Exactly two failures: the pre-existing no-tags
`assert_not_contains … "just release"` and this item's new `vnext` one. Both
went red — the second new assertion (`assert_not_contains … "just release"` on
`vnext`), previously untested for falsifiability by any of this item's own
gates, is confirmed capable of failing.

Reverted; confirmed:

```
$ git diff --quiet -- toolkit/version-guard.sh && echo clean
clean
$ bash tests/version-guard-test.sh 2>&1 | tail -3
=== version-guard (semver filter fails: steady-state wording) ===

all version-guard scenarios passed
```

**Outcome.** No newly-added assertion stayed green under a mutation targeted at
its own mechanism: `assert_no_escape_hatch` on `vnext` was proven falsifiable by
the N6 gate, and `assert_not_contains … "just release"` on `vnext` was proven
falsifiable by this sweep. No pre-existing assertion stayed green when it should
have caught a mutation — the no-tags sibling of each new assertion went red
alongside it in both gates. Nothing here contradicts the runbook and no
production defect was found; the sweep is complete, both probe mutations fully
reverted.

## `just precommit`

Green (all nine suites, `_import-check`, 400-line cap, doc-sync, `whitespace`,
`format-docs`). One earlier combined run showed a single `release-test.sh` flake
(`first-release 'major' names the remedy for wanting another version`) that did
not reproduce when `tests/release-test.sh` was run standalone immediately after,
or in the subsequent full `just precommit` run that landed the commit —
unrelated to this item's file (`tests/version-guard-test.sh`), which was the
only path modified in the working tree at the time.

## Diff after revert, before N6 gate

```diff
--- a/tests/version-guard-test.sh
+++ b/tests/version-guard-test.sh
@@ -341,9 +341,11 @@ assert_not_contains "$reason_minus_refusal" "9.9.9" \
 # rather than $proposed (release.sh:456-460), so in THIS branch every mention
 # of the invocation routes the agent at something nobody asked for -- which
 # is why the fix withheld the identifier instead of qualifying it. Asserted
-# over the no-tags reason alone: the steady-state message names the recipe
-# legitimately. Residual bound: prose that routes at the recipe without
-# naming it ("when the release recipe runs") still passes here.
+# here and again over the vnext reason below (slice 4), which takes the same
+# initial-release branch -- the steady-state message is the only one that
+# names the recipe legitimately, so it alone is exempt from this assertion.
+# Residual bound: prose that routes at the recipe without naming it ("when
+# the release recipe runs") still passes here.
 assert_not_contains "$reason" "just release" \
     "version-guard no-tags reason: initial-release branch names no recipe invocation"
 assert_no_escape_hatch "$reason" "version-guard no-tags reason"
@@ -351,7 +353,16 @@ assert_no_escape_hatch "$reason" "version-guard no-tags reason"
 # Slice 3: only the agent channel (permissionDecisionReason) may branch on
 # release state. systemMessage is a factual one-liner, true in both states,
 # so it must come out byte-identical for the same payload whichever fixture
-# answers it.
+# answers it. Re-invoke the hook here, deliberately fresh, rather than reuse
+# $guard_out from the no-tags run forty lines above: that capture is two
+# assertion blocks away, so a scenario inserted between would silently
+# retarget this byte-identity comparison. That is the opposite call from
+# the $reason reuse just above (slice 2) -- that reuse stays documented and
+# undisturbed because its run is immediately adjacent, with nothing able to
+# land between it and the read.
+run_guard "$(jq -nc --arg cwd "$git_proj" --arg fp "$git_proj/.claude-plugin/plugin.json" \
+    '{cwd:$cwd, tool_name:"Edit", tool_input:{file_path:$fp, old_string:"1.2.3", new_string:"9.9.9"}}')" \
+    "$git_proj"
 tagless_sysmsg="$(jq -r '.systemMessage' <<<"$guard_out")"

 echo "=== version-guard (v1.2.3 tag: steady-state wording) ==="
@@ -379,6 +390,12 @@ assert_deny "version-guard vnext-tags"
 reason="$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<<"$guard_out")"
 assert_contains "$reason" "never been released" "version-guard vnext-tags reason: never-released wording"
 assert_not_contains "$reason" "last released version" "version-guard vnext-tags reason: no last-released wording"
+# Same initial-release branch as the no-tags case above, so the same two
+# properties apply: no escape hatch, and no recipe invocation -- this reason
+# is not the steady-state message, which alone is exempt from the latter.
+assert_no_escape_hatch "$reason" "version-guard vnext-tags reason"
+assert_not_contains "$reason" "just release" \
+    "version-guard vnext-tags reason: initial-release branch names no recipe invocation"

 # Slice 5: the guard clears repo-local GIT_* variables before listing tags,
 # so a leaked GIT_DIR (e.g. a `claude` process started from inside a git
```

This is exactly what landed (the commit below is this diff, unchanged).

## Commit

`71bdf3124267d4cdf6364b397084bbd2b2f4626a` — "✅ Item 3.2 — fresh capture and
the vnext block's two missing assertions" (the pre-commit gitmoji hook prepended
the emoji; message text otherwise as given).

```
$ git show --stat HEAD
commit 71bdf3124267d4cdf6364b397084bbd2b2f4626a
Author: David Allouche <david@ddaa.net>
Date:   Sun Sep 20 20:41:05 2026 +0200

    ✅ Item 3.2 — fresh capture and the vnext block's two missing assertions

 tests/version-guard-test.sh | 25 +++++++++++++++++++++----
 1 file changed, 21 insertions(+), 4 deletions(-)
```

`.claude/` appears nowhere in that stat —
`git show --stat HEAD | grep -i claude` matched nothing.

`git status --short` after the commit still shows `.claude/handoff-task.md` and
`.claude/handoff-todo.md` staged (pre-existing, untouched by this commit), plus
this sandbox's usual untracked dotfile masks (`.bashrc`, `.zshrc`,
`.claude/agents`, `.idea`, `.vscode`, …) — none of it from this item's work.
`memory` did not need `git add`: `git status --short` shows no `memory` change,
`git -C memory status --short` is clean, and `git ls-tree HEAD memory`
(`332096d346009349b3ac690ecf5edfc34b17e1dc`) already equals
`git -C memory rev-parse HEAD`.

## For Item 3.4

The two new call sites, verbatim, in the file's current glob-form idiom (not yet
converted to `grep -q --`):

```sh
assert_no_escape_hatch "$reason" "version-guard vnext-tags reason"
assert_not_contains "$reason" "just release" \
    "version-guard vnext-tags reason: initial-release branch names no recipe invocation"
```

(`assert_no_escape_hatch` itself internally calls `assert_contains` once and
`assert_not_contains` twice, per its existing body — those three call sites also
convert under 3.4's count and are unchanged by this item.)
