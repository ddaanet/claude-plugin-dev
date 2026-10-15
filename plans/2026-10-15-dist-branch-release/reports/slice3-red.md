# Slice 3 red: tests/dogfood-sync-test.sh

Scenarios were inserted before "unknown subcommand is usage". Helpers added:
`vendor_dist` (copies toolkit/dist.sh beside dogfood.sh), `set_include`,
`make_allowlisted`. `make_consumer` is unchanged, so existing scenarios still
run with dogfood.sh alone and no dist.include.

## Scenario map

| Scenario | Pins |
| --- | --- |
| only listed paths are copied | unlisted root file, dist.include, unlisted dir, plugin-dev absent; listed dir, dot-dir, root file present |
| listed directories in full | deep file `skills/demo/deep/er/leaf.md` present, bytes equal |
| space and nested | `my docs/` copied; `a/b/file` copied; `a/b/sibling` and `a/other` absent |
| untracked / ignored | untracked file in listed dir present; ignored `cache.log` absent |
| deletion | deleted files leave the copy on next sync |
| list shrinks | a path removed from dist.include leaves the copy |
| missing listed path | rc != 0, stderr names `no such.md`, SENTINEL survives, find listing before/after equal, previous bytes kept, new source file did not land |
| .git and dist/plugin | `.git` inside listed dir absent; listed `dist/` copies `dist/keep.md` but never `dist/plugin` (two syncs) |
| no include, dist.sh vendored | unlisted root file copied |
| no include, no dist.sh | as today (root file copied) |
| include, no dist.sh | rc != 0, stderr names `dist.sh`, `dist/` untouched (mirrors release.sh) |

## Result against unchanged dogfood.sh

Suite reaches its end, exit 1, `18 failure(s)`, all FAIL lines are failed
assertions (paths exist / rc 0 / message missing). Pre-existing scenarios pass.

## FAIL lines (truncated)

```
FAIL: allowlist: an unlisted root file is left out: '<c>/dist/plugin/NOTES.md' exists
FAIL: allowlist: an unlisted dist.include is left out: '<c>/dist/plugin/dist.include' exists
FAIL: allowlist: an unlisted directory is left out: '<c>/dist/plugin/other dir' exists
FAIL: allowlist: the vendored toolkit is left out: '<c>/dist/plugin/plugin-dev' exists
FAIL: allowlist: the unlisted sibling of a listed nested file is left out: '<c>/dist/plugin/a/b/sibl
FAIL: allowlist: an unlisted file in a listed file's grandparent is left out: '<c>/dist/plugin/a/oth
FAIL: allowlist: still left out on a second sync: '<c>/dist/plugin/NOTES.md' exists
FAIL: allowlist shrink: a no-longer-listed directory leaves the copy: '<c>/dist/plugin/my docs' exis
FAIL: allowlist shrink: a no-longer-listed nested file and its parents leave the copy: '<c>/dist/plu
FAIL: allowlist missing path: sync exited 0
FAIL: allowlist missing path: the message names the path: output did not contain 'no such.md'
FAIL: allowlist missing path: the sentinel survives: '<c>/dist/plugin/SENTINEL' is not a regular fil
FAIL: allowlist missing path: the copy's listing is unchanged: expected '.
FAIL: allowlist missing path: the copy holds the previous bytes: expected '# demo skill', got 'changed'
FAIL: allowlist missing path: a new source file did not land: '<c>/dist/plugin/skills/demo/added.md'
FAIL: allowlist without dist.sh: sync exited 0
FAIL: allowlist without dist.sh: the message names dist.sh: output did not contain 'dist.sh'
FAIL: allowlist without dist.sh: dist/ untouched: '<c>/dist' exists
```

## Ambiguities resolved

- dist.sh absent: no include behaves as today; include present refuses (rc != 0,
  message names `dist.sh`, `dist/` not created).
- Refusal message wording is not pinned beyond naming the path / `dist.sh`.
- The `.git`/`dist/plugin` scenario passes today (the existing excludes already
  cover it); it is a regression pin for the green step, which must put the
  excludes ahead of the include rules. Its fixture asserts the nested `.git`
  exists so the absence is not vacuous.
- The missing-path "listing unchanged" compare ran against the unchanged code
  after a full-tree copy, which is why it fails there; under green the refusal
  must leave the earlier allowlisted copy untouched.
- A listed `dist` directory is used for the dist/plugin case; dist.sh accepts
  it.

## Review

Verdict: APPROVE. Two optional additions (1, 2) would close real gaps; neither
blocks the red phase.

Method: a scratch copy of tests/ and toolkit/ under `$TMPDIR/sr` with a
reference green `dogfood.sh sync` (excludes first, then `+` rules for each
parent directory, `+ /p/` and `+ /p/***` for a directory, `- *`; merge input
NUL-delimited; `--delete --delete-excluded`; allowlist read from the worktree
via `dist.sh paths`; refusal before any write). The reference passes the whole
suite. The suite against the unchanged script: 18 failures, all failed
assertions. Then one mutant per wrong variant:

| Mutant | Result |
| --- | --- |
| no parent-directory include rules | 1 failure: `a/b/file` "copied via its parent rules" |
| no `***` for a directory | 14+ failures (every listed directory) |
| `--delete` without `--delete-excluded` | 2 failures, both in the shrink scenario |
| allowlist and existence read from HEAD | shrink (2) and missing-path (6) fail |
| include rules ahead of the ignore excludes | 3 failures: ignored `cache.log`, nested `.git`, `dist/plugin` |
| refusal wipes the previous copy | 3 failures: sentinel, listing, bytes |

Every mutant is caught, and by the assertion that names it. Notes:

1. Optional. `--delete-excluded` is pinned only by the shrink scenario. That is
   enough for the mutant above, but nothing pins a file that becomes ignored
   after it was copied; add it to the untracked/ignored scenario if wanted.
2. Optional, whitespace. The space fixtures are a root-level `my docs/` and the
   consumer path. No listed path has a space in a nested parent
   (`a b/c d/file`), so a green that word-splits only the parent-rule generation
   passes. Add one such nested file to `make_allowlisted` with an unlisted
   sibling. A name with a newline cannot be listed (dist.sh reads the file by
   line), so none is needed; dist.sh refuses leading and trailing blanks. Also
   unpinned: anchoring of include rules (an unanchored `+ a/` would copy an
   empty `a/b/a/`); low value.
3. The `.git`/`dist/plugin` scenario passes today, as the author says. It is a
   genuine pin, not decoration: the ignore-order mutant fails it, and the
   fixture asserts the nested `.git` exists first. Keep. The "no include" pair
   also pass today and are labelled as regression pins; fine.
4. Author's default (include present, `dist.sh` missing: refuse, rc != 0,
   message names `dist.sh`, `dist/` not created) is sound: the alternative falls
   back to copying the whole tree and ships what the allowlist excludes, and it
   mirrors release.sh's refusal. The plan is silent on this case, so the green
   must implement it; the assertion is loose enough to leave wording free.
5. Contract coverage against the plan's case list: unlisted root file, untracked
   file in a listed directory, ignored file in one, deletion, missing listed
   path with previous copy intact, and no allowlist are all present, plus
   shrink, nested parents, deep files, and `.git`/`dist/plugin`.

## Revision

Added both optional cases from the review.

- (a) `make_allowlisted` now lists `a b/c d/file`, with unlisted decoys
  `a b/c d/sibling` and `a b/other`. Asserts: the file is copied, both decoys
  are absent. Two new FAIL lines against the unchanged script (the decoys).
- (b) In the untracked/ignored scenario, `later.log` is created untracked,
  synced (copied, asserted present), then added to `.gitignore` and synced
  again; it must leave the copy. It is created after the fixture commit: a
  tracked file stays on disk once ignored and would make the case vacuous. It
  passes against the unchanged script, because today's `--delete-excluded`
  already removes it; it is a regression pin for green (the mutant without
  `--delete-excluded`), not a red.

Totals against unchanged dogfood.sh: suite reaches its end, exit 1,
`20 failure(s)` (was 18), all failed assertions; shellcheck clean.
