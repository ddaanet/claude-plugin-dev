# Item 1.4 — RED (all four slices, batched)

Scope: `tests/release-test.sh` only. `toolkit/release.sh` untouched. No commit.
Suite run: `bash tests/release-test.sh` from repo root — 7 failures total, all
in the scenarios below; every other scenario in the file (before and after
these) still passes. `bash -n` and `shellcheck` on the test file are clean.

## Summary

| Slice | Scenario (`echo "=== …"`) | Ladder branch selected | Fixture discriminator | Assertions red today |
|---|---|---|---|---|
| 1 | `resume: on a virgin repo, the hint has no bump argument` (`:376`) | 3rd (release_tags empty, origin probe empty) | `make_virgin` drops the tag from **both** local and origin — origin has nothing to name | 2 of 5 |
| 2 | `resume: refuses when no tag exists for the manifest version` (`:395`, rewritten in place) | 1st (v$V present on origin) | tag deleted **locally only**; origin keeps `v1.2.3` and `$V` is `1.2.3` — the two agree | 3 of 5 |
| 3 | `resume: a different semver tag on origin than v$V names the bump hint` (`:412`) | 2nd (some other semver tag on origin) | manifest hand-advanced to `1.3.0`; origin's only tag is `v1.2.3`, which is semver but not `$V` | 1 of 5 |
| 4a | `resume: keeping the local tag while origin drops it still advises the bump form` (`:433`) | 4th (today's default) | origin's `v1.2.3` deleted, local `v1.2.3` **kept** — release_tags non-empty, origin evidence empty | 0 of 5 (guard) |
| 4b | `resume: refuses cleanly … when origin has no remote to probe` (`:456`) | 3rd, reached via a **failed** probe (no `origin` remote) rather than an empty one | `make_virgin` + `git remote remove origin` | 1 of 5 |

## Slice 1 — external contract, virgin repo

```bash
echo "=== resume: on a virgin repo, the hint has no bump argument ==="
new_sandbox ""
make_virgin "0.1.0"
run_in "$plugin" bash plugin-dev/release.sh --resume
assert_eq "$rc" "1" "virgin resume exit code"
assert_contains "$out" "no tag v0.1.0 for plugin.json version 0.1.0" "virgin resume message"
assert_contains "$out" 'just release`' "virgin resume hint names just release with no bump argument"
assert_not_contains "$out" "just release <bump>" "virgin resume hint must not advise the bump form"
assert_eq "$(cat "$GH_LOG")" "" "virgin resume must not call gh"
```

Branch: `make_virgin` deletes the tag from the local clone AND pushes the
deletion to origin, and `new_sandbox ""` starts with no marketplace entry.
`origin_release_tags` therefore succeeds and returns an empty listing — that's
what selects the ladder's third branch (`release_tags` empty, no origin
evidence) rather than the fourth (nothing local to name) or the second (origin
has no tag to be "a different one" from).

Verbatim red output today:

```
=== resume: on a virgin repo, the hint has no bump argument ===
FAIL: virgin resume hint names just release with no bump argument: output did not contain 'just release`'
  --- output ---
hint: no release was started at this version.
      run `just release <bump>` instead.
error: no tag v0.1.0 for plugin.json version 0.1.0
  --------------
FAIL: virgin resume hint must not advise the bump form: output contained 'just release <bump>'
  --- output ---
hint: no release was started at this version.
      run `just release <bump>` instead.
error: no tag v0.1.0 for plugin.json version 0.1.0
  --------------
```

`exit code`, `virgin resume message` (the `die` text is unchanged by this item)
and `must not call gh` already pass today — they guard invariants the ladder
must not disturb, not new behaviour.

## Slice 2 — v$V on origin (rewrite of the existing `:376` scenario)

**Before** (what was there):

```bash
echo "=== resume: refuses when no tag exists for the manifest version ==="
new_sandbox "1.2.3"
git -C "$plugin" tag -d v1.2.3 >/dev/null
run_in "$plugin" bash plugin-dev/release.sh --resume
assert_eq "$rc" "1" "no-tag resume exit code"
assert_contains "$out" "no tag v1.2.3 for plugin.json version 1.2.3" "no-tag resume message"
assert_contains "$out" "run \`just release <bump>\` instead" "no-tag resume hint"
assert_eq "$(cat "$GH_LOG")" "" "no-tag resume must not call gh"
```

**After** (same fixture, verbatim — only the assertions changed):

```bash
echo "=== resume: refuses when no tag exists for the manifest version ==="
new_sandbox "1.2.3"
git -C "$plugin" tag -d v1.2.3 >/dev/null
run_in "$plugin" bash plugin-dev/release.sh --resume
assert_eq "$rc" "1" "no-tag resume exit code"
assert_contains "$out" "no tag v1.2.3 for plugin.json version 1.2.3" "no-tag resume message"
assert_contains "$out" "git fetch --tags" "no-tag resume hint names the fetch remedy"
assert_contains "$out" "just resume-release" "no-tag resume hint names resume-release, not a fresh release"
assert_not_contains "$out" "just release <bump>" "no-tag resume hint must not advise the bump form"
assert_eq "$(cat "$GH_LOG")" "" "no-tag resume must not call gh"
```

The fixture was already correct (`new_sandbox "1.2.3"` + local-only tag
deletion, matching the runbook's slice 2 description exactly), so it is
untouched. Only the old `assert_contains … "run \`just release <bump>\`
instead"` line was replaced — that line would fail the moment slice 2's branch
lands, since the hint text changes entirely. No other scenario in the file
referenced this fixture or this assertion; it's local to this one block.

Branch: origin still holds `v1.2.3` (deletion above is local-only via bare
`git tag -d`, no push), and `$V` computed from the manifest is `1.2.3` — the two
agree, selecting the ladder's first branch. That's what distinguishes it from
slice 3 (origin has a tag, but a *different* one) and from slice 1 (origin has
no tag at all).

Verbatim red output today:

```
=== resume: refuses when no tag exists for the manifest version ===
FAIL: no-tag resume hint names the fetch remedy: output did not contain 'git fetch --tags'
  --- output ---
hint: no release was started at this version.
      run `just release <bump>` instead.
error: no tag v1.2.3 for plugin.json version 1.2.3
  --------------
FAIL: no-tag resume hint names resume-release, not a fresh release: output did not contain 'just resume-release'
  --- output ---
hint: no release was started at this version.
      run `just release <bump>` instead.
error: no tag v1.2.3 for plugin.json version 1.2.3
  --------------
FAIL: no-tag resume hint must not advise the bump form: output contained 'just release <bump>'
  --- output ---
hint: no release was started at this version.
      run `just release <bump>` instead.
error: no tag v1.2.3 for plugin.json version 1.2.3
  --------------
```

`exit code` and the `no tag v1.2.3 …` message pass today already (the `die` text
is unchanged) — they guard the refusal itself, which this item never touches,
only its hint.

## Slice 3 — a different semver tag on origin

```bash
echo "=== resume: a different semver tag on origin than v\$V names the bump hint ==="
new_sandbox "1.3.0"
jq '.version = "1.3.0"' "$plugin/.claude-plugin/plugin.json" \
    > "$plugin/.claude-plugin/plugin.json.tmp"
mv "$plugin/.claude-plugin/plugin.json.tmp" "$plugin/.claude-plugin/plugin.json"
git -C "$plugin" add -A
git -C "$plugin" commit -qm "hand-advance to 1.3.0"
git -C "$plugin" push -q origin main
lose_tag "$plugin"
run_in "$plugin" bash plugin-dev/release.sh --resume
assert_eq "$rc" "1" "other-origin-tag resume exit code"
assert_contains "$out" "no tag v1.3.0 for plugin.json version 1.3.0" "other-origin-tag resume message"
assert_contains "$out" "git fetch --tags" "other-origin-tag resume hint names the fetch remedy"
assert_contains "$out" "just release <bump>" "other-origin-tag resume hint names the bump form"
assert_eq "$(cat "$GH_LOG")" "" "other-origin-tag resume must not call gh"
```

Branch: origin's only tag is `v1.2.3` (from `new_sandbox`'s setup, never removed
from origin — `lose_tag` only drops the local copy), while `$V` is `1.3.0` after
the hand-advance. Origin has a real semver tag, but it isn't `$V`, selecting the
ladder's second branch — distinct from slice 2 (where origin's tag *is* `$V`)
and from slice 1 (where origin has no tag to name).

Verbatim red output today:

```
=== resume: a different semver tag on origin than v$V names the bump hint ===
FAIL: other-origin-tag resume hint names the fetch remedy: output did not contain 'git fetch --tags'
  --- output ---
hint: no release was started at this version.
      run `just release <bump>` instead.
error: no tag v1.3.0 for plugin.json version 1.3.0
  --------------
```

`exit code`, the `no tag v1.3.0 …` message, `just release <bump>` (today's
single hardcoded hint already happens to say this) and `must not call gh` all
pass today. The `<bump>` assertion passing today is coincidence, not coverage:
today's code always emits that phrase regardless of state: it isn't yet
conditioned on the branch at all. Once the ladder lands, the same assertion
instead pins that *this specific branch* is the one producing it, which is why
it stays in this scenario rather than being dropped as redundant.

## Slice 4a — the local hint survives (`<bump>` regression guard)

```bash
echo "=== resume: keeping the local tag while origin drops it still advises the bump form ==="
new_sandbox "1.2.3"
git -C "$plugin" push -q origin :refs/tags/v1.2.3
jq '.version = "1.2.4"' "$plugin/.claude-plugin/plugin.json" \
    > "$plugin/.claude-plugin/plugin.json.tmp"
mv "$plugin/.claude-plugin/plugin.json.tmp" "$plugin/.claude-plugin/plugin.json"
git -C "$plugin" add -A
git -C "$plugin" commit -qm "hand-advance to 1.2.4"
git -C "$plugin" push -q origin main
run_in "$plugin" bash plugin-dev/release.sh --resume
assert_eq "$rc" "1" "local-tag-survives resume exit code"
assert_contains "$out" "no tag v1.2.4 for plugin.json version 1.2.4" "local-tag-survives resume message"
assert_contains "$out" "just release <bump>" "local-tag-survives resume hint names the bump form"
assert_not_contains "$out" "git fetch --tags" \
    "local-tag-survives resume hint must not advise a fetch — origin has no evidence to fetch"
assert_eq "$(cat "$GH_LOG")" "" "local-tag-survives resume must not call gh"
```

Branch: today's default (fourth). Origin's `v1.2.3` is explicitly deleted
(`git push origin :refs/tags/v1.2.3`), so origin carries no semver tag at all —
that rules out both the first and second branches (both need origin evidence).
The local clone still holds `v1.2.3` (never deleted), so `release_tags` is
non-empty — that rules out the third branch. Only the fourth is left. Per the
runbook: "deleting origin's copy is what makes branch 4 fire rather than branch
2, and the kept local tag is what skips branch 3" — verified against both by
construction here (dropping either condition moves this fixture onto a different
branch: keep the local tag deleted too and it becomes slice 1's fixture; keep
origin's tag and it becomes slice 2's).

**Zero assertions are red today.** Every one already passes against unchanged
`release.sh`, because today's single hardcoded hint always says
`just release <bump>` and never says `git fetch --tags`, coincidentally matching
what this branch must still say once the ladder lands. This is a forward
regression guard, not new red behaviour — the runbook labels it "Guard," and
slice 4's genuine redness comes entirely from 4b below. Full verbatim run for
this block:

```
=== resume: keeping the local tag while origin drops it still advises the bump form ===
```

(no `FAIL` lines follow it in the run — all five assertions pass.)

## Slice 4b — probe failure degrades, it doesn't refuse

```bash
echo "=== resume: refuses cleanly, with the local no-argument hint, when origin has no remote to probe ==="
new_sandbox "1.2.3"
make_virgin "1.2.3"
git -C "$plugin" remote remove origin
run_in "$plugin" bash plugin-dev/release.sh --resume
assert_eq "$rc" "1" "no-origin resume exit code"
assert_contains "$out" "no tag v1.2.3 for plugin.json version 1.2.3" "no-origin resume message"
assert_contains "$out" 'just release`' "no-origin resume hint names just release with no bump argument"
assert_not_contains "$out" "could not verify this plugin's release history on origin" \
    "no-origin resume output carries no probe-failure wording"
assert_eq "$(cat "$GH_LOG")" "" "no-origin resume must not call gh"
```

Branch: same as slice 1 (third — `release_tags` empty), but reached via a
**failed** `origin_release_tags` (no `origin` remote at all, so `git ls-remote`
fails) rather than a successful empty listing. The outline is explicit that a
failed listing "falls through to the two local hints: the refusal has no side
effect, so the probe only improves the advice" — unlike `release_preflight`'s
own origin probe, which dies outright on a failed listing because there a false
negative would let a side effect (tag/push) happen. `resume_preflight`'s refusal
already happened (no local tag) before the probe even runs, so there is nothing
left to protect by refusing harder. This test guards two ways an implementation
could get that wrong: reading the listing in a bare, uncaptured substitution
(`set -e` would kill the run before the `die`/hint print at all, so several
assertions — not just the targeted one — would fail together, changed output
entirely rather than a missing phrase), or copying `release_preflight`'s
fail-closed pattern and dying with the probe-failure wording instead of falling
through to the ordinary local hint.

Verbatim red output today:

```
=== resume: refuses cleanly, with the local no-argument hint, when origin has no remote to probe ===
FAIL: no-origin resume hint names just release with no bump argument: output did not contain 'just release`'
  --- output ---
hint: no release was started at this version.
      run `just release <bump>` instead.
error: no tag v1.2.3 for plugin.json version 1.2.3
  --------------
```

`exit code`, the `no tag v1.2.3 …` message, and the "no probe-failure wording"
guard all pass today (today's code never probes origin from `resume_preflight`
at all, so it can't emit that wording).

## The `just release` / `just release <bump>` substring problem

`just release` is a literal substring of `just release <bump>`, so a bare
`assert_contains "$out" "just release"` cannot tell the two forms apart — it
would pass against either. Every assertion above that needs to assert the
no-argument form specifically instead uses the needle `` 'just release`' `` —
the word `release` followed immediately by a backtick, with nothing in between.
That backtick can only appear there if the hint's inline-code span is exactly
`` `just release` `` (matching the file's own convention, confirmed by grepping
existing backtick-wrapped commands in
`release.sh:19,254,365,433,477,485,509,567,665,699` — every one wraps the
literal command text with no trailing words inside the backticks). The bump form
instead has `` `just release <bump>` ``, where the character right after
"release" is a space, then `<bump>`, then the backtick — so the needle cannot
match it. Verified empirically: `` 'just release`' `` fails (is red) against
today's actual hint text (`` `just release <bump>` `` instead.), in every
scenario above that asserts it, and the runs above show that failure directly
rather than asserting it by construction.

The reverse direction — confirming the bump form is present — never has this
problem: `assert_contains "$out" "just release <bump>"` only matches when the
fuller string is actually there, so it's a safe positive assertion regardless of
which form the other one is.

## State on exit

- `toolkit/release.sh`: untouched (`git diff --stat -- toolkit/release.sh` is
  empty).
- Nothing committed (`git status --porcelain` shows only
  `M tests/release-test.sh`).
- `bash -n tests/release-test.sh` and `shellcheck tests/release-test.sh`: both
  clean.
- `bash tests/release-test.sh`: 7 failures, all accounted for above; every other
  scenario in the suite (before line 376 and after line 478) still passes,
  confirming no collateral breakage from the rewrite or the new insertions.
