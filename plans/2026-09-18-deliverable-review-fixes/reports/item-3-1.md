# Item 3.1 report — `tests/release-test.sh` two refusals assert the full property set

## What changed

Two scenarios identified by `cluster-b-test-suites.md`'s B4 citations
(`tests/release-test.sh:935-947` and `:949-964` at `8d3fbf5`, unmoved by
Items 1.1/1.2 since those land earlier in the file and Items 1.1/1.2's own
new scenarios append at the file's end):

- `=== release: origin's listing is read version-sorted, not lexicographically ===`
- `=== release: the lost-tag probe runs before the version-drift check ===`

Both previously asserted only `rc` and message needles. Each now also
asserts, matching the shape `hand-advanced-lost-tag` (the scenario
immediately above them) already uses:

- the local tag set is unchanged from the fixture — captured as
  `local_tags_before="$(git -C "$plugin" tag --list 'v*' | sort)"` right
  before `run_in`, compared after with `assert_eq ... "$local_tags_before"`.
  Phrased as a set comparison per the item's instruction, not a named
  refutation — which tag the code would create is itself under test.
- origin `main` unchanged — `origin_head_before` captured the same way,
  compared via `ls-remote origin refs/heads/main`.
- `$GH_LOG` empty — `assert_eq "$(cat "$GH_LOG")" ""`.
- the marketplace untouched — `assert_eq "$(market_version)" "1.2.3"` for
  both (neither scenario's fixture ever changes the marketplace entry).

One further needle, beyond the four named in the item, proved necessary for
the first scenario to discriminate under the runbook's own mutation (see
below): `assert_not_contains "$out" "never been released" "origin-sort must
not read as a first release"`. Documented inline with a comment explaining
why, and covered in "Newly added assertion that stayed green" below.

## The runbook's own gate

**Shared refusal mechanism the two scenarios exercise:** both enter
`release_preflight`'s lost-tags guard — local `release_tag_list` empty,
origin's listing non-empty — and hit the same `die` call at
`toolkit/release.sh`'s `release_preflight`:

```
die "local release tags are missing — refusing to guess whether $origin_newest was published"
```

**Mutation applied**, per the item's own Mutation gate: turned that one
`die` into `note` (the script's existing non-fatal print helper) so the
refusal prints and falls through instead of exiting.

**First run — both properties stayed green on `origin-sort`, only rc-only
message needles caught it.** Tracing the fall-through: with local tags
empty and `bump_arg="patch"`, falling through the mutated guard lands
`release_tag_list` still empty, hitting an *unrelated* `die` a few lines
down — the "explicit bump refused: this plugin has never been released"
branch — before any tag, push, `gh` call, or marketplace write. That second
die also yields `rc=1` and leaves every one of the four new properties
untouched, so with only the four named properties the scenario passed
under mutation (`0 failures`). Fixed by adding the `assert_not_contains
"$out" "never been released"` needle above, which the sibling scenarios
already use for the analogous risk.

**Second run — red on both scenarios, quoted verbatim:**

```
=== release: origin's listing is read version-sorted, not lexicographically ===
FAIL: origin-sort must not read as a first release: output contained 'never been released'
```

```
=== release: the lost-tag probe runs before the version-drift check ===
FAIL: probe-before-drift must not read as a drift refusal: output contained 'version drift'
```

(The second scenario's pre-existing `assert_not_contains "$out" "version drift"`
needle already caught this mutation on its own — falling through there lands
in the version-drift refusal instead, which the pre-existing needle already
guarded against. The newly added tag/GH_LOG/marketplace properties were
confirmed separately, in the additive sweep below, to also fail under a
mutation that lets the release actually proceed.)

**Revert and green:**

```
$ git diff --quiet -- toolkit/release.sh && echo "REVERT CONFIRMED: no diff in toolkit/release.sh"
REVERT CONFIRMED: no diff in toolkit/release.sh
```

```
=== resume hint names the tag already on origin at 1MB ===

all release scenarios passed
```

## Additive falsifiability sweep

**Identified shared refusal mechanism of `toolkit/release.sh`:** the
script-wide `die()` helper itself —
`die() { printf 'error: %s\n' "$*" >&2; exit 1; }` — used by every refusal
in the file, the same role `die` plays in `scripts/self-release.sh`.

**The runbook gate above did not defeat this globally** — it mutated one
specific call site (`die`→`note` at the lost-tags guard only), not the
`die()` function itself, so it is narrower than "the shared refusal
mechanism of the whole script." Per the instructions, the sweep therefore
ran, and was not a duplicate.

**Mutation applied:** `die() { printf 'error: %s\n' "$*" >&2; }` (dropped
`exit 1`, defeating every refusal in the script at once).

**Run in the foreground**, full suite: 138 failures across the file, as
expected from a mutation this broad. The two scenarios this item touches,
quoted:

```
=== release: origin's listing is read version-sorted, not lexicographically ===
FAIL: origin-sort exit code: expected '1', got '0'
FAIL: origin-sort must not read as a first release: output contained 'never been released'
FAIL: origin-sort local tag set unchanged: expected '', got 'v1.2.3'
FAIL: origin-sort must not call gh: expected '', got 'release view v1.2.3
release create v1.2.3 --title Release 1.2.3 --generate-notes'
```

```
=== release: the lost-tag probe runs before the version-drift check ===
FAIL: probe-before-drift exit code: expected '1', got '0'
FAIL: probe-before-drift must not read as a drift refusal: output contained 'version drift'
FAIL: probe-before-drift must not offer the drift recovery command: output contained 'just resume-release'
FAIL: probe-before-drift local tag set unchanged: expected '', got 'v1.2.4'
FAIL: probe-before-drift must not call gh: expected '', got 'release view v1.2.4
release create v1.2.4 --title Release 1.2.4 --generate-notes'
FAIL: probe-before-drift must not touch the marketplace: expected '1.2.3', got '1.2.4'
```

Every assertion this item added — the tag-set comparison, `$GH_LOG`, the
marketplace check, and the extra "never been released" needle — fires
under this broader mutation too. **No newly added assertion stayed green
under the sweep**; nothing to fix.

**Revert and confirm:**

```
$ git diff --quiet -- toolkit/release.sh && echo "REVERT CONFIRMED: no diff in toolkit/release.sh"
REVERT CONFIRMED: no diff in toolkit/release.sh
```

```
=== resume hint names the tag already on origin at 1MB ===

all release scenarios passed
```

**Origin `main` unchanged property not exercised by either mutation.**
Neither mutation reached a code path that pushes to origin's `main` branch
in these two fixtures (both refusals fire before `push_branch`), so that
particular assertion did not go red under either probe. It is retained
because it matches the reference shape (`hand-advanced-lost-tag`) and would
catch a mutation that let the refusal proceed further down the release
flow (past the manifest commit and branch push) than either mutation here
reached — a residual not exercised, reported rather than silently claimed
covered.

## Pre-existing assertions

No pre-existing assertion in either scenario stayed green under the sweep
in a way that needed reporting as a separate finding — the pre-existing
`rc` and message-needle assertions in both scenarios also failed under the
sweep (quoted above), consistent with the runbook's characterization of
them as real, if incomplete, assertions.

## `just precommit`

Ran in the foreground after the revert, green, ending:

```
bash tests/doc-sync-test.sh
=== the root README's install/update commands appear in the toolkit README ===
=== CLAUDE.md's Layout list matches toolkit/ ===

doc sync ok (5 shared command blocks, Layout matches toolkit/)
ok
```

## Commit

```
$ git commit -m "test: Item 3.1 — two release refusals assert the full property set" -- tests/release-test.sh
```

The commit hook rewrites the subject with this repo's gitmoji convention
(matching the style of prior commits on this branch, e.g. "✅ Item 2.1 —
phase-2 code-review fixes"):

```
commit aca70cc1db1bb4495fa6319f1c9e6e10a36def94
Author: David Allouche <david@ddaa.net>
Date:   Sun Sep 20 20:26:01 2026 +0200

    ✅ Item 3.1 — two release refusals assert the full property set

 tests/release-test.sh | 28 ++++++++++++++++++++++++++++
 1 file changed, 28 insertions(+)
```

`git show --stat HEAD` confirms `.claude/` appears nowhere in this commit
— only `tests/release-test.sh`. `git status --short` after the commit shows
only the pre-existing staged `.claude/handoff-task.md` and
`.claude/handoff-todo.md`, unchanged by this run; no `memory` gitlink
change appeared, so no `git add memory` was needed.

## Anything the runbook did not anticipate

The runbook's own Mutation gate, applied exactly as written (`die`→`note`
at the one lost-tags-guard call site), did **not** turn `origin-sort` red
using only the four named properties (tag absence, `$GH_LOG`, origin
`main`, marketplace) — that scenario's fixture happens to fall through into
a second, unrelated `die` (the explicit-bump-on-first-release refusal) that
also yields `rc=1` with no side effects, so none of the four properties
differ. Fixing this required one additional message needle
(`assert_not_contains "$out" "never been released"`), analogous to the one
`hand-advanced-lost-tag` and the two `lost-tag-*` scenarios already carry
for the same reason. This is reported here as a defect I found and fixed
inside this item's own scope (the mutation gate demanded genuine
discrimination), not a pre-existing gap left standing.
