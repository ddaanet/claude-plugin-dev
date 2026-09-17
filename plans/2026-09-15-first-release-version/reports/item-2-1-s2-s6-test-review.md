# Item 2.1, slices 2-6 — test review

Verdict: **PASS with three fixes applied to `tests/hook-test.sh`.** The RED
report's per-slice verdicts are all reproduced independently and hold. Two
defects were found beyond the one the dispatch named, both in the same class —
an assertion that looked live and was not — and all three are fixed.

`toolkit/version-guard.sh` was mutated for eight probes and restored after every
one. Final state: `git diff --stat toolkit/version-guard.sh` empty,
`git status --porcelain toolkit/version-guard.sh` empty, md5
`3a7e923a452966bfe5c87d9795806e39` — the same checksum the RED report recorded.
Working tree carries `M tests/hook-test.sh` and the untracked RED report,
nothing else. Nothing staged, nothing committed.

## 1. Mechanical check — confirmed

`bash tests/hook-test.sh` against the unmutated SUT: **exactly four failures**,
all `fail()` calls from `[[ ]]` conditions, no shell error and no ERROR line.

- slice 5 — `git-dir-leak reason: never-released wording despite leaked GIT_DIR`
  and `… no last-released wording despite leaked GIT_DIR`
- slice 6 —
  `git-listing-failure reason: steady-state wording despite failed listing` and
  `… no never-released wording despite failed listing`

Slice 1's three wording assertions, slices 2/3/4 in full, and all fourteen
pre-existing scenarios pass. This matches the RED report's transcript.

Slice 3's and slice 4's mutation proofs re-run independently, not quoted:

| Mutation | Failing assertions added | Matches RED report |
| --- | --- | --- |
| S3 — branch `human_msg` on `release_tags` | `systemMessage byte-identical across tagless and tagged fixtures` | yes |
| S4-B1 — drop the semver filter, key on `git tag --list 'v*'` emptiness | both `vnext-tags` assertions | yes |
| S4-B2 — key on repo-ness (`rev-parse --git-dir`) | three `no-tags` + two `vnext-tags` | yes, including the over-determination the RED report noted |

## 2. The slice-2 prose gap — decision and action

### The gap is real, reproduced

Reinstating the exact prose slice 1's code review removed —

```text
This plugin has never been released -- no vX.Y.Z tag exists yet. The first
release will publish whatever plugin.json holds when
'just release {patch|minor|major}' runs; that recipe validates state, bumps,
commits, tags, and pushes in one step.
```

— produced a failure set **byte-identical to the unmutated baseline**: four
failures, slice 5's two and slice 6's two, no new `FAIL` line. Slice 2 does not
catch it, because the message never prints the digits `9.9.9`. Slice 1 does not
catch it either: the prose still contains `never been released` and
`will publish` and still omits `last released version`.

The three defects the slice-1 code review found in that prose, each verified
against `toolkit/release.sh` directly rather than taken from the review:

1. **It is a route to `$proposed` in prose.** "publish whatever plugin.json
   holds when … runs" instructs the agent to make the very edit being refused
   and then run the recipe.
2. **`just release {patch|minor|major}` is refused outright** on an unreleased
   plugin. `release.sh:446` sets `first_release=1` when the tag list is empty
   and `release.sh:455` is
   `die "'$bump_arg' bump refused: this plugin has never been released"`.
3. **"that recipe … bumps" is false on this path.** `release.sh:456-460` sets
   `V="$manifest_version"` and notes
   `first release: publishing the manifest version $V as-is (no bump)`.

### Decision: option 1, taken

I added an assertion that the **initial-release** reason contains no
`just release`, scoped to the no-tags `$reason` only.

The dispatch framed the risk as constraining future wording more tightly than
the runbook's words do, since `outline.md:120-121` permits "The message may say
what the recipe publishes, not suggest running it for this edit." That reading
is right in general and wrong for this branch specifically, which is what
decides it: on the initial-release path there is
**no correct sentence that names the invocation**. With a bump argument the
recipe refuses (defect 2); without one it publishes `$current`, not `$proposed`.
So every mention of `just release` in this branch routes the agent at something
nobody asked for. That is not a proxy for the requirement, it is the requirement
— and it is what the code review's fix actually did: it withheld the identifier
rather than qualifying its use, which is also what `craft:directive-writing`
prescribes for agent-facing output.

The steady-state message names the recipe legitimately, so asserting over both
reasons would fail on arrival. The assertion is against the extracted
`permissionDecisionReason` of the no-tags case alone.

**Residual bound, stated in the test comment rather than implied away:** prose
that routes at the recipe without naming it ("when the release recipe runs")
still passes. Forbidding "release recipe" would collide with the legitimate
no-bypass sentence, and the hazard is weaker — the agent has to look the name
up.

### Mutation proof

| SUT state | New assertion |
| --- | --- |
| committed (unmutated) | **passes** — red set unchanged at four |
| mutation A (the shipped defect prose) | **fires**: `FAIL: version-guard no-tags reason: initial-release branch names no recipe invocation`, 5 failures |

## 3. Second finding — slice 2's first-line stripping was positional, not semantic

The RED used `reason_after_first_line="$(tail -n +2 <<<"$reason")"`. Dropping
physical line 1 is a proxy for "everything but the legitimate mention", and it
breaks in **both** directions. Both constructed and measured:

- **False positive.** Wrap the refusal opener so `1.2.3 -> 9.9.9` lands on
  physical line 2, leaving the message otherwise the committed, correct one:
  slice 2 **fires** on a legitimate message (5 failures).
- **False negative.** Put
  `Run 'just release' now and it will publish 9.9.9 as the first release.` on
  physical line 1 and drop the version pair from the opener: `tail -n +2` strips
  the route itself, slice 2 **passes** (4 failures, baseline).

The false negative is the serious one — it is an explicit, literal route to
`$proposed` walking straight through the assertion meant to catch exactly that.

**Fix:** excise the one legitimate mention instead of the one legitimate line.

```sh
reason_minus_refusal="${reason/1.2.3 -> 9.9.9/}"
```

`${var/pat/}` replaces the first match only, and the pattern carries no glob
metacharacter (`.` and `-` are literal in a glob outside brackets), so it is a
literal single excision. Post-fix behaviour on all four cases:

| Case | Before | After |
| --- | --- | --- |
| committed SUT | passes | **passes** (red unchanged) |
| wrapped legit opener | fires (wrong) | **passes** |
| route on line 1 | passes (wrong) | **fires** |
| RED's mutation B (`$proposed` interpolated into an extra sentence) | fires | **fires** |

## 4. Third finding — slice 6's stderr assertion was vacuous

The scenario's comment claims empty stderr proves "the `2>/dev/null` on the
listing does not leak the stub's own noise". The stub was `#!/bin/sh` +
`exit 127` — it emits no noise, so there was nothing for the redirect to swallow
and the assertion passed regardless.

**Fix:** the stub now writes one line to stderr before exiting 127. Isolated
proof on slice 6's own path (tagless *repo* fixture, so the pre-existing
non-repo scenarios are not what is being measured):

```text
WITH 2>/dev/null         stderr=[]
WITHOUT 2>/dev/null      stderr=[git: fatal: stub noise on stderr]
```

A whole-suite mutation dropping `2>/dev/null` fires five pre-existing non-repo
scenarios as well, which is why the isolated form above is the one that speaks
to slice 6. The stub's stdout stays silent, so the fixture tests one thing.

## 5. Probe results

**1. Slice 2's stripping** — covered in §3. Two hostile cases constructed and
run; both now handled. On the `$proposed`-substring-of-`$current` variant: the
needle and the payload are both literals in the same scenario, so a `1.2.3` →
`1.2.30` shape would need the scenario rewritten to arise; the excision form is
robust to it anyway, since it removes the pair as one unit.

**2. Slice 3's byte-identity** — confirmed `assert_eq`, not containment, on
`tagless_sysmsg` and `tagged_sysmsg`, each `jq -r '.systemMessage'` over its own
run's `$guard_out`. `tagless_sysmsg` is extracted after the slice-2 block, which
re-invokes nothing, so it is genuinely the no-tags payload. A degenerate
both-`null` pass is blocked upstream by `assert_deny`'s
`grep -q '"systemMessage"'`.

**3. Slice 4's fixture** — both tags exist (`git tag` lists `v1.2` and `vnext`).
Against the SUT's filter `^v[0-9]+\.[0-9]+\.[0-9]+$`: `vnext` nomatch, `v1.2`
nomatch, `v1.2.3` match. `v1.2` fails on the missing third component, which is
the discrimination the slice wants.

**4. Slice 5's `GIT_DIR`** — the leak genuinely reaches the SUT: the scenario
fails today with steady-state wording, which is only reachable if the listing
found `$git_tagged_proj`'s `v1.2.3` through `GIT_DIR`. And it is **not** the
harness's `unset $(git rev-parse --local-env-vars)` that will make it pass after
GREEN: that unset runs at line 14, on the *harness's* environment, while
`run_guard` sets `GIT_DIR` on the *child's* environment afterward via `env`. The
unset cannot undo a later explicit assignment — demonstrated by the leak
arriving at all. So the scenario tests the guard's own clearing.

On `GIT_WORK_TREE` / `GIT_COMMON_DIR`: measured against the tagless fixture with
the tagged repo as target —

```text
GIT_DIR        -> v1.2.3     (redirects the listing)
GIT_COMMON_DIR -> []         (no effect without GIT_DIR)
GIT_WORK_TREE  -> []         (no effect; tags live in the git dir)
```

`GIT_DIR` is the only one of the three that redirects a tag listing on its own,
so it is the right and strongest single leak.
**Recommend not adding a second scenario:** a GREEN that clears the
`git rev-parse --local-env-vars` list covers all fifteen at once, and one proven
leak is what establishes the clearing exists. A second scenario would cost a
fixture and prove nothing new.

**5. Slice 6's stub** — `guard_path` is set at the scenario's start and restored
to `"$PATH"` immediately after `run_guard`, before `assert_deny`, following the
BSD-realpath scenario's pattern. Every later scenario is a `check-version` one,
which does not read `guard_path`. The stub *is* reached, proven positively
rather than inferred: against the **tagged** `v1.2.3` fixture the real `git`
gives steady-state wording and the stubbed `git` gives initial-release wording.
That discrimination matters because against the tagless fixture the stub and the
real `git` currently produce the same wording, so slice 6's own transcript is
not evidence the stub ran. Stderr assertion liveness: §4.

**6. Fixture hygiene** — all six temp paths (`$proj`, `$guard_err`, `$git_proj`,
`$git_tagged_proj`, `$git_vnext_proj`, `$guard_stub127_dir`) are allocated ahead
of the `trap` and all six are named in it. Construction is silent on both
channels: running `tests/hook-test.sh:1-141` in isolation gives `rc=0`, 0 bytes
stdout, 0 bytes stderr. Under
`HOME=/nonexistent GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null` the
suite produces the same four failures and nothing else — the
`git -c user.name/user.email` on the two committing fixtures carries it.

**7. Whitespace safety** — under a `TMPDIR` containing spaces
(`/tmp/claude-1000/s2s6-review/s p a c e d`), the same four failures and nothing
else. No stray stderr.

**8. File length** — `tests/hook-test.sh` is now **439 lines** (419 before this
review's fixes; +20 for the new assertion and the two corrected comment blocks).
`tests/docs-test.sh` caps `docs/` and `plans/` only, so this is not a gate
failure, but it is past CLAUDE.md's 400-line guidance for source files.

A real seam exists and it is clean: lines 1-357 are version-guard (fixtures,
`run_guard`, `assert_deny`/`assert_allow`, fourteen scenarios) and lines 359-413
are check-version, which shares only `$proj`, `$market` and the three generic
assert helpers — no guard fixture, no `guard_path`, no `run_guard`. A split
would need those three helpers plus a `$proj` manifest in both halves, which is
a small shared preamble rather than a tangle. **Not split**, per the dispatch;
flagged for the phase checkpoint.

## 6. Fixes applied

All three are in `tests/hook-test.sh`; `toolkit/version-guard.sh` is untouched.

1. **New slice-2 assertion** (§2) — the initial-release reason names no recipe
   invocation. Comment records why the identifier is withheld rather than
   qualified, cites `release.sh:446-455` and `:456-460`, and states the residual
   bound.
2. **Slice 2's stripping made semantic** (§3) — `${reason/1.2.3 -> 9.9.9/}`
   replaces `tail -n +2`. Comment records both measured failure directions of
   the positional form.
3. **Slice 6's stub made noisy** (§4) — one stderr line before `exit 127`.
   Comment records that a silent stub made the assertion vacuous.

`bash -n`: OK. `shellcheck tests/hook-test.sh`: clean.

Unmutated red after all three fixes: **exactly slice 5's two and slice 6's two**
— unchanged. The new assertion passes against the committed SUT; its mutation
proof is §2.
