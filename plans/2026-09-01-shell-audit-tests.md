# Shell audit: tests/*.sh (release-test.sh, update-plugin-dev-test.sh, hook-test.sh, dist-tree-test.sh)

Scope: bugs ShellCheck 0.10.0 cannot detect — vacuous-pass tests, portability
(macOS bash 3.2 vs Linux), `set -e` holes, quoting/whitespace, hostile-environment
gotchas. Every line of all four files was read; findings below are verified by
reading the actual code (and, where noted, by running an isolated repro), not
guessed.

## Confirmed defects

### 1. Missing `unset CDPATH` corrupts `repo_root` in 3 of 4 files — HIGH

Files: `release-test.sh:15`, `update-plugin-dev-test.sh:17`, `dist-tree-test.sh:19`.

All three compute:
```sh
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
```
`hook-test.sh:9` runs `unset CDPATH` immediately before the identical line
(`hook-test.sh:10`) with a comment explaining exactly why: "else `cd` may echo
its target into the `$(cd … && pwd)` capture below." The other three files
use the same idiom and lack that guard.

When each script is invoked as documented (`bash tests/release-test.sh`, run
from repo root), `$0` is `tests/release-test.sh`, so `dirname "$0")/..`
evaluates to `tests/..` — a relative path whose first component is `tests`
(not `.` or `..`), which is exactly the shape bash's `CDPATH` search applies
to. Reproduced empirically:

```
$ CDPATH=".:$PWD" bash -c '
script0="tests/release-test.sh"
repo_root="$(cd "$(dirname "$script0")/.." && pwd)"
echo "REPO_ROOT=[$repo_root]"
'
REPO_ROOT=[/Users/david/code/claude-plugin-dev
/Users/david/code/claude-plugin-dev]
```

`repo_root` becomes a two-line string. Every later use of `$repo_root` breaks:
`cd "$repo_root"` fails ("too many arguments" is not quite right since it's
quoted — but the value itself is wrong, a two-line string, so any string
comparison, path concatenation, or `cp "$repo_root/toolkit/..."` reference is
corrupted) and the whole run fails loudly and confusingly, not with a clean
"CDPATH is set" diagnosis. This is a real, non-hypothetical developer/CI
footgun: anyone (or any CI image) with `CDPATH` set — a common personal
dotfiles habit — gets a baffling failure in three of the four suites while
the fourth, doing the exact same thing, is immune.

**Fix:** add `unset CDPATH` near the top of `release-test.sh`,
`update-plugin-dev-test.sh`, and `dist-tree-test.sh`, matching `hook-test.sh`.

## Latent / low-severity

### 2. `dist-tree-test.sh:60` — one `grep -v` lacks the sibling line's `|| true` guard

```sh
bad="$(printf '%s\n' "$migration_notes" | grep -v '^migrations/v[0-9][0-9.]*\.md$' || true)"
...
actual="$(printf '%s\n' "$actual" | grep -v '^migrations/')"
```
The first `grep -v` is correctly guarded against grep's "no non-matching
line" exit-1 case (the robustness catalog's "grep benign no-match" gotcha).
The second, one line later, filters the same kind of thing out of `$actual`
and is missing the same guard. Under `set -e`, if `$actual` (the full sorted
`toolkit/` file list) ever consisted *entirely* of `migrations/*.md` entries,
this line would return 1 and abort the whole script — not a wrong-verdict
bug, but a hard, uninformative crash. Currently unreachable in practice: the
shipped `toolkit/` tree always contains core files (`LICENSE`, `install.sh`,
etc.) alongside any migration notes, so `$actual` can never be all-migrations.
Flagging as a latent inconsistency, not a live bug — the two lines should be
symmetric.

**Fix (optional, for consistency):** append `|| true` to the second `grep -v`
too.

### 3. `chmod 555` read-only-directory tests are no-ops when the suite runs as root

`release-test.sh` lines 374–420 (three scenarios: "refuses when the
marketplace directory isn't writable", "succeeds on a no-op marketplace bump
even when its directory isn't writable", "still refuses when a real
marketplace write is needed and the directory isn't writable") all rely on
`chmod 555 "$marketplace/.claude-plugin"` actually blocking writes. Root
ignores directory permission bits, so under a CI image that runs as root
(common for Docker-based CI), these three scenarios silently exercise the
*writable* code path instead of the *read-only* one. This fails loudly
(`assert_eq "$rc" "1"` would see `rc=0` and report a real FAIL) rather than
silently passing, so it is not a vacuous-pass risk — but it does mean these
three scenarios simply cannot run meaningfully as root, and a failure there
under a root CI runner is a false alarm about environment, not about the
toolkit. Not a code change these tests obviously need (no portable way to
force "operation not permitted" as root without extra tooling like
`unshare --user` or a synthetic FS), but worth knowing before chasing a "test
regression" that is actually "CI now runs as root."

## Checked and found CLEAN

- **`unset $(git rev-parse --local-env-vars)`** (`release-test.sh:13`,
  `update-plugin-dev-test.sh:15`): correctly justified word-splitting
  (shellcheck-disabled deliberately), matches the documented git-hook-env-leak
  fix; every git command downstream targets fixtures via `-C`, never this
  repo's own working tree.
- **`sandboxes=(); cleanup() { for s in "${sandboxes[@]:-}"; ...`**
  (`release-test.sh:37-44`, `update-plugin-dev-test.sh:46-53`): the `:-`
  default correctly guards bash 3.2's pre-4.4 "unbound variable on empty
  array" behavior under `set -u` (these scripts use `set -euo pipefail`).
  `[ -n "$s" ] && rm -rf "$s"` guards against an `rm -rf ""` no-op-vs-danger
  edge case. No `rm -rf "$var"/...` with a possibly-empty base path anywhere.
- **`run_in()`'s `set +e` / `set -e` toggling**: always called at statement
  top level (never inside a condition where `-e` would already be
  suspended), so the toggle behaves as intended in every call site checked.
- **`cmd && echo yes || echo no` idiom** (`release-test.sh:197-198, 370-371,
  385-386`): the classic `a && b || c` pitfall requires `b` to be capable of
  failing; here `b` is always a bare `echo`, which cannot fail, so this is
  the recognized-safe instance of the pattern, not a bug.
- **Annotated tags make the "tag not moved" assertion non-vacuous**:
  verified `toolkit/release.sh` uses `git tag -a "$tag" -m "Release $V"`
  (annotated, not lightweight) at both its call sites. `release-test.sh`'s
  "resume left the tag object untouched" assertion
  (`git -C "$plugin" rev-parse v1.2.4` before/after resume) would in fact
  change if resume deleted and recreated the tag, even pointing at the same
  commit, because an annotated tag's sha encodes tagger/timestamp/message.
  Initially suspected this could be vacuous for a lightweight-tag
  implementation; verified against the real script and it is not.
- **`gh` stub's positional-arg assumption**: verified `toolkit/release.sh`
  calls `gh release view "$tag"` and `gh release create "$tag" --title ...
  --generate-notes`, i.e. the tag is always `$3`. The stub's
  `case "$1 $2" in "release view") [ -f "$GH_RELEASES/$3" ] ...` correctly
  matches this shape. Not fragile against the actual caller.
- **Migration-note ordering** (`update-plugin-dev-test.sh`'s
  "prints migration notes for the crossed range only"): verified
  `toolkit/update.sh` orders notes via `sort -V` on `migrations/v*.md`
  filenames, not mtime — so no clock-second collision risk in this
  assertion. `grep -o 'NOTE-1\.0\.[0-9]*' | tr '\n' ' '` correctly reproduces
  the expected trailing-space string including the final `tr`-converted
  newline.
- **Space-in-path fixture** (`release-test.sh`'s `mount_resting_submodule`
  called with `"store dir"`): deliberately exercises the word-split-`.gitmodules`
  gotcha the inline comment names; all downstream uses (`"$parent/$path"`,
  `submodule add ... "$path"`) are properly quoted throughout the helper.
  Genuinely discriminates, not fixture-satisfied-by-construction.
- **"proceeds with X" / "still refuses a genuinely dirty Y" test pairs**
  (resting-memory-submodule scenarios in `release-test.sh`): each "proceeds"
  case has a matching "still refuses" case that adds one independent dirty
  change on top of the same resting-submodule fixture, so the refusal is
  demonstrably attributable to the added dirty change and not to the
  submodule scaffolding itself. Not vacuous.
- **`hook-test.sh` version-guard/check-version scenarios**: exit codes,
  `permissionDecision`/`permissionDecisionReason` JSON field checks, and the
  MARKETPLACE_DIR-unset / missing-file / no-entry / in-sync / drift matrix
  for `check-version.sh` all assert against distinguishable, non-overlapping
  fixture states; no missing/misspelled command found (all invoked scripts —
  `version-guard.sh`, `check-version.sh` — exist under `toolkit/`).
- **`dist-tree-test.sh`'s exact-file-list assertion**: compares against the
  *index* (`git ls-files`), not `git subtree split` output, per its own
  comment, specifically to avoid a one-commit-late blind spot. Confirmed this
  reasoning is sound: a split-based check would validate the *previous*
  commit's tree, not the one about to be tagged.
- **No `grep -q` multi-line-pattern risk found**: every `assert_contains`
  needle across all four files is a short, single-line literal string; none
  span multiple lines or rely on `.` matching newlines.
- **No timestamp-collision-based ordering assertions found** in any of the
  four files.
- **`run_in`'s `cd "$dir"` calls**: `$dir` is always an absolute path
  (`mktemp -d` output or built from it), so the CDPATH risk above does not
  apply to these call sites — checked specifically because the pattern looks
  similar to the vulnerable `repo_root` line.

## Summary

1 confirmed, environment-triggered defect (CDPATH, reproduced empirically,
affecting 3 of 4 files); 1 latent inconsistency (asymmetric `grep -v` guard,
currently unreachable); 1 environment caveat worth knowing (root-run CI makes
three read-only-directory scenarios non-discriminating, fails loud not
silent). No vacuous-pass tests found in the four files — every negative
assertion, fixture, and command reference was verified to actually exercise
the class of failure it claims to.
