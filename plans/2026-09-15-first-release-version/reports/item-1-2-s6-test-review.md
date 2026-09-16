# Item 1.2, slice 6 — test review

## The unconditional-replacement question, answered

**Nothing in the suite caught it. I added the scenario that does.**

I wrote the naive GREEN into `toolkit/release.sh` — the resume hint at
`:318-322` replaced outright, with no condition on whether the plugin is
published:

```sh
    bash "$here/check-version.sh" || {
        printf 'hint: no release is recorded at either version.\n' >&2
        printf '      correct the marketplace entry to match the manifest, or\n' >&2
        printf '      set .version in %s instead.\n' "$manifest" >&2
        die "fix the version drift above before releasing"
    }
```

Full suite against that, verbatim:

```
EXIT=0
--- FAIL lines ---
--- tail ---
=== release: an initial release whose entry disagrees with the manifest is still refused ===

all release scenarios passed
```

Every scenario passed, slice 6's included. The suite as it stood could not tell
"branches on published-ness" from "replaces the hint unconditionally".

Why nothing caught it: the four `assert_contains "$out" "just resume-release"`
sites (`:278`, `:316`, `:541`, `:925`) all belong to *other* messages — the
refused branch push, the refused marketplace push, `common_preflight`'s dirty
marketplace, and the refused marketplace commit. None goes through
`release_preflight`'s `check-version.sh` failure hint. The only scenario that
touches that hint at all is `:765` (`probe-before-drift`), and it asserts the
hint is **absent** — same direction as slice 6, so it reinforces the mutation
rather than catching it.

### The guard scenario I added

Placed immediately after slice 6's, so the branch's two sides read together:

```sh
echo "=== release: version drift on a plugin that HAS been released still offers resume ==="
new_sandbox "1.2.3"       # entry still at the previously released 1.2.3...
jq '.version = "1.2.4"' "$plugin/.claude-plugin/plugin.json" > "$plugin/.claude-plugin/plugin.json.tmp"
mv "$plugin/.claude-plugin/plugin.json.tmp" "$plugin/.claude-plugin/plugin.json"
git -C "$plugin" commit -qam "release: 1.2.4"
git -C "$plugin" tag -a v1.2.4 -m "Release 1.2.4"
git -C "$plugin" push -q origin main
git -C "$plugin" push -q origin v1.2.4    # ...but 1.2.4's commit and tag already landed
run_in "$plugin" bash plugin-dev/release.sh
assert_eq "$rc" "1" "released-drift exit code"
assert_contains "$out" "version drift" "released-drift refuses as drift"
assert_contains "$out" "just resume-release" \
    "released-drift still offers resume — a release did land partially here"
assert_eq "$(git -C "$plugin" tag --list 'v1.2.5')" "" "released-drift creates no tag"
assert_eq "$(market_version)" "1.2.3" "released-drift must not touch the marketplace"
assert_eq "$(cat "$GH_LOG")" "" "released-drift must not call gh"
```

**Configuration and why.** Tags land both locally and on origin, and the fixture
keeps its `v1.2.3`. Local tags are what matters: `release_preflight` only runs
the origin probe when `release_tags` is empty (`release.sh:298`), so a non-empty
local list is the *only* way to reach `check-version.sh` without the lost-tags
guard intercepting first. Origin gets the tag too because that is what the state
being modelled actually is — a real half-landed release, not a synthetic one —
and because the guard's `origin_release_tags` must find nothing surprising if a
future implementation widens the probe. This is precisely the state
`just resume-release` exists for: commit and tag at `1.2.4`, entry still at
`1.2.3`.

**Status: green today.** It is a characterization guard, not part of slice 6's
red — the same shape as slices 2-5's guards, proven by mutation rather than by a
failing run.

**Mutation re-run, with the guard in place** (verbatim):

```
EXIT=1
33:FAIL: released-drift still offers resume — a release did land partially here: output did not contain 'just resume-release'
34-  --- output ---
35-check-version: version drift — plugin.json=1.2.4 marketplace.json=1.2.3
36-  bump both to the same value before release.
37-hint: no release is recorded at either version.
38-      correct the marketplace entry to match the manifest, or
39-      set .version in .claude-plugin/plugin.json instead.
=== release: refuses a detached-HEAD marketplace before anything is published ===

1 failure(s)
```

Exactly one failure, in the guard, naming the missing resume hint. The
unconditional replacement is now caught. `toolkit/release.sh` was restored to
`e1b872d` after each probe.

## Mechanical check

Baseline (slice 6's scenario as the RED agent wrote it, `release.sh` untouched):
exit 1, `4 failure(s)`, all four the assertion failures the RED report lists,
all under slice 6's own `===` header, none an ERROR or a bash/git fault. 47
`===` scenarios ran; no `FAIL:` line appeared under any of the other 46.

Final state of the file (after the relocation, the four added state assertions,
the hint-scoped version assertions and the guard scenario): exit 1,
`6 failure(s)`, 48 scenarios.

```
=== release: an initial release whose entry disagrees with the manifest is still refused ===
FAIL: initial-entry-disagrees hint names the manifest version: output did not contain '0.1.0'
  --- output ---
  bump both to the same value before release.
hint: `just resume-release` completes a release that landed partially.
error: fix the version drift above before releasing
  --------------
FAIL: initial-entry-disagrees hint names the marketplace entry version: output did not contain '1.2.3'
  --- output ---
  bump both to the same value before release.
hint: `just resume-release` completes a release that landed partially.
error: fix the version drift above before releasing
  --------------
FAIL: initial-entry-disagrees says neither version has a recorded release: output did not contain 'no release is recorded at'
  --- output ---
check-version: version drift — plugin.json=0.1.0 marketplace.json=1.2.3
  bump both to the same value before release.
hint: `just resume-release` completes a release that landed partially.
error: fix the version drift above before releasing
  --------------
FAIL: initial-entry-disagrees points at the marketplace entry as the one to correct: output did not contain 'correct the marketplace entry'
  --- output ---
check-version: version drift — plugin.json=0.1.0 marketplace.json=1.2.3
  bump both to the same value before release.
hint: `just resume-release` completes a release that landed partially.
error: fix the version drift above before releasing
  --------------
FAIL: initial-entry-disagrees offers editing the manifest instead, if 1.2.3 is the intended version: output did not contain 'set .version in .claude-plugin/plugin.json'
  --- output ---
check-version: version drift — plugin.json=0.1.0 marketplace.json=1.2.3
  bump both to the same value before release.
hint: `just resume-release` completes a release that landed partially.
error: fix the version drift above before releasing
  --------------
FAIL: initial-entry-disagrees must not offer resume — nothing was ever released to resume: output contained 'just resume-release'
  --- output ---
check-version: version drift — plugin.json=0.1.0 marketplace.json=1.2.3
  bump both to the same value before release.
hint: `just resume-release` completes a release that landed partially.
error: fix the version drift above before releasing
  --------------
=== release: version drift on a plugin that HAS been released still offers resume ===
```

All six are assertion failures inside slice 6's scenario. No other scenario
moved in either direction — the guard is green, and the 46 pre-existing
scenarios print with no `FAIL:` under them.

`bash -n` and `shellcheck` on `tests/release-test.sh`: both clean.

## Decision 1 cross-check — one real gap, fixed

Decision 1's conclusion (`outline.md:305-323`):

> The hint names both versions, says no release is recorded at either, and
> points at the entry as the one to correct […] while noting the manifest is the
> right edit if that version is the intended one. Resume is not offered.

Four clauses. The RED scenario encoded three of them.
**"The hint names both versions" was not encoded at all.** Assertions 2a/2b ran
against `"$out"` whole, and `check-version.sh`'s own first line already prints
`plugin.json=0.1.0 marketplace.json=1.2.3` — so both assertions passed today
against unchanged code and would keep passing against a GREEN hint that named
neither version. The RED report is candid that they pass; what it does not say
is that they are therefore untestable as written on this path.

Fixed by scoping them to the hint — the output with `check-version.sh`'s own
lines removed:

```sh
hint_only="$(printf '%s\n' "$out" | { grep -v '^check-version:' || [ "$?" -eq 1 ]; })"
assert_contains "$hint_only" "0.1.0" "initial-entry-disagrees hint names the manifest version"
assert_contains "$hint_only" "1.2.3" "initial-entry-disagrees hint names the marketplace entry version"
```

Both are now red (they are the first two failures above), taking slice 6 from 4
discriminating assertions to 6. The `|| [ "$?" -eq 1 ]` is `semver_tags`'s idiom
from `release.sh:207`: absorb a no-match grep's status 1 and nothing else, so an
empty result is a value while a real grep error still aborts the suite under
`set -e`.

This tightening is authorised by both authorities, not just one: the decision
says "the hint names both versions" and the runbook's slice 6 says "the hint
names both `0.1.0` and `1.2.3`". A GREEN that wrote "no release is recorded at
either version above", relying on `check-version.sh`'s line for the numbers,
would now fail — that is deliberate, and it is what both texts ask for.

Otherwise the runbook's list and the decision's reasoning agree; no divergence
to report. The decision's framing sentence — "this state is reached only when
the plugin is verifiably unpublished" — is about *this* state (drift with no
tags anywhere), and it does not license removing the resume hint from the state
where tags exist. That reading is what the guard scenario above now pins.

### Also added: four state assertions on slice 6's own scenario

The outline's stated default for a refusal scenario (`:172-173`) is "the named
hint, no local tag created, origin `main` not advanced, `gh` not called,
marketplace untouched". The RED scenario asserted the hint, the tag and `gh`;
the other two were missing. Added, mirroring the neighbouring `:658` scenario:

```sh
assert_eq "$(market_version)" "1.2.3" "initial-entry-disagrees must not overwrite the marketplace entry"
assert_eq "$(jq -r .version "$plugin/.claude-plugin/plugin.json")" "0.1.0" \
    "initial-entry-disagrees left the manifest untouched"
assert_eq "$(git -C "$plugin" rev-parse HEAD)" "$head_before" "initial-entry-disagrees makes no commit"
assert_eq "$(git -C "$plugin" ls-remote origin refs/heads/main | cut -f1)" "$head_before" \
    "initial-entry-disagrees did not advance origin main"
```

The marketplace one carries the most weight: decision 1's **rejected**
alternative was to skip `check-version.sh` here and let `bump_marketplace`
overwrite the entry. Nothing pinned that the entry survives untouched. All four
pass today.

## Judgement on assertions 3, 4 and 5

**3 — `no release is recorded at`. Right granularity.** It states the fact
decision 1 rests on without fixing the sentence: "no release is recorded at
either 0.1.0 or 1.2.3", "…at either version", "…at 0.1.0 or at 1.2.3" all
satisfy it. It does pin the preposition, but that preposition is decision 1's
own word, so a GREEN that drops it has drifted from the decision rather than
merely reworded. Confirmed absent from `toolkit/release.sh` and
`toolkit/check-version.sh` entirely — `grep -n "no release is recorded"` over
`toolkit/*.sh` returns nothing, so there is no reachable *or* unreachable path
on which it could pass by accident.

**4 — `correct the marketplace entry`. Right granularity, and load-bearing.** It
pins the remedy *and its direction*: the entry, not the manifest. A hint that
said "correct the version drift" or "correct the manifest" would fail, which is
the point — the direction is the substance of decision 1's conclusion.
`grep -n "correct the marketplace entry"` over `toolkit/*.sh` returns nothing.
The only `marketplace entry` hits are `check-version.sh:7,9` (header comment),
`release.sh:15` (header comment) and `release.sh:550` (`bump_marketplace`'s
refused-commit hint, unreachable here — preflight dies at `:321`, hundreds of
lines earlier). Neither string can pass by accident.

**5 — `set .version in .claude-plugin/plugin.json`. Keep the reuse.** I verified
the RED report's two claims rather than taking them:

- The phrase exists once in `release.sh`, at `:336`
  (`grep -n "set .version in" toolkit/*.sh` → one hit).
- That branch is genuinely unreachable on a no-argument run, for *two*
  independent reasons. `bump_arg` is empty unless the user typed a bump word
  (`:35-42`), and `:331` is `if [ -n "$bump_arg" ]`. More decisively, `:331`
  sits inside the `[ -z "$release_tag_list" ]` block at `:328`, which is *after*
  the `check-version.sh` call at `:318` — this scenario dies at `:321` and never
  reaches line 328 at all. The RED output confirms it empirically.

On the coupling itself: it is real but it is at the right granularity. The
shared text is a clause — remedy verb plus path — not a sentence, and the two
messages say genuinely different things around it ("to publish some other
version instead…" versus "if 1.2.3 was the intended version…"). The act being
named *is* the same act in both: edit `.version` in the manifest, the one edit
the version-guard hook reserves for the maintainer. If someone rewords that
clause in one message and not the other, the plugin ends up naming the same
operation two ways, and a test breaking is the correct signal — not a false
alarm. A phrase of slice 6's own would buy independence at the price of letting
that divergence happen silently. Keep it.

One caveat worth recording for whoever reads a future failure: `assert_contains`
greps BRE, so the `.` characters in this needle are wildcards.
`set Xversion in Yclaude-plugin/plugin.json` would satisfy it. Harmless in
practice — no such string can plausibly appear — and consistent with the suite's
92 other unescaped version-string assertions, so I left it. Same for `0.1.0` and
`1.2.3`: neither is a BRE match for the other (`0.1.0` needs a literal `0` where
`1.2.3` has `2`, and `1.2.3` needs a literal `1` where `0.1.0` has `0`), and the
hint-scoped output contains no third version-shaped string.

## Scenario placement — it was wrong, and I moved it

Appended at the end of the file, slice 6's scenario sat after
`refuses a detached-HEAD marketplace`, which has nothing to do with it. The
suite groups by subject: first-release scenarios at `:607-675`, lost-tag
scenarios at `:677-788`, non-semver tags at `:789-853`.

Slice 6 is a first-release scenario with a marketplace entry, so it is the third
member of the pair already at `:642` (entry agrees, publishes) and `:658` (entry
agrees, bump still refused). Moved to sit directly after `:675`, where it reads
as the third case of that family: entry present, entry *disagrees*, refused. The
guard scenario follows it immediately, so the branch's two sides are adjacent
and a reader meeting one meets the other.

Nothing else moved; the relocation is a cut-and-paste of slice 6's own block.

## Whitespace safety

Clean across everything I added, and across the fixture paths slice 6's scenario
touches. Every `$plugin`, `$marketplace`, `$sandbox`, `$GH_LOG` and `$out`
expansion in the two scenarios is double-quoted, including inside `$( )`.
`market_version` quotes `$marketplace` internally (`:141-142`).
`jq … > "$plugin/…tmp"` and its `mv` are both quoted. The `hint_only` capture
quotes `$out` on the way into `printf`.

The one split in my additions is `ls-remote … | cut -f1`, which splits on TAB:
`ls-remote` emits exactly `<oid><TAB><ref>`, and a git ref name can contain
neither space, tab nor newline, so the split is total. It mirrors `:673` in the
neighbouring scenario verbatim. This is not one of the out-of-scope captures at
`:438`, `:466`, `:562`.

`shellcheck` is clean, which covers the unquoted-expansion class mechanically.

## Nothing UNFIXABLE

## State on exit

- `toolkit/release.sh` — **untouched**. Two throwaway mutations applied and
  restored with `git checkout --`; `git diff --stat toolkit/release.sh` and
  `git status --short toolkit/release.sh` are both empty. Slice 6's branch was
  **not** implemented.
- `tests/release-test.sh` — the only modified file. `git diff --stat` against
  `e1b872d` reads `64 insertions(+)`, no deletions: HEAD carries neither
  scenario, so both slice 6's and the guard's blocks are pure additions and the
  relocation leaves no trace in the diff. No pre-existing scenario weakened,
  skipped or rewritten.
- Suite is red on slice 6's six discriminating assertions and green everywhere
  else, the new guard included.
- Nothing committed. Nothing staged.
- `$TMPDIR` was unset in this dispatch shell; scratch logs went to
  `/tmp/claude-1000/s6review/`. Nothing left in the repo root.
