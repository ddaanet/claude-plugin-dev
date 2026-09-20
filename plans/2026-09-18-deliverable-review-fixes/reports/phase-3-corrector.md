# Phase 3 boundary checkpoint — Items 3.1–3.5

**Scope reviewed:** `git diff 0ebf780..HEAD` over `CLAUDE.md`, `justfile`,
`tests/citation-test.sh`, `tests/release-test.sh`,
`tests/version-guard-test.sh`, plus the five execution reports. Contract:
`runbook-test-suites.md` Phase 3 and `runbook.md`'s Gate section.

**Verdict: the contract is met in all five items.** Three fixes applied, all in
Phase 3's own new code; one of them turns an assertion that could pass for the
wrong reason into one that cannot. No UNFIXABLE findings.

Every mutation gate that mattered was re-run here rather than taken on the
reports' word: Item 3.1's `die`→`note`, Item 3.3's hoisted tag listing, and Item
3.5's re-planted citation all reproduced the quoted output. Item 3.4's needle
analysis was re-derived from the file rather than read off its table.

## Per item

### Item 3.1 — `tests/release-test.sh`, two refusals (N3)

Contract met. Both scenarios now assert the `hand-advanced-lost-tag`
four-property shape: local tag set, origin `main` tip, `$GH_LOG` empty,
marketplace version. The tag property is a **set comparison** against a
pre-`run` capture (`local_tags_before`), not a named refutation, exactly as the
runbook required; the comment says why.

**Mutation gate re-run here** (the lost-tags guard's
`die "local release tags are missing …"` → `note`):

```
FAIL: origin-sort must not read as a first release: output contained 'never been released'
FAIL: probe-before-drift must not read as a drift refusal: output contained 'version drift'
```

This confirms the report's candid finding rather than contradicting it: under
the runbook's own mutation **none of the four new properties goes red** in
either scenario — control falls through into a *different* refusal
(`origin-sort`) or the drift refusal (`probe-before-drift`), which produces the
same `rc` and the same absence of every side effect. The executor's response was
correct: it added a fifth assertion,
`assert_not_contains "$out" "never been released"`, which is the only thing that
tells the two refusals apart, documented it inline with the mutation evidence,
and then ran a broader `die()`-neutering sweep under which the four properties
*do* go red (quoted in `item-3-1.md`, including
`origin-sort local tag set unchanged: expected '', got 'v1.2.3'`). It also
reported, rather than claimed covered, that the origin-`main` property was
reached by neither mutation. That is the honest shape.

One residual worth naming and **not** worth changing: in both scenarios the
fixture's local tag set is empty (every tag is lost by construction), so the set
comparison is an empty-vs-empty `assert_eq`. It still discriminates the failure
mode under test — a tag *created* by the refused run makes the post-set
non-empty, as the broad-sweep evidence shows — and the runbook asked for
"unchanged from the fixture", which is what it asserts.

**Changed:** nothing.

### Item 3.2 — `tests/version-guard-test.sh`, N4 and N6

Contract met on all four points:

- The fresh re-invocation against `$git_proj` sits immediately before the
  `tagless_sysmsg` capture, so the byte-identity comparison no longer reads a
  `guard_out` from forty lines earlier.
- Its comment states the capture is deliberately fresh **and** why the adjacent
  `$reason` reuse stays a documented reuse ("its run is immediately adjacent,
  with nothing able to land between it and the read") — which is the half a
  later reader would otherwise "fix" in the wrong direction.
- Both `vnext` assertions landed: `assert_no_escape_hatch` and
  `assert_not_contains "$reason" "just release"`.
- The no-tags site's comment no longer claims the no-recipe property is
  "asserted over the no-tags reason alone"; it now names the vnext site and
  exempts only the steady-state message.

The two-step N4 gate is the right construction (an `assert_eq` between two
notices cannot be turned red by a single edit) and the report quotes the step-2
red verbatim. I did not re-run it; the N6 gate's red is reproduced transitively
by my own hoist mutation below, which reds the same class of assertion.

**Changed:** nothing.

### Item 3.3 — the allow scenario in `$git_tagged_proj` (N5)

Contract met in construction — real-repo fixture, recording `git` stub via the
`guard_stub127_dir` idiom, `\037`-joined arguments with the residual bound
stated in the stub's comment, `guard_path` restored immediately after the run —
**but the log assertion could pass for the wrong reason**, which I fixed.

**Mutation gate re-run here** (the whole `listing`/`release_tags` block hoisted
above `[[ -z "$proposed" || "$proposed" == "$current" ]] && exit 0`):

```
FAIL: version-guard git-tagged-unrelated: no git tag listing runs before the early return: output contained 'tag--list'
```

— plus the two expected collateral `git-dir-leak` failures, since the hoist also
moves the listing above the `unset GIT_*` block. Reverted;
`git diff --quiet -- toolkit/version-guard.sh` clean. So the assertion does
discriminate the ordering defect, and the raw `\037` byte survives the
`grep -q --` round trip (adjudication 3, below).

**The defect:** on an unmutated run nothing in the allow path invokes `git` at
all, so `$guard_recordgit_log` is **empty** and the `assert_not_contains` reads
an empty haystack. That is `test-discipline`'s "isolation fixture with nothing
to leak" — an unwired stub, a `guard_path` that stopped reaching the hook, or a
non-executable stub file all look identical to the property holding. Measured:
replacing `guard_path="$guard_recordgit_dir:$PATH"` with `guard_path="$PATH"`
left the suite **green** before my fix.

**Fix applied** — a positive control over the same fixture, differing only in
whether the edit changes `.version`, run first so the negative reads a log the
control has just proved is written:

```
echo "=== version-guard (git-tagged repo, recording stub reaches the hook) ==="
guard_path="$guard_recordgit_dir:$PATH"
run_guard "… old_string:\"1.2.3\", new_string:\"9.9.9\" …" "$git_tagged_proj"
assert_deny "version-guard git-tagged-control"
assert_contains "$(cat "$guard_recordgit_log")" "tag${US}--list" \
    "version-guard git-tagged-control: the recording stub logged the deny path's tag listing"
```

followed by `: >"$guard_recordgit_log"` and the unchanged allow scenario. With
the stub unwired the control now reds:

```
FAIL: version-guard git-tagged-control: the recording stub logged the deny path's tag listing: output did not contain 'tag--list'
```

`US` moved above both scenarios; nothing else in the block changed.

### Item 3.4 — harness convergence on `grep -q --` (N8)

Contract met. Both bodies are now byte-identical to `release-test.sh`,
`self-release-test.sh` and `update-plugin-dev-test.sh` (verified by reading all
four), failure output included; the haystack-constraint comment survives
unchanged; no call site was touched.

The two-axis re-read re-derived here from the file, not from the report's table:

- **Positive needles (8):**
  `Do not bypass this guard, modify the recipe, or alter version state by`,
  `never been released` ×4, `will publish`, `last released version` ×3 (8 call
  sites; the first is inside `assert_no_escape_hatch`).
  **Every one is free of BRE metacharacters** — no `.`, `*`, `[`, `\`, `^`, `$`
  — so glob-substring and BRE agree exactly on them.
- **Negative needles:** `settings.json` and `9.9.9` carry the only BRE-live
  characters (dots), both widen, both still match; widening on a negative risks
  only a loud false failure.
- **Newline spans:** none. The no-bypass needle is cut at the heredoc's line
  break before `other means.`, which I confirmed against the current
  `toolkit/version-guard.sh`; the `tag${US}--list` needle lies inside one
  `\037`-joined log line by the stub's construction.

**Changed:** nothing.

### Item 3.5 — the citation gate (N9)

Contract met: `tests/citation-test.sh` in `docs-test.sh`'s shape, wired into
`justfile`'s `bash -n` line **and** run list and into `CLAUDE.md`'s Quality gate
paragraph, with **no** Conventions bullet (the proof gate's decision is
respected). The pattern is never written out as a literal matching instance —
every sample is assembled at runtime — so the suite stays inside its own
coverage; verified by running the pattern against the file itself: no hits. The
self-fixture runs the failing path on every invocation, and the `.md` residual
bound is stated in the header, leaving `outline.md:118-121` standing.

**Mutation gate re-run here** (a `release.sh:42` citation appended to a comment
in `toolkit/release.sh`):

```
citation-not-allowed: toolkit/release.sh:872
  found: release.sh:42
  convention: cite the enclosing symbol plus a short quoted fragment of …
```

Real-repo half red naming file and line, self-fixture half green, revert clean.
The failure message carries the convention in full and is enough to act on
alone.

`git ls-files -z` handling is correct: `while IFS= read -r -d '' rel`, so a
tracked path holding whitespace stays one path; the inner loop reads `grep -n`'s
own `\n`-per-match output, where no whitespace hazard exists; the embedded-NUL
residual is stated rather than implied away. No tracked file in this repo is
binary (checked), so `grep`'s binary-file line never reaches the `IFS=: read`.
Worth knowing if one is ever added: it would produce a loud bogus hit, not a
silent miss.

**Two fixes applied:**

1. The suite's `assert_contains`/`assert_not_contains` used
   `grep -q -- "$2" <<<"$1"` while the other four suites — converged one item
   earlier by N8, the very defect this phase exists to close — use
   `printf '%s' "$1" | grep -q -- "$2"`. Landing a fifth divergent copy in the
   same phase re-opens N8. Aligned to the canonical body.
2. The self-fixture's `mktemp -d` had no `trap`, so an early `set -e` exit (e.g.
   a failing `git init`) leaked the directory. Replaced the trailing
   `rm -rf "$fixture"` with `trap 'rm -rf "$fixture"' EXIT`, the idiom
   `version-guard-test.sh` already uses for its own fixtures.

## The four adjudications

**1. Item 3.5's honest red was three, not five — confirmed.** `git show 73d46da`
("🐛 Phase 1 — boundary checkpoint fixes") carries both missing conversions, and
`reports/phase-1-corrector.md` states the consequence for Item 3.5 in advance.
Both are genuine conversions, not deletions: `toolkit/release.sh`'s
`release.sh:780-785` became "the mode dispatch at the foot of this file takes
the `else resume_preflight` branch", and `tests/release-test.sh`'s
`release.sh:138` became "its own `tree_is_clean \".\"` guard". The three Item
3.5 converted are likewise enclosing-symbol-plus-fragment, and I re-located
their targets in the current `toolkit/release.sh`:
`die "'$bump_arg' bump refused: this plugin has never been released"` and
`V="$manifest_version"` both exist, both inside `release_preflight`, as cited.
The `release-test.sh:8-13` header citation became a pointer to that file's
header comment "just above its own `unset $(git rev-parse --local-env-vars)`
line" — accurate.

**2. Item 3.4's adapted falsifiability check covers 2 of 20 call sites, and 0 of
the 8 positive needles.** The heredoc mutation can only reach assertions that
read an *initial-release* reason, and the two that redded are both
`assert_not_contains … "just release"`. It does **not** rule out a silent false
pass across the positive needles, and the report's framing ("same set before and
after") should be read as covering those two assertions, not the suite. This is
the gap the Phase 2 escalation warned of, and you asked to be told:
**it is real.**

It is also, here, harmless — and decidably so, which is why I am not raising it
as a defect to fix. A silent false pass under this conversion requires an
`assert_contains` needle whose BRE reading matches text its literal reading
would not. All 8 positive needles are metacharacter-free, so their BRE reading
*is* their literal reading; the only remaining difference, line-boundary
matching, makes `assert_contains` fail loudly rather than pass silently. The
property is settled by enumeration, and the enumeration was done and is
checkable. The weakened-needle probe in Gate 1 exercises exactly one positive
needle empirically; the other seven rest on that reading. Recorded as a residual
of the `general` typing, not a fix.

**3. Item 3.3's `\037` needle still discriminates — confirmed empirically, and
now for the right reason.** Byte 037 is not a BRE metacharacter, so `grep -q --`
treats it as a literal; the needle lies within a single log line by the stub's
construction, so the glob-to-grep newline change cannot silently retarget it;
and the hoist mutation reds the assertion under the post-conversion helper
(output quoted above). The failure direction is silent, which is why the vacuity
I found mattered and why the positive control now closes it.

**4. The `release-test.sh` intermittent: nothing in Phase 3's diff could
plausibly have caused it.** Phase 3 touches `tests/release-test.sh` in exactly
two hunks, both additive assertions *inside* the `origin-sort` and
`probe-before-drift` scenarios — and none of the three reported failures is
either scenario. The added statements are read-only (`git tag --list`,
`git ls-remote`, `cat "$GH_LOG"`, `market_version`) and run after the scenario's
`run_in`, inside a sandbox `new_sandbox` rebuilds for the next scenario, so they
cannot carry state into `staged frame:` or the `first-release` scenarios. The
other changed files run in different processes: `version-guard-test.sh` and
`citation-test.sh` add small `mktemp` entries, both trapped, and
`citation-test.sh` runs *after* `release-test.sh` in the recipe. The symptom —
three *different* scenarios, combined runs only, each passing standalone
immediately after — points at the environment (this box's ~2GB RAM and the
shared `/tmp` tmpfs, with `release-test.sh`'s 100000-tag fixture as the heaviest
consumer) rather than at any code path, and it predates Phase 3 as the runbook's
Scope/OUT records. Not investigated further.

## Mutation-gate evidence assessment

All five gate reports quote failing output that corresponds to the assertion
each item added, with the suite's green line after the revert. Three I
reproduced verbatim (3.1, 3.3, 3.5); 3.2's I accepted on the strength of its
two-step construction and its quoted labels; 3.4's I re-derived analytically, as
above. No report claims a gate passed without showing it.

No mutation rode into a commit: `git diff 0ebf780..HEAD -- toolkit/ scripts/` is
**empty** — not comment-only, entirely empty — so no production behaviour
changed anywhere in Phase 3, and every `toolkit/version-guard.sh` and
`toolkit/release.sh` mutation named in the five reports was reverted before its
commit. My own three mutations were likewise reverted and verified with
`git diff --quiet`.

## Gate

`just precommit` run in the foreground after the fixes: green, all nine suites,
closing `ok`. `tests/version-guard-test.sh` and `tests/citation-test.sh` also
run standalone (green), `bash -n` and `shellcheck` clean on both.
`.claude/handoff-task.md` and `.claude/handoff-todo.md` are exactly as found.

## Files modified

- `/Users/david/code/claude-plugin-dev/tests/version-guard-test.sh`
- `/Users/david/code/claude-plugin-dev/tests/citation-test.sh`

Left uncommitted in the working tree, as instructed.
