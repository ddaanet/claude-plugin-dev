# Item A2 — the version-drift refusal offers one remedy, because one works

Addendum item, agreed 2026-09-17 alongside A1 and A3, out of the runbook's scope
and run before Phase 4. Executed inline by the orchestrator rather than
dispatched: the design was already settled and both files' regions already in
context, so a dispatch would only have re-paid that reading.

Scope: `toolkit/release.sh` (the `release_preflight` drift hint) and
`tests/release-test.sh` (the `version-drift` scenario). No behaviour change —
the refusal fires on exactly the same condition and still exits 1. Only what it
tells the operator to do changes.

## What was wrong

The hint offered two remedies. Item 1.2's lost-tags hint and Item 1.4's branch 2
both dead-end at this refusal, and neither remedy helps there. Measured, not
read:

**`git checkout HEAD -- .claude-plugin/plugin.json` is always a no-op here.**
`common_preflight` refuses a dirty tree at `release.sh:138`, and it runs before
`release_preflight` (`release.sh:779-781`). `clean_pathspecs` exempts exactly
two paths — `.claude/` and the gitlore memory submodule — and its own comment
records that `.claude-plugin/` is deliberately *not* among them. So a
hand-written manifest bump has necessarily been committed by the time this
refusal fires, and restoring it from `HEAD` restores the hand-written value. The
scenario's own fixture commits the bump
(`git commit -qam "hand-bump the manifest"`), so the suite could never have
exercised the uncommitted case either.

This is broader than the open decision recorded it. The frame said the remedy
was "useless for a *committed* hand-advance"; it is useless on every path that
reaches the refusal, because no uncommitted path reaches it.

**`git fetch --tags` can never have anything to fetch here.** `latest_tag` comes
from `release_tag_list`, which is the *local* semver tags
(`release.sh:464-466`). The lost-tags probe upstream has already established
that local and origin agree on the newest one: an origin tag ahead of local
fires the probe's own fetch hint first, and an unreachable origin dies there
outright. The `probe-before-drift` scenario (`tests/release-test.sh:949`) pins
that ordering. The two refusals therefore closed a loop — the probe's hint sends
the operator to fetch, and this one, reached after they did, sent them back to
fetch again.

## The replacement

    set .version in .claude-plugin/plugin.json back to 1.2.3, commit that
    edit, then re-run with the bump that produces the version you want.

One act, and the one that works: the revert needs a new commit, and the bump to
re-run with is the one that computes the intended version from the last released
one. The formulation reuses the shape already used by the sibling hint at
`release.sh:431-432` ("set .version in ... and commit that edit, then re-run"),
so the two refusals speak with one voice. No bypass or skip is offered, as in
every other refusal in this file.

The `$latest_tag` interpolation is deliberate and asserted: the operator is told
the version to type, not told to go and work it out.

## RED

Assertions changed first, against unchanged production code.
`tests/release-test.sh` lost the `git checkout HEAD --` assertion and gained
four: two positive (the new remedy naming `.claude-plugin/plugin.json` and
`1.2.3`; the bump guidance) and two negative, pinning that neither dead remedy
returns. The negatives carry the measurement above as a comment, so a later
reader does not restore them.

`TMPDIR=/tmp/claude-1000 bash tests/release-test.sh` —
**4 failures, all four new assertions, in the `version-drift` scenario only.**
Every other scenario in the file passed, including both scenarios A1 added. The
two negatives failed by finding the old text verbatim in `$out`:

    FAIL: version-drift must not offer a fetch — the lost-tag probe already
    cleared origin: output contained 'git fetch --tags'

## GREEN

Hint rewritten; `shellcheck disable=SC2016` directives dropped along with the
two backticked commands that needed them. A comment above the `if` records why
there is one remedy and not three, in the terms measured above.

Full suite: **all release scenarios passed.**

## Mutation

Both mutations of the *prose* were caught — the technique this run keeps earning
its keep with, applied to a refusal's wording rather than its decision:

1. Dropping the `$latest_tag` interpolation ("back to the last released version"
   instead of "back to 1.2.3") → 1 failure, the remedy assertion.
2. Softening the bump guidance ("the bump you want" instead of "the bump that
   produces the version you want") → 1 failure, the bump assertion.

`toolkit/release.sh` restored byte-identical after each (`diff -q`, silent).

## Docs: checked, and correct as they stand

Grepping `docs/`, `toolkit/README.md` and `toolkit/release.just` for
`checkout HEAD` and `fetch --tags` finds four hits, none of them this refusal's:

- `recovery.md:89-95` — the lost-tags probe's four-case advice, where
  `git fetch --tags` is the *right* remedy and stays. `recovery.md:198`
  describes the same probe.
- `recovery.md:130` — `git checkout HEAD -- .claude-plugin/marketplace.json`, a
  different file and a different recovery (rolling back a staged marketplace
  bump).

So Phase 3's docs stand as written. One connection is worth recording, because
it is the dead-end from the other side: `recovery.md:93`'s second case sends an
operator to `git fetch --tags` and then `just release <bump>`, and a manifest
hand-advanced past the tag that fetch just delivered lands precisely on this
refusal. That path now ends in an act instead of a loop.
