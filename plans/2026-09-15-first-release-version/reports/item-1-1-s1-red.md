# Item 1.1 slice 1 — RED report

Command: `bash tests/release-test.sh` (from repo root). `toolkit/release.sh`
untouched throughout (`git diff --stat -- toolkit/release.sh` empty); only
`tests/release-test.sh` is modified and uncommitted (`git status --porcelain`
shows `M tests/release-test.sh` only).

Full run: 13 failures, all in the three new/strengthened scenarios below. Every
other scenario in the suite (including `:592`, `:634`, `:721` per the phase
header) stayed green.

## Test 1 — inverted `:625` scenario, no-argument case

`=== release: a marketplace entry does not disqualify a first release ===`
(`new_sandbox "1.2.3"` + `make_virgin "1.2.3"`, no local/origin tag, no
argument).

```
FAIL: entry-agrees-no-tags publishes the manifest version verbatim: output did not contain 'Release v1.2.3 complete'
FAIL: entry-agrees-no-tags manifest untouched: expected '1.2.3', got '1.2.4'
FAIL: entry-agrees-no-tags makes no commit: expected '67b8aec9bd10560a92fe14e199d51f78a2eb33d0', got 'eb8a3b83b15bffa3f9c0629625b95bfff8ca0199'
FAIL: entry-agrees-no-tags tags HEAD: expected '67b8aec9bd10560a92fe14e199d51f78a2eb33d0', got ''
FAIL: entry-agrees-no-tags marketplace untouched: expected '1.2.3', got '1.2.4'
FAIL: entry-agrees-no-tags marketplace HEAD unmoved: expected '1f726505d3763f6be3787f4348daeeca6bcb12c7', got 'd1520b6f93b3766a4319ba0de44820599b859ec8'
```

Red for the right reason: today's two-part predicate (`release.sh:225`) treats
an existing marketplace entry as disqualifying, so with no tags locally or on
origin but an entry present it falls through to the ordinary bump path — commits
`release: 1.2.4`, tags `v1.2.4`, pushes, creates the GitHub release, and bumps
the marketplace to `1.2.4`. None of that is a setup failure; each assertion
compares the (wrong) post-run state to the first-release contract slice 1
specifies.

## Test 2 — inverted `:625` scenario, `patch` case

`=== release: a marketplace entry does not exempt a first release from refusing a bump ===`
(same fixture, `release.sh patch`).

```
FAIL: entry-agrees-no-tags-bump exit code: expected '1', got '0'
FAIL: entry-agrees-no-tags-bump explains why: output did not contain 'never been released'
FAIL: entry-agrees-no-tags-bump creates no tag: expected '', got 'v1.2.4'
FAIL: entry-agrees-no-tags-bump must not call gh: expected '', got 'release view v1.2.4
release create v1.2.4 --title Release 1.2.4 --generate-notes'
```

Red for the right reason: today's code does not read this state as a first
release at all (entry present disqualifies it under the old conjunct), so
`patch` succeeds ordinarily — exit 0, a `v1.2.4` tag created and pushed, `gh`
called twice, ending in `Release v1.2.4 complete`. The new scenario expects the
first-release bump refusal instead.

## Test 3 — bump-refusal loop, commit-instruction assertion

Existing loop at `:610-623`, new assertion added after the
`set .version in .claude-plugin/plugin.json` check, run for each of
`patch`/`minor`/`major`:

```
FAIL: first-release 'patch' names committing the version edit: output did not contain 'commit that edit'
FAIL: first-release 'minor' names committing the version edit: output did not contain 'commit that edit'
FAIL: first-release 'major' names committing the version edit: output did not contain 'commit that edit'
```

Red for the right reason: `release.sh:227-235`'s current hint tells the
maintainer to `set .version in .claude-plugin/plugin.json` but never says to
commit that edit — the actual printed hint (captured in the failure output) ends
at "maintainer who decides what a plugin first ships as," with no commit
instruction. The other three assertions in the same loop iteration (`exit code`,
`explains why`, `names the version it would publish`) passed unchanged,
confirming this failure is isolated to the new assertion and not a setup
problem.

## Other edits made

- `make_virgin`'s comment (`tests/release-test.sh:194-200`) no longer says "it
  isolates the no-tags half of the conjunct" — replaced with a description of
  what pairing it with `new_sandbox "1.2.3"` now exercises (an entry that
  already agrees with the manifest, on a plugin that has still never been
  tagged).

## Scope confirmation

- `toolkit/release.sh` unmodified (verified via `git diff --stat`).
- No commit made; `tests/release-test.sh` is the only file touched, and it
  remains uncommitted (`git status --porcelain`).
