# Deliverable Review: dogfood-0.9.2

**Date:** 2026-10-08 **Methodology:** docs/references/deliverable-review.md
(edify)

## Inventory

Review range `e8885c3..HEAD` (0.9.1 release commit to the 0.9.2 build, four
commits). `edify-review-range.sh plans/2026-10-08-dogfood-0.9.2/outline.md`
returned `NO-PROVENANCE:`; the range was supplied by the caller. Conformance
baseline: `outline.md` (no `design.md`). Layer 1 skipped: 353 changed lines,
under the 500-line threshold, so Layer 2 ran as a full per-file plus
cross-cutting review.

| Type | File | +/- |
|------|------|-----|
| Code | `toolkit/dogfood.sh` | +75 −36 |
| Test | `tests/dogfood-session-start-test.sh` | +40 |
| Test | `tests/dogfood-sync-test.sh` | +46 |
| Test | `tests/dogfood-sync-refusal-test.sh` | +53 |
| Test | `tests/install-test.sh` | +1 −1 |
| Human docs | `toolkit/README.md` | +13 −9 |
| Human docs | `docs/references/dogfood.md` | +20 −19 |
| Human docs | `docs/changelog.md` | +7 |
| Human docs | `docs/changelog/2026-10-08-dogfood-no-copy-remedy-and-submodule-ignores.md` | +65 (new) |
| Context only | `memory` gitlink bump, `plans/…` outline, build summary, red files | n/a |

Conformance summary: both outline items are implemented as specified. The
`session_start` no-copy branch sits after the entry loop and uses `-d`, with the
specified channel split. `list_ignored` is recursive, NUL-delimited and uses
scratch files on fd 3, with no pipe, no `submodule foreach` and no grep, and the
prefixed refusal exits directly. The docs land where the outline puts them, and
the hub is unchanged. The findings below are test gaps and doc accuracy. None is
a code defect: every probe of the shipped script behaved correctly.

### Suites and probes run

All ran in the foreground on the committed tree:

- `bash tests/dogfood-sync-test.sh`: all dogfood sync scenarios passed
- `bash tests/dogfood-sync-refusal-test.sh`: all dogfood sync refusal scenarios
  passed
- `bash tests/dogfood-session-start-test.sh`: all dogfood session-start
  scenarios passed
- `bash tests/dogfood-pre-tool-test.sh`: all dogfood pre-tool scenarios passed
- `bash tests/dogfood-launcher-test.sh`: all dogfood launcher scenarios passed
- `bash tests/install-test.sh`: install.sh scenarios passed
- `bash tests/docs-test.sh`: docs ok (cap 400 lines, pointers resolve)
- `bash tests/doc-sync-test.sh`: doc sync ok (5 shared command blocks, Layout
  matches toolkit/)
- `bash tests/dist-tree-test.sh`: dist tree ok (11 files)
- `bash tests/citation-test.sh`: citations ok
- `shellcheck toolkit/dogfood.sh tests/dogfood-*.sh tests/install-test.sh`:
  clean

Probes, all under `$TMPDIR` with `GIT_CONFIG_GLOBAL=/dev/null`:

- **Whitespace.** Root `…/probe dr/my plugin`, a submodule `my sub` ignoring
  `/build out/` and `*.tmp`, holding `build out/x`, `a b.tmp` and a file whose
  name holds a newline. Sync rc 0, and every ignored entry was absent from the
  copy. Clean.
- **Real layout.** `list_ignored` extracted and run read-only against this repo
  (`memory` → `memory/ddaanet`, two gitlink levels). It listed
  `/memory/.claude/` and `/memory/ddaanet/.claude/`, rc 0. Clean.
- **Sibling submodules.** `a sub` (holding `in ner`) and `b sub`, each ignoring
  `build/`. All three `build/` were excluded and every `t.md` was copied. Clean.
- **Uninitialised submodule** (`submodule deinit -f`). rc 0, and the empty
  `sub/` was copied. Clean.
- **Broken gitfile submodule** (gitdir moved away). rc 128 with git's own
  `fatal: not a git repository`, and `dist/` was not created. This is correct
  under the outline's errexit design; see m4 for the doc gap.
- **Mutations.** Three mutations of `dogfood.sh` survived both sync suites (M1,
  M2, m1).

## Critical Findings

None.

## Major Findings

### M1. The initialised-submodule guard is unpinned, and its removal makes the sync recurse without bound

- **File:** `toolkit/dogfood.sh:97` (`[[ -e "$dir/$entry/.git" ]] || continue`),
  with the missing test belonging in `tests/dogfood-sync-test.sh`, near the
  block at :346.
- **Axis:** test coverage of a specified scenario. The outline says "gitlinks
  (mode 160000) with a `.git` recurse".
- **Evidence:** with that line replaced by `:`, `dogfood-sync-test.sh` and
  `dogfood-sync-refusal-test.sh` both still pass. On a fixture with a
  `submodule deinit`'d gitlink, the real script syncs (rc 0). The mutant ran
  until `timeout 20` killed it (rc 124) and left no `dist/plugin`.
- **Failure scenario:** a consumer cloned without `--recursive`, the common
  case, has an empty `sub/`. If a later edit drops or weakens the guard, for
  example to `-d "$dir/$entry"`, `git -C sub` finds the superproject, lists the
  same gitlink again and recurses into `sub/sub/…` without end. Each level
  creates two `mktemp` files under `$work` (on `/tmp`, a 2G tmpfs here) and
  forks two git processes, so `just dogfood` hangs while filling `/tmp`. No test
  fails.
- **Fix:** in the sync suite, add a gitlink left uninitialised (for example a
  second `submodule add` followed by `submodule deinit -f`). Assert rc 0, empty
  stderr, and the empty directory present in the copy. Run it once against the
  guard-removed mutant under `timeout`, to record the red.

### M2. Sibling submodules are unpinned: dropping `local` silently ships a submodule's ignored files

- **File:** `toolkit/dogfood.sh:79`
  (`local dir="$1" prefix="$2" ignored staged entry`), with the fixture at
  `tests/dogfood-sync-test.sh:360-370`.
- **Axis:** test coverage of a specified scenario. `dogfood.sh:62` and the
  outline both say "each initialised submodule in turn, recursively".
- **Evidence:** with `local` removed, the sync suite still passes. On a
  two-sibling fixture (`a sub` holding `in ner`, then `b sub`), the mutant
  copies `b sub/build` into `dist/plugin`, where the real script excludes it.
  The suite cannot see this because its fixture has one gitlink per level and
  each sorts last in its repo's `ls-files -s` (`sub` after `skills/`, `inner`
  followed only by the non-gitlink `tool.md`). No loop ever resumes after a
  recursion returns.
- **Failure scenario:** a refactor that shares state between recursion levels,
  such as a dropped `local`, a global prefix, or a shared scratch-file name,
  reintroduces exactly the bug class 0.9.2 fixes for every submodule after the
  first. Ignored `.venv/` or build output reaches the copy, and the suite stays
  green.
- **Fix:** give the superproject in the `dogfood-sync-test.sh` fixture a second
  submodule that sorts after `sub` and holds its own ignored `build/`, plus a
  tracked file of the root's that sorts after the gitlinks. Assert that its
  `build/` is absent and its tracked file present.

## Minor Findings

### Test coverage

- **m1. The errexit guarantee for the gitlink listing is unevidenced**
  (`toolkit/dogfood.sh:93`; `tests/dogfood-sync-refusal-test.sh:240-260`). The
  header (`dogfood.sh:69-72`) claims each git listing ends the script under
  errexit. Both refusal stubs fail every `ls-files` call, so the first listing
  (`-o -i`) always dies first. Mutating `:93` to
  `ls-files -z -s >"$staged" || true` passes both suites. Scenario: a git
  failure on the `-s` listing would be swallowed, and that repo's submodules
  silently skipped. Fix: one stub case that fails only when the arguments hold
  `-s` (or `ls-files -z -s`), asserting non-zero rc and no `dist/`.
- **m2. "An entry naming the copy stays silent, copy or not" has no no-copy
  case** (`tests/dogfood-session-start-test.sh`, silence cases from :137 on).
  Every silence test runs `run_dogfood sync` first, so the copy always exists.
  The outline places the `-d` check after the entry loop and keeps the silent
  match unchanged, and the build summary repeats the claim. Moving the `-d`
  block above the loop (`dogfood.sh:199`) would pass the suite. Scenario: such a
  refactor would start warning in a session whose variable names the copy before
  any sync, changing documented behaviour unnoticed. Fix: one case with
  `CLAUDE_CODE_PLUGIN_DIRS="$root/dist/plugin"`, no sync, asserting empty stdout
  and stderr.

### Documentation accuracy

- **m3. `--recurse-submodules` is said to need `--cached`**
  (`docs/references/dogfood.md:38`). On git 2.47.3,
  `git ls-files --recurse-submodules -s` works, and the `-o -i` form fails with
  `fatal: ls-files --recurse-submodules unsupported mode`. The accurate claim is
  that it supports only `--cached` and `--stage`, never `-o`. Scenario: a reader
  concludes `-s` cannot recurse either, or "fixes" the listing with `--cached`.
  Fix: in the node, change to "(`--recurse-submodules` does not support `-o`)",
  the same line count. The dated changelog record repeats the claim and stays as
  written.
- **m4. A git failure inside a submodule is a new way for `just dogfood` to
  fail, and the README does not name it** (`toolkit/README.md:270-275`). The
  paragraph lists the refusals and "rsync's own errors". The broken-gitfile
  probe now exits 128 with only git's
  `fatal: not a git repository: …/my sub/../.git/modules/my sub`, where 0.9.1
  synced the same tree. The node covers it (`dogfood.md:51-52`); the consumer
  manual and the changelog record do not. Scenario: a maintainer with a stale or
  moved submodule checkout sees a bare git fatal from `just dogfood` and no
  `dogfood:` line. Nothing they read says the sync now lists every submodule.
  Fix: one README sentence, such as "a git error listing the root or an
  initialised submodule stops the sync with git's own message, `dist/`
  untouched".

### Style and conventions

- **m5. The changelog index turns into a loose list** (`docs/changelog.md:18`).
  The new entry is followed by a blank line, where every other item of the
  36-bullet list is contiguous. In CommonMark one blank line between items makes
  the whole list loose, which wraps every item in a paragraph. Fix: delete line
  18.
- **m6. `docs/references/dogfood.md` grew 399 → 400 lines and now sits at the
  cap** (`tests/docs-test.sh` passes at ≤ 400). The outline asked for "words
  replaced rather than lines added", and the record says it "stays at 400
  lines", but the growth was one line. A file at exactly its cap no longer
  signals that it is near it, and m3's fix must not add a line. The build
  summary already flags that the node needs a split before its next addition.
  Fix: none required now. Note it for the next edit of the node.

### Checked, no finding

- `run_dogfood` in `dogfood-sync-test.sh:111` runs the script under the
  machine's global git config. Only `fixture_git` masks it. The red still
  discriminates: 0.9.1's root listing never enters `sub/`, whatever the global
  excludes say.
- The fd 3 save and restore across recursion behaves correctly on the sibling
  probe and on the real `memory` layout, where `memory`'s loop resumes after
  `ddaanet`.
- The hub (`docs/design.md`) and CLAUDE.md Layout remain accurate: "minus what
  git ignores" covers submodule ignores, and no shipped file was added.
- `tests/install-test.sh:326` now matches the no-copy line, which is still
  enough to prove that the wired command reached the check.

## Gap Analysis

| Outline requirement | Status |
|---|---|
| 1. session-start: no-copy branch after the entry loop, `-d` test | Covered; the silent "copy or not" case is untested (m2) |
| 1. `systemMessage` names `just dogfood` and the relaunch | Covered (session-start suite, 2 shapes) |
| 1. `additionalContext` fact only, no command or sync | Covered (`just dogfood`/`sync`/`promote` absent) |
| 1. Copy-present text and jq-missing unchanged | Covered (exact pin; jq case pre-existing) |
| 1. Tests red against 0.9.1 | Covered (`red-session-start.txt`, 8 failures) |
| 2. Recursive `list_ignored <dir> <prefix>`, NUL, fd 3, scratch files | Covered; the uninitialised guard is unpinned (M1), siblings unpinned (M2) |
| 2. errexit catches a git failure at any level | Partly: the `-o -i` listing in a submodule is covered, the `-s` listing is not (m1) |
| 2. Prefixed pattern refusal exits the script | Covered (`memory/a*b.log`) |
| 2. Header comment rewritten | Covered (`dogfood.sh:31-43`, `:61-77`) |
| 2. Submodule + nested submodule fixture, `GIT_CONFIG_GLOBAL=/dev/null` | Covered |
| Docs: `dogfood.md` source set and session check | Covered; m3 accuracy, m6 line count |
| Docs: README exclusions and three warnings | Covered; m4 git-failure gap |
| Changelog record and index bullet, no migration note | Covered; m5 list spacing |

## Summary

0 critical, 2 major, 6 minor.

The shipped code behaves correctly on every probe: spaced and newline paths, the
real two-level `memory` layout, sibling submodules, uninitialised and broken
submodules. Both majors are test gaps found by mutation: two invariants of the
new recursion that, broken, would hang the sync (M1) or reintroduce the fixed
leak (M2) with a green suite. The minors are two further unpinned claims, two
doc accuracy points, and two style notes.
