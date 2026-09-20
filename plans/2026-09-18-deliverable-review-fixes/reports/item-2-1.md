# Item 2.1 — `tests/self-release-test.sh` fixtures discriminate

One commit, four lettered parts, run in order (a) -> (b) -> (c) -> (d). Every
mutation named below was applied to `scripts/self-release.sh`, run, quoted,
reverted and re-verified clean before the next part began; none rides in the
commit.

## Part (a) — N7: happy-path untracked leftovers

**Change.** Extended the happy-path's tree-clean check in
`tests/self-release-test.sh` to also assert
`git -C "$repo" ls-files --others --exclude-standard` is empty, with a comment
explaining why `diff --quiet HEAD` alone misses an untracked leftover (same
blind spot `stage_handoff_frame` in `tests/release-test.sh` documents from the
other direction).

**Fixture-leftover check.** Ran the suite with the new assertion against
*unchanged* code first, before touching `scripts/self-release.sh` at all: it
passed. The happy-path fixture does not leave any pre-existing untracked,
non-ignored path — nothing to clean up, no weakening needed.

**Mutation applied verbatim** (`scripts/self-release.sh`, `bump_commit_tag`):

```
bump_commit_tag() {
    printf 'gate-probe-stray-file\n' > MUTATION-STRAY.md
    printf '%s\n' "$V" > toolkit/VERSION
    git add toolkit/VERSION
```

**Failing assertion output under it:**

```
FAIL: happy: untracked leftovers left (MUTATION-STRAY.md)
1 self-release check(s) failed
```

The pre-existing
`git -C "$repo" diff --quiet HEAD || fail "happy: tree left dirty"` did NOT fire
under this mutation (an untracked file doesn't touch `diff --quiet HEAD`) — only
the new assertion did, which is exactly the gap it closes.

**Revert verification.** `git diff --quiet -- scripts/self-release.sh` -> clean.
Re-run closing line:

```
self-release.sh: ok
```

## Part (b) — M1: dist-split scenario discriminates the tag's tree from HEAD's

**Change.** Rewrote "resume after later work" (now titled "resume after later
work inside toolkit/"): the later commit lands *inside* `toolkit/`
(`toolkit/later-work.md`, not `docs.md` at the root), and the local
`dist-v0.2.0` tag is deleted before `--resume` — mirroring the dead-origin
resume scenario further down the file — so `ensure_dist_tag`'s own "already
created locally" short-circuit can't skip the split. New assertions:
`git show dist-v0.2.0:later-work.md` must fail (git show against the *dist*
tree, which strips the `toolkit/` prefix, so the path is unprefixed), and
`git ls-tree --name-only dist-v0.2.0` must omit `later-work.md`. Rewrote the
false "the split ran against the tagged commit at all" comment to explain why
that claim was wrong (the split never ran in the old fixture) and what the new
one actually discriminates.

**Mutation applied verbatim** (`scripts/self-release.sh`, `ensure_dist_tag`):

```
    dist_sha=$(git subtree split -q --prefix=toolkit HEAD) \
```

(was `"$tag"`)

**Failing assertion output under it:**

```
FAIL: resume after work: dist tree carries later work
FAIL: resume after work: dist tree omits later file: output contained 'later-work'
  --- output ---
README.md
VERSION
later-work.md
  --------------
```

Today (unmutated) the whole suite stays green; here both new assertions fail.

**Revert verification.** `git diff --quiet -- scripts/self-release.sh` -> clean.
Re-run closing line:

```
self-release.sh: ok
```

## Part (c) — M3: `.claude`/`memory` exemptions actually constructed

**Change.** Added two fixture helpers, `stage_claude_frame` (adopts
`stage_handoff_frame`'s commit-then-rewrite-and-stage shape from
`tests/release-test.sh`) and `stage_memory_gitlink` (builds a `sub` upstream
*inside* `$sandbox` with two empty commits,
`git -c protocol.file.allow=always submodule add`s it as `memory`, commits the
gitlink at the second commit, then `git -C "$repo/memory" checkout`s the first —
the gitlink resting off HEAD's recorded sha, the resting state gitlore leaves).
Rewrote the "=== preflight refusals ===" exemption scenario to call both,
replacing the false "`.claude/` and `memory/` are excluded from that check, the
way this repo needs" comment with one stating why both must be *constructed*,
not merely created, to reach `common_preflight`'s tracked-only diff.

**Order bug found and fixed during implementation** (not anticipated by the
runbook): calling `stage_claude_frame` before `stage_memory_gitlink` breaks the
fixture, because `stage_memory_gitlink`'s own `git commit -qm "memory gitlink"`
commits *every* staged change in the index — including the `.claude` frame's
staged rewrite left by `stage_claude_frame`, silently folding it into HEAD and
turning the `.claude` half vacuous again. Fixed by calling
`stage_memory_gitlink` first, `stage_claude_frame` last, so the final staged
diff is genuinely uncommitted when `run minor` executes. Verified with a
standalone reproduction outside the suite before fixing in place.

**Mutation 1 applied verbatim** (`scripts/self-release.sh`, `common_preflight`,
drop `':(exclude).claude'`):

```
    git diff --quiet HEAD -- . ':(exclude)memory' \
        || die "uncommitted changes"
```

**Failing assertion output under it:**

```
FAIL: .claude/ and memory/ are exempted from the clean check: expected '0', got '1'
```

**Revert verification.** `git diff --quiet -- scripts/self-release.sh` -> clean.
Re-run closing line: `self-release.sh: ok`.

**Mutation 2 applied verbatim** (drop `':(exclude)memory'`):

```
    git diff --quiet HEAD -- . ':(exclude).claude' \
        || die "uncommitted changes"
```

**Failing assertion output under it:**

```
FAIL: .claude/ and memory/ are exempted from the clean check: expected '0', got '1'
```

Both halves stay green today (unmutated); both go red under their respective
mutation, confirming the fixture's contract from the runbook (clean with both
excludes, dirty with either dropped).

**Revert verification.** `git diff --quiet -- scripts/self-release.sh` -> clean.
Re-run closing line: `self-release.sh: ok`.

## Part (d) — M4: all ten refusals assert status, side-effect absence and `gh` untouched

**Change.** Added `assert_gh_untouched <label>` (fails unless `$GH_LOG` is
empty). Applied `assert_eq "$rc" 1 ...`, `refute_tag <would-be-tag> ...` and
`assert_gh_untouched ...` to all nine `=== preflight refusals ===` scenarios
(dirty tree, wrong branch, malformed VERSION, zero-padded VERSION, hand-written
bump, tag squatting, bad argument, bad option, extra argument) and to "resume,
no tag anywhere" under `=== resume refusals ===` — the tenth. Added
`assert_eq "$rc" 1 ...` to "no dist tag: names it" per the runbook's "same pass"
note (it already had `refute_tag` but no `rc`).

**Finding not anticipated by the runbook: the "tag squatting" scenario cannot
assert `gh` untouched — because it legitimately touches `gh`.** Tracing
`release_preflight`'s order: the drift check fires first (dies before `gh` for
"hand-written bump"), then `require_prior_release_published` calls
`gh release view "$prior"` and succeeds (the fixture is a properly published
prior release), THEN the tag-exists check dies with "tag dist-v0.2.0 already
exists". So by the time the squatting refusal fires, `gh` has already been
reached once, legitimately, by an earlier, passing guard. Asserting
`assert_gh_untouched` there is factually false and did fail on first attempt:

```
FAIL: tag squatting: gh was touched (release view v0.1.0)
```

Fixed by replacing that call with a positive assertion documenting exactly what
`gh` call is expected there and why it's the one scenario in the nine where `gh`
is legitimately reached before the refusal:

```
assert_contains "$(cat "$GH_LOG")" "release view v0.1.0" "tag squatting: gh reached for the prior-release check"
```

**Mutation applied verbatim** (`scripts/self-release.sh`, `common_preflight`):

```
    git diff --quiet HEAD -- . ':(exclude).claude' ':(exclude)memory' \
        || printf 'warn: uncommitted changes (gate probe)\n' >&2
```

(was `|| die "uncommitted changes"`)

**Failing assertion output under it:**

```
FAIL: dirty tree: exit status: expected '1', got '0'
FAIL: dirty tree: tag v0.2.0 should not exist
FAIL: dirty tree: gh was touched (release view v0.1.0
release view v0.2.0
release create v0.2.0 --title Release 0.2.0 --generate-notes)
3 self-release check(s) failed
```

**Discrepancy from the runbook's "three refusal scenarios," verified
empirically, not assumed:** I instrumented `common_preflight` with a temporary
debug probe logging `git status --short` to a side file on every invocation
across the *entire* suite (27 invocations total), ran the full suite once, and
read the log. Exactly two invocations showed a non-clean working tree at the
moment `common_preflight` runs: the "dirty tree" refusal itself, and the
".claude/ and memory/ are exempted" scenario (which is not a refusal — it
asserts `rc == 0` and stays green under this mutation regardless, since the
exempting pathspec already made `diff --quiet` pass before the mutation). Every
other refusal scenario in the file (wrong branch, malformed VERSION, zero-padded
VERSION, hand-written bump, tag squatting, bad argument/option/extra-argument,
both resume refusals, "no gh release", "no dist tag") reaches `common_preflight`
with a genuinely clean tree — they either commit their dirty state before
calling `run` (`git commit -qam`), or never dirty the tree at all, or die at a
check earlier or later than the dirty-tree branch. So in the *current* file,
this exact mutation discriminates **one** refusal scenario ("dirty tree"), not
three — its three individual *assertions* (exit status, tag absence,
gh-untouched) all flip red under it, which may be what the runbook's "three"
refers to, but "scenario" and "assertion" are not the same count. I removed the
debug probe before finishing (confirmed via a second clean run with the mutation
and a plain `git diff --quiet -- scripts/self-release.sh` check) and did not
weaken or invent extra scenarios to force a literal match — the runbook's phrase
traces to `cluster-b-test-suites.md`'s line-number citations (`:262-265`,
`:273-276`, `:296-301`), which are stale against the current,
already-restructured file (shifted by Item 1.3, and further by this item's own
parts (b) and (c)), the same class of drift `tests/citation-test.sh` (Item 3.5)
exists to catch for `.sh` files — `cluster-b-test-suites.md` is itself a `.md`
file, outside that check's scope.

**Revert verification.** `git diff --quiet -- scripts/self-release.sh` -> clean.
Re-run closing line: `self-release.sh: ok`.

## Commit

```
c5a4196d296feee5243445ee6f1cb5d99c6446f9 ✅ Item 2.1 — self-release suite fixtures discriminate
```

Committed with paths named explicitly:

```
git commit -m "test: Item 2.1 — self-release suite fixtures discriminate" -- tests/self-release-test.sh
```

(gitmoji's commit-msg hook prefixed the emoji; message body unchanged.)

`git show --stat HEAD`:

```
commit c5a4196d296feee5243445ee6f1cb5d99c6446f9
Author: David Allouche <david@ddaa.net>
Date:   Sun Sep 20 19:45:10 2026 +0200

    ✅ Item 2.1 — self-release suite fixtures discriminate

 tests/self-release-test.sh | 136 ++++++++++++++++++++++++++++++++++++++++++---
 1 file changed, 127 insertions(+), 9 deletions(-)
```

`.claude/` appears nowhere in it — only `tests/self-release-test.sh` is touched.

## `just precommit`

Ran as the commit's own pre-commit hook (the tool output above) and again is
implied green by the commit having succeeded (a failing hook would have aborted
it, per this repo's "never `--no-verify`" rule — not invoked). Closing lines
from the run:

```
bash tests/doc-sync-test.sh
=== the root README's install/update commands appear in the toolkit README ===
=== CLAUDE.md's Layout list matches toolkit/ ===

doc sync ok (5 shared command blocks, Layout matches toolkit/)
ok
```

All eight suites passed, including `bash tests/self-release-test.sh` itself
(`self-release.sh: ok`) between `tests/release-test.sh` and
`tests/update-plugin-dev-test.sh` in the run.

## Final tree state

```
$ git status --short
 M .claude/handoff-task.md
 M .claude/handoff-todo.md
```

Only the two pre-existing staged handoff files remain, as expected — no
memory-submodule gitlink change appeared (nothing there needed
`git add memory`). `git diff --quiet -- scripts/self-release.sh` confirmed clean
before and after every mutation in every part.

## Summary of findings not anticipated by the runbook

1. **Part (a):** no fixture leftover — the happy-path scenario was already clean
   against unchanged code; no cleanup needed.
2. **Part (c):** the fixture helpers' call order matters — building the `memory`
   gitlink after staging the `.claude` frame silently folds the `.claude` change
   into `stage_memory_gitlink`'s own commit, since
   `git commit -qm "memory gitlink"` commits the whole index, not just the
   gitlink. Fixed by calling `stage_memory_gitlink` before `stage_claude_frame`.
3. **Part (d):** the "tag squatting" refusal cannot assert `gh` untouched —
   `require_prior_release_published`'s `gh release view` runs and succeeds
   before the tag-exists check fires. Replaced with a positive assertion of the
   expected `gh` call instead.
4. **Part (d):** the runbook's "three refusal scenarios must go red" claim does
   not hold against the current file — empirically confirmed (debug
   instrumentation across all 27 `common_preflight` calls in one run) that only
   the "dirty tree" scenario has a genuinely dirty tree at call time; its three
   individual assertions (rc, tag absence, gh-untouched) all go red, but that is
   one scenario, not three. Traced to stale line citations in
   `cluster-b-test-suites.md`, predating this item's own restructuring of the
   file in parts (b) and (c).
