# Item 1.2, slices 2-5 — test review

Every mutation was re-run from scratch against a saved pristine copy of
`toolkit/release.sh` at `cbdd3c2e…`, restored after each, with
`git diff --quiet toolkit/release.sh` asserted clean before the next. The two
RED reports' numbers reproduce exactly — no discrepancy found between what they
claim and what the mutations actually do.

**No fix was needed on `tests/release-test.sh`.** The six scenarios are
unchanged from what the RED dispatches left; nothing was weakened, skipped or
rewritten. Findings below are observations for the orchestrator, not defects I
left unrepaired.

## Verdict

| Slice | Discriminates | Mutations run, and the failure count each produced |
|---|---|---|
| 2 — any semver tag on origin | **yes** | `v$manifest_version`-only narrowing → 6 failures, all in `hand-advanced-lost-tag` |
| 3 — listing is version-sorted | **yes**, on all three | drop `--sort=-v:refname` → 2; `1p`→`$p` → 1; both → 2. All in `origin-sort`, nothing else |
| 4 — probe precedes drift check | **yes** | probe moved after `check-version.sh` → 4 failures, all in `probe-before-drift` |
| 5 — failed listing refuses | **yes** | capture-rule violation → 6 failures, 3 per fixture; survives the §5 experiment (see below) |

Baseline: 46 scenarios, suite green, exit 0. Under every mutation the failure
count matched the scenario under test exactly — **no scenario outside the slice
under test moved under any of the six named mutations**, nor under the two extra
probes I added.

## The §5 experiment — the finding the orchestrator asked for first

**Fixing `push_branch`'s unguarded capture does not disarm slice 5.** It disarms
one assertion of four per fixture; the two that carry the guarantee still fail.

Applied together: the capture-rule mutation (`origin_tag_list=$(…) || die` →
bare `[ -n "$(origin_release_tags)" ]`) *and* a guard on
`toolkit/release.sh:438`:

```sh
remote_head=$(git ls-remote origin "refs/heads/$branch" | cut -f1) \
    || die "could not read origin's $branch — nothing was pushed"
```

| Run | failures | which assertions fail |
|---|---|---|
| capture mutation alone | 6 | exit code, probe message, no-local-tag — on each of (a) and (b) |
| capture mutation + `push_branch` fix | **4** | probe message, no-local-tag — on each of (a) and (b) |

The exit-code assertion stops discriminating, because the guarded `push_branch`
dies with status 1 instead of `set -e` killing the script with git's 128. Both
surviving assertions are the load-bearing ones: the run still reads the failed
listing as "origin has no tags either", still falls into the first-release
branch, and still creates a local `v1.2.3` tag it had no business creating.
Verbatim from the combined run's captured output:

```
check-version: in sync (1.2.3)
first release: publishing the manifest version 1.2.3 as-is (no bump)
tag: v1.2.3 created locally (manifest already at 1.2.3)
fatal: '/tmp/claude-1000/tmp.WVmjOFneqv/does-not-exist' does not appear to be a git repository
error: could not read origin's main — nothing was pushed
```

Conclusion for the orchestrator:
**slice 5 is a real guard, not an accident of the pre-existing bug.** Whoever
later fixes the `ls-remote | cut` captures at `:438,466,562` will not silently
blind these scenarios. If they want the exit-code assertion to keep its edge
afterwards, the natural replacement is to keep asserting on `rc` — it stays `1`
either way once `push_branch` is guarded, so the assertion becomes
true-but-inert rather than wrong. Leaving it is harmless.

## Per-check results

### 1. Mutations re-run independently

All six named mutations reproduced the reports' counts exactly. Applied by
script from the pristine copy; the slice 4 reorder was inspected as a diff first
and confirmed to be a pure move of the same 9-line block (no edit to its
contents). After every run the file was restored and
`git diff --quiet toolkit/release.sh` verified.

### 2. Slice 3 closes the recorded debt — confirmed

The `sed -n '1p'` → `sed -n '$p'` mutation, which two prior reviews measured
leaving the whole suite green, now produces **exactly one failure**, and it is
`origin-sort names the newest origin tag`. Exactly one failure is simultaneously
the proof that the debt is closed (this scenario catches it) and that no other
scenario catches it (none moved). The debt is closed.

### 3. Wrong-reason passes

**The BRE concern is real in principle and inert on this fixture.**
`assert_contains` greps as a BRE, so `.` is a wildcard, and the suite's
convention across all 92 assertions is unescaped version strings. I checked the
full cross-product empirically rather than by reading:

```
haystack=v1.11.0  needle=v1.10.0  no      haystack=v1.10.0  needle=v1.11.0  no
haystack=v1.11.0  needle=v1.9.0   no      haystack=v1.9.0   needle=v1.11.0  no
haystack=v1.2.3   needle=v1.11.0  no      haystack=v1x10y0  needle=v1.10.0  MATCH
```

The only string that spuriously matches `v1.10.0` is of the shape `v1x10y0`,
which `release.sh` cannot emit. Same for slice 2's `v1.2.3` against a `v1.3.0`
hint, and slice 4's `v1.2.4` against `check-version.sh`'s `1.2.3` line — neither
cross-matches. **No change made**: escaping the dots in six of ninety-two
needles would break a suite-wide convention for a hazard that cannot fire here.

**The vacuity concern is answered empirically, not by argument.** Under the
`1p`→`$p` mutation the hint names `v1.2.3` — a tag that contains neither
`v1.10.0` nor `v1.9.0`, so *both* `assert_not_contains` assertions passed
vacuously and the positive `assert_contains "$out" "v1.11.0"` was the sole
assertion that caught the bug. That run is the direct demonstration that the
positive assertion carries the scenario and the two negatives cannot pass it
alone.

Other wrong-reason paths checked and ruled out:

- Slice 4's `v1.2.4` cannot come from anywhere but the lost-tag hint on the
  correct implementation: the run dies before `check-version.sh`, which is the
  only other thing that prints a version.
- Slice 4's `just resume-release` appears only in the drift hint, so the
  negative assertion is not vacuous — the mutation fires it.
- Slice 3 would also fail if the probe were removed entirely (the `patch`
  argument would hit the first-release bump refusal, whose message names no
  origin tag), so it is not merely pinning "exit 1".

### 4. Slice 5 fixture (b) reaches the probe — verified with a control

Two independent confirmations.

First, structurally: the scenario's own `assert_contains "$out" "could not
verify this plugin's release history on
origin"` is emitted **only** at the probe's `|| die`. If `common_preflight`
ever started refusing this fixture early, that assertion would fail. The "passes
for an entirely wrong reason and nothing notices" worry does not hold — the
scenario is self-guarding on this exact point.

Second, empirically, with a positive control. I built a throwaway harness from
the same helpers and ran the same fixture with and without the marketplace
entry:

```
PROBE A: no origin remote, marketplace entry present (slice 5 fixture b)
  rc=1
  error: could not verify this plugin's release history on origin — nothing was done

PROBE B: no origin remote, no marketplace entry (control)
  rc=1
  error: 'fixture' has no entry in …/marketplace.json and no 'origin' remote to derive one from
```

The control fires `common_preflight:176-177`; the real fixture does not. The
entry is indeed what lets (b) reach the probe, as the runbook says. The
throwaway harness was deleted; `ls tests/` confirms only the six tracked test
scripts remain.

### 5. See the section above.

### 6. Fixture honesty and redundancy

| Scenario | Pins something no other scenario pins? |
|---|---|
| `hand-advanced-lost-tag` | **yes** — sole catcher of the `v$manifest_version` narrowing; slice 1's two lost-tag scenarios use a same-string fixture and stayed green under it |
| `origin-sort` | **yes** — sole catcher of all three sort/first-line mutations |
| `probe-before-drift` | **yes** — sole catcher of the reorder |
| `unreachable-origin` (5a) | overlaps (b); see below |
| `no-origin` (5b) | **yes** — see the extra probe below |

The two slice 5 fixtures behaved identically under both capture-rule runs (same
3 assertions each, same 2 each after the `push_branch` fix), so on the named
mutation they do not discriminate from one another. I constructed an extra
mutation to test whether either is dead weight: an origin-presence check placed
in `release_preflight` immediately before the capture, refusing with a different
message.

```
FAIL: no-origin names the unverifiable probe: output did not contain
      'could not verify this plugin's release history on origin'
1 failure(s)
```

Only (b) fails; (a) passes untouched. **Fixture (b) is not redundant** — it pins
that a missing remote must reach the same probe and the same refusal, not a
special-cased earlier one.

I could not construct a natural mutation that (a) catches and (b) does not.
(a)'s independent value rests on being the realistic case — a configured remote
that fails on read, which is what the function's own comment cites (unreachable
origin, auth) — rather than on distinct mutation coverage.
**I am reporting the overlap and deleting nothing**; both are runbook-
specified.

One asymmetry worth naming in the other direction: slice 3's scenario asserts
only `rc` and hint content, where its siblings also assert no local tag, empty
`$GH_LOG` and an untouched marketplace. That is not a gap for what slice 3 pins
— under every sort mutation the run still refuses before any side effect — and
the runbook specifies exactly these four assertions.

### 7. Whitespace safety

Clean. Nothing in the six scenarios splits on whitespace.

- Slice 3's loop iterates a literal word list
  (`for t in v1.9.0 v1.10.0 v1.11.0`), not an unquoted expansion, and every use
  of `$t` and `$plugin` is quoted. No IFS exposure.
- Every command substitution feeding an assertion is quoted at the point of use,
  including `"$(git … ls-remote … | cut -f1)"` and `"$(cat "$GH_LOG")"`.
- Slice 5's `remote set-url origin "$sandbox/does-not-exist"` is quoted, so it
  survives a `$TMPDIR` containing spaces.
- `git tag --list 'v*'` is single-quoted against glob expansion in the test
  shell.
- `bash -n` and `shellcheck` on `tests/release-test.sh`: both clean, no output.

## Out-of-scope observation

Worth recording, found while constructing the §6 probe and **not acted on**: a
`die` placed inside `origin_release_tags` cannot terminate the run, because that
function is only ever called in a command substitution — the `exit` kills the
subshell and the caller's `|| die` fires instead. My first attempt at the probe
mutation was silently neutralised by this, and the suite stayed fully green. The
landed code does not rely on dying from inside that function, so this is latent
rather than a bug; it is a trap for whoever next edits it.

## State on exit

- `toolkit/release.sh` — **untouched.** `shasum` matches the pristine copy byte
  for byte (`cbdd3c2e25f8c288520c66c6e554750e5dd71213`) and
  `git diff --stat toolkit/release.sh` is empty. Eight mutations total (the six
  named, plus two probes of my own) were applied and restored.
- `tests/release-test.sh` — **modified, uncommitted, unchanged by me.** The six
  scenarios are exactly as the RED dispatches left them.
- Scratch lived under `/tmp/claude-1000/s2s5-review/` — `$TMPDIR` was indeed
  unset, as the dispatch warned. Nothing was left in the repo root or in
  `tests/`; `git status --short` shows only `tests/release-test.sh` and the
  three report files under `plans/`.
- Suite against the restored tree: green, `all release scenarios passed`.
- **Nothing committed.**
