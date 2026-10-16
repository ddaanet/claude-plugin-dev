# RED report: remove the .claude/ clean-tree exemption

Run against UNCHANGED toolkit/ and scripts/. `bash -n` and `shellcheck` clean on
all four edited files.

## Files changed (tests/ only)

| File | Lines | Notes |
|---|---|---|
| tests/release-tree-test.sh | 334 (was 339) | header, l.232-233 assertions, spaced-path, two inverted scenarios, decoy removed |
| tests/self-release-publish-test.sh | 361 (was 378) | dead `stage_claude_frame` helper removed (defined, never called); comment fix |
| tests/self-release-refusal-test.sh | 372 (was 363) | combined assertion split; claude frame now refuses |
| tests/release-tags-test.sh | 299 | comment only: "exempts only `.claude/` and the gitlore submodule" -> "only the gitlore submodule" |

## Scenarios

release-tree-test.sh
- Header (Scope): now says a staged `.claude` frame refuses like any dirty path;
  memory submodule is the exemption.
- dirty-plugin-root (memory mounted): removed the
  `.claude/ — agent working state` and `.claude-plugin/ is NOT exempt` positive
  assertions; added `assert_not_contains` for both. Memory exemption line
  assertion kept (still printed). Comment updated.
- spaced-path (no memory): added `assert_not_contains "exempt from this check"`.
- "proceeds with staged frame, plugin root" -> INVERTED to "refuses": rc 1,
  output has `uncommitted changes` and `.claude/handoff-task.md`; no
  `exempt from this check`, no `gitlore memory submodule`, no
  `.claude/ — agent working state`; HEAD unchanged, no v1.2.4 tag, marketplace
  still 1.2.3, gh log empty. (The old positive HEAD-commit-contains-frame
  assertions were dropped; they cannot hold when refusing.)
- "proceeds with staged frame, marketplace repo" -> INVERTED: rc 1,
  `$MARKETPLACE_DIR has uncommitted changes`, names `.claude/handoff-task.md`,
  no exemption header, marketplace unchanged, gh log empty.
- `.claude-plugin` decoy scenario: REMOVED. The exemption it disambiguated is
  gone and dirty-plugin-root already proves `.claude-plugin/plugin.json`
  refuses. Its one unique assertion (no exemption claimed that was not applied
  when no memory is mounted) is folded into the inverted plugin-root scenario
  (`gitlore memory submodule` and `exempt from this check` absent).

self-release-publish-test.sh
- `stage_claude_frame` was defined but called nowhere in this suite (only the
  refusal suite used it); removed. Neutral vs current code (suite passes before
  and after). No publish scenario staged a frame.

self-release-refusal-test.sh
- Combined `.claude/ and memory/ are exempted` assertion SPLIT: memory/ alone
  still asserted exempt (rc 0, passes today and must keep passing); the
  `.claude` frame is a separate fresh sandbox scenario asserting rc 1,
  `uncommitted changes`, output names `.claude/handoff-task.md`, no v0.2.0 tag,
  gh untouched.
- Comment updated to mention only the `memory` exclusion.

## Implementer note (self-release.sh)

`scripts/self-release.sh` `common_preflight` currently does
`git diff --quiet ... || die "uncommitted changes"` and names no path. The
inverted test asserts the output names `.claude/handoff-task.md` (per the spec
"the refusal names that path"), so after removing the exclusion that assertion
will STILL fail until self-release.sh also prints the offending paths (e.g.
`git diff --name-only HEAD -- . ':(exclude)memory'` in the refusal). Drop that
one assertion instead if naming paths is not wanted there.

## Results against unchanged code

release-tree (exit 1, 15 failures, all by failed assertion; the unrelated
scenarios pass):
```
FAIL: dirty-plugin-root names no .claude exemption: output contained '.claude/ — agent working state'
FAIL: dirty-plugin-root carries no near-miss note: output contained '.claude-plugin/ is NOT exempt'
FAIL: spaced path: no exemption header without an exemption: output contained 'exempt from this check'
FAIL: staged-frame release exit code: expected '1', got '0'
FAIL: staged-frame release message: output did not contain 'uncommitted changes'
FAIL: staged-frame release names the offending path: output did not contain '.claude/handoff-task.md'
FAIL: staged-frame refusal commits nothing: expected '<frame head>', got '<release commit>'
FAIL: staged-frame refusal creates no tag: expected '', got 'v1.2.4'
FAIL: staged-frame refusal leaves the marketplace alone: expected '1.2.3', got '1.2.4'
FAIL: staged-frame release must not call gh: expected '', got 'release view v1.2.4 ...'
FAIL: staged-frame marketplace exit code: expected '1', got '0'
FAIL: staged-frame marketplace message: output did not contain '<MARKETPLACE_DIR> has uncommitted changes'
FAIL: staged-frame marketplace names the offending path: output did not contain '.claude/handoff-task.md'
FAIL: staged-frame marketplace refusal leaves the marketplace alone: expected '1.2.3', got '1.2.4'
FAIL: staged-frame marketplace release must not call gh: expected '', got 'release view v1.2.4 ...'
15 failure(s)
```

self-release-refusal (exit 1, 5 failures; memory-alone assertion passes):
```
FAIL: staged .claude/ frame: exit status: expected '1', got '0'
FAIL: staged .claude/ frame: output did not contain 'uncommitted changes'
FAIL: staged .claude/ frame names the offending path: output did not contain '.claude/handoff-task.md'
FAIL: staged .claude/ frame: tag v0.2.0 should not exist
FAIL: staged .claude/ frame: gh was touched (release view v0.1.0 ...)
```

self-release-publish: exit 0, `self-release.sh: ok` (neutral edit).
release-tags: exit 0, `all release tags scenarios passed` (comment-only edit).

No commits made; no files outside tests/ and this report touched.
