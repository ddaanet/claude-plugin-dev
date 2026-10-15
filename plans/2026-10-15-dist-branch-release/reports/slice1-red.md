# Slice 1 red report

Suite: `tests/dist-test.sh` (shellcheck clean). Run against the absent
`toolkit/dist.sh`: it runs to its end (20 scenario headers, no abort), exit 1,
every script invocation is rc 127 captured as a failed assertion.

## Scenarios mapped to the plan's case bullets

- allowlist builds exactly the listed paths, dev files and `memory` gitlink
  absent: `tree: handoff's allowlist builds exactly the listed paths` (also
  checks repo index untouched, blob identity, `HEAD` vs sha),
  `tree: dist.include itself ships only when listed`,
  `tree: the allowlist and the blobs come from the commit, not the worktree`.
- refusals: `tree: refuses a gitlink inside a listed directory`,
  `...a listed path that is itself a gitlink`,
  `...a symlink inside a listed directory`, `...a tree with no plugin.json`,
  `...a listed path that matches nothing`, `...each malformed allowlist line`
  (10 forms: absolute, leading `..`, mid `..`, leading blank, trailing blank,
  `*`, `?`, `[`, `]`, `\`; each through both `tree` and `paths`),
  `tree: listed paths are literal pathspecs`,
  `paths: a listed path absent from the worktree is refused`.
- space and newline paths survive:
  `tree: a space and a newline in a path survive the build` (NUL-delimited cmp;
  repo path itself also holds a space).
- `commit`: `commit: reproducible, copied from the source commit` (same sha
  twice under a different caller GIT_* env, message, author and committer
  name/email/date vs source, root commit, different version gives different
  sha), `commit: with a parent, the parent is that sha`.
- `validate`:
  `validate: runs claude plugin validate --strict on the extracted tree` (stub
  argv, files of the directory it was pointed at, status 7 propagates, status 0
  passes), `validate: refuses when claude is not on PATH` (symlink-only bin dir,
  precondition asserts `type -P claude` is empty there).
- warnings, exit 0: `tree: warnings do not change the exit status` (quiet
  baseline; 512 vs 513 files; 262144 vs 262145 bytes; nine exempt asset
  suffixes; `.png.txt` still warns; README 40 vs 39 words; no license vs
  LICENSE.md vs `license` in plugin.json; each warning asserts `dist:` prefix, a
  key noun and "review").
- `paths` exit 3: `paths: exits 3 without dist.include`; plus
  `paths: reads the worktree allowlist, NUL-delimited and normalised`.
- `enabled`: `enabled: reads dist.include from the commit's tree` (committed +
  deleted in worktree gives 0; untracked in worktree gives 1).

## Run output (FAIL lines trimmed to the first 25 and the totals; 165 in all)

```
FAIL: handoff allowlist: exit code: expected '0', got '127'
FAIL: handoff allowlist: stdout is not a bare object id: ''
FAIL: handoff allowlist: files of the built tree: expected '.claude-plugin/plugin.json|LICENSE|README.md|bin/tool|hooks/hooks.json|scripts/run.sh|skills/demo/SKILL.md|', got ''
FAIL: handoff allowlist: no warnings on a clean fixture: expected '', got 'bash: /Users/david/code/claude-plugin-dev/toolkit/dist.sh: No such file or directory'
FAIL: listed dist.include: exit code: expected '0', got '127'
FAIL: listed dist.include: stdout is not a bare object id: ''
FAIL: listed dist.include: files of the built tree: expected '.claude-plugin/plugin.json|LICENSE|README.md|dist.include|', got ''
FAIL: commit not worktree: exit code: expected '0', got '127'
FAIL: commit not worktree: stdout is not a bare object id: ''
FAIL: commit not worktree: files of the built tree: expected '.claude-plugin/plugin.json|LICENSE|README.md|skills/demo/SKILL.md|', got ''
FAIL: space and newline: exit code: expected '0', got '127'
FAIL: space and newline: stdout is not a bare object id: ''
FAIL: space and newline: NUL-delimited listing differs (want '.claude-plugin/plugin.json|LICENSE|README.md|extra dir/f g.txt|skills/demo/SKILL.md|skills/my skill/SKILL.md|skills/new
FAIL: pathspec magic is literal, so it matches nothing: exit code: expected '1', got '127'
FAIL: pathspec magic is literal, so it matches nothing: stderr line without the dist: prefix: 'bash: /Users/david/code/claude-plugin-dev/toolkit/dist.sh: No such file or directory'
FAIL: pathspec magic is literal, so it matches nothing: stderr names the offender: output did not contain 'exclude'
FAIL: gitlink in a listed directory: exit code: expected '1', got '127'
FAIL: gitlink in a listed directory: stderr line without the dist: prefix: 'bash: /Users/david/code/claude-plugin-dev/toolkit/dist.sh: No such file or directory'
FAIL: gitlink in a listed directory: stderr names the offender: output did not contain 'skills/vendored'
FAIL: listed gitlink: exit code: expected '1', got '127'
FAIL: listed gitlink: stderr line without the dist: prefix: 'bash: /Users/david/code/claude-plugin-dev/toolkit/dist.sh: No such file or directory'
FAIL: listed gitlink: stderr names the offender: output did not contain 'memory'
FAIL: symlink in a listed directory: exit code: expected '1', got '127'
FAIL: symlink in a listed directory: stderr line without the dist: prefix: 'bash: /Users/david/code/claude-plugin-dev/toolkit/dist.sh: No such file or directory'
FAIL: symlink in a listed directory: stderr names the offender: output did not contain 'skills/linked.md'
...
165 failure(s)
```

Every failure is rc 127 / empty stdout / "No such file" on stderr or a derived
effect of those. No assertion about a fixture (`FAIL: fixture...`) fails.

A few negative assertions in the validate scenario (`assert_not_contains` on the
stub log) pass vacuously against the absent script; each sits beside positive
log assertions that fail, so the scenario as a whole is red.

## Ambiguities and how they were resolved

1. `commit` "author and committer ... copied": taken as author fields to author,
   committer fields to committer; the fixture gives them different identities
   and dates.
2. `validate`: the plan does not say whether the extracted directory is an
   argument or the cwd. The stub accepts either (an argument naming a directory,
   else its cwd) and lists that directory's files. The argv must contain
   `plugin`, `validate`, `--strict` as separate args, order unpinned.
3. Warning wording: only `dist:` prefix, a key noun (`files`, the file name,
   `README`, `license`) and the word `review` are pinned. Thresholds taken as:
   more than 512 files, size greater than 262144 bytes, fewer than 40 words
   (whitespace-split).
4. README and license warnings are checked at the tree root only; a missing
   README is not tested (the plan says "under 40 words"); a license in
   `LICENSE*` is tested at the root only.
5. Pathspec-literal case: a listed `:(exclude)skills/demo` must be refused as
   matching nothing, with the stderr line naming `exclude`. This follows from
   "pathspecs literal" plus "a listed path matching nothing" and is not stated
   in so many words.
6. A listed path that is itself a gitlink is refused (plan says "anywhere in the
   result").
7. `tree` accepts any commit-ish (`HEAD` tested); the plan says `<commit>`.
8. `enabled` exit 1 is not asserted to print a `dist:` line (not a refusal in
   the plan's wording); only rc 1 and empty stdout.
9. Refusals pin the offending text on stderr, so the malformed-line messages
   must contain the line (or its distinctive part); the message for a
   leading/trailing-blank line is asserted to contain the line's non-blank text.
10. Parent for the with-parent case is a commit-tree of the source commit's
    tree, made in the suite.

## Review

Verdict: CHANGES

1. Make the malformed-line scenario fail for the stated reason. This is the one
   blocking item. Every offending line in `bad_lines` names a path that does not
   exist in the fixture (`/etc-passwd`, `../dotdot-lead`,
   `skills/../dotdot-mid`, ` blank-lead`, `blank-trail `, `glob-st*ar`, ...).
   The suite accepts any exit-1 `dist:` line naming the needle, so the plan's
   mandatory "listed path matches nothing" refusal satisfies it. The rule that
   was supposed to fire is never separated from the absence refusal.
   - Evidence: in a scratch copy I wrote a naive `dist.sh` with no line rules at
     all. It trims a trailing `/`, skips blanks and comments, and refuses only
     when `ls-tree` finds nothing. The `tree` assertions for `blank-lead`,
     `blank-trail` and `dotdot-mid` passed against it. The `paths` assertions
     for those lines only failed because the naive script printed the earlier
     valid paths before dying, not because of the rule.
   - Fix: create each offending name as a real file in the committed tree (and
     the worktree for `paths`). That means files literally named `glob-st*ar`,
     `glob-qu?ery`, `br-op[en`, `br-clo]se`, `back\slash`, `blank-lead ` and
     ` blank-lead`, and a real `dotdot-mid` at the root so
     `skills/../dotdot-mid` would resolve under naive path normalisation.
   - For the absolute and leading `..` forms, use a spelling that does exist on
     disk. For `paths`, `$repo/README.md` for the absolute form and
     `../<basename of $repo>/README.md` for the `..` form. For `tree`, the
     commit cannot hold those names, so keep the needle check, but add a second
     fixture where the same line sits beside an otherwise valid allowlist and
     also assert the stderr does not claim the path "matches nothing". If you do
     not want to pin that wording, drop `tree` for those two forms and cover
     them via `paths` only.
2. Add a "warnings are computed on the result, not the commit" case. Today every
   warning fixture lists everything, so an implementation that counts or sizes
   the whole source commit passes. Add an unlisted file of 300000 bytes under
   `plans/` and 520 unlisted small files, with a small listed set. Expect no
   warning and `err == ""`. A naive implementation that scans the source
   commit's blobs warns here.
3. Make `paths` prove it uses `<root>`, not the cwd. `run_dist` always runs from
   `$repo` and passes `$repo`. Add one `paths` call from `cd "$sandbox"` (or any
   unrelated directory) with `$repo` as the argument, and assert the same
   output.
4. Tighten "one `dist:` line per refusal" (optional). `assert_dist_prefix` only
   checks that every line is prefixed. Add a count assertion for single-offender
   fixtures (`wc -l == 1`), and optionally a fixture with two gitlinks that
   expects two lines.

Checked and sound:
- **Coverage:** every bullet of the plan's case list and every refusal, warning
  and line rule has an assertion. The gaps are items 1 to 3 plus two points I do
  not require: cleanup of the extraction dir is unspecified in the plan, and
  `justfile`, `dist-tree-test` and `CLAUDE.md` wiring is a green-phase task.
- **Gitlink, symlink and plugin.json refusals:** each failed against the naive
  script as designed.
- **Warnings:** the 513-file, over-256-KiB, 39-word README and no-license
  warnings failed (at 513 files, 262145 bytes, 39 words) against a script that
  emits none. Their boundary cases (512 files, 262144 bytes, 40 words) need a
  quiet stderr. Each warning pins only `dist:`, a key noun and "review".
- **Commit:** dates, names and message are compared against a source commit with
  distinct, explicit author and committer identities and dates. The same-sha
  check runs under a hostile `GIT_*` environment, so a "now" date or a caller
  identity fails. The parent argument order is the plan's.
- **Validate:** it pins argv pieces without order, and the stub accepts a cwd or
  a directory argument. Validating `HEAD` instead of `<tree>` would leak
  `plans/x.md` and `dist.include` and fail. The status-7 propagation is checked.
- **Harness:**
  - The no-claude PATH is a symlink-only directory, and the suite asserts
    `type -P claude` is empty there.
  - Every fixture date and identity is explicit.
  - Cleanup works. `mk_repo` runs in the main shell, so `sandboxes+=` persists,
    and the EXIT trap removes each sandbox.
  - `unset $(git rev-parse --local-env-vars)` guards hook runs.
- **The ten resolutions:**
  - Items 1 to 4 and 6 to 10 are consistent with the plan.
  - Item 5, the `:(exclude)` literal-pathspec case, is a fair reading of
    "literal".
  - A missing README is untested. The plan says only "under 40 words", so
    leaving it is fine.
  - Pinning a refusal's offending text on stderr (item 9) over-constrains only
    mildly, since the plan says "naming the line".
  - I would not resolve any of them differently.

## Revision

Applied review items 1 to 4 to `tests/dist-test.sh` (shellcheck clean):

1. Malformed lines: every relative bad line now has the real file it could
   resolve to committed and in the worktree (`dotdot-mid` at root for
   `skills/../dotdot-mid`, files literally named `glob-st*ar`, `glob-qu?ery`,
   `br-op[en`, `br-clo]se`, `back\slash`, and both the blank-padded and trimmed
   names for leading and trailing blanks), so only the line rule can refuse
   them. The absolute and leading `..` forms cannot be committed names, so they
   are exercised through `paths` only, spelled to resolve to the real
   `README.md` (`$repo/README.md` and `../plug in/README.md`); `tree` is not
   asserted for those two.
2. New case "unlisted bulk": 520 unlisted files and a 300000-byte unlisted file
   under `plans/`, small listed set; expects a tree of exactly the listed files
   and empty stderr.
3. `paths` is also run from an unrelated cwd (`$sandbox`) with `$repo` as the
   argument and must print the same list.
4. `expect_refusal` now requires exactly one `dist:` line, which covers every
   single-refusal case; a new two-gitlink fixture expects exactly two lines
   naming both.

New totals against the absent script: 21 scenario headers, run to the end, 182
failures (was 165), all rc 127 / empty stdout / missing-script effects; exit 1.

## Re-review

Verdict: APPROVE

Each of the four review items now fails against a mutation built for it, in a
scratch copy under $TMPDIR. No tracked file was edited.

1. Malformed lines: I re-ran the same naive `dist.sh` with no line rules.
   - It now fails `blank-lead`, `blank-trail`, `dotdot-mid`, `glob-star`,
     `glob-query`, `br-open`, `br-close` and `back-slash` on `tree` and on
     `paths`. The failures are exit code 0, empty stderr, and the stdout-empty
     assertion. Before the revision, `blank-lead`, `blank-trail` and
     `dotdot-mid` passed on `tree`.
   - `../plug in` (paths) fails on exit code 0 because the path resolves to a
     real file.
2. Unlisted bulk: a variant that counts and sizes the whole source commit
   emitted `dist: 526 files ... review`, and the case failed with
   `unlisted files and a big unlisted file: no warning`.
3. `paths` from an unrelated cwd: a variant reading `./dist.include` failed both
   assertions (exit 3, empty list).
4. Exactly-one-line check: a variant that dies on the first gitlink failed
   `two gitlinks: one dist: line each` (1 instead of 2) and `second named`.
5. Against the absent script, the suite runs to its end: 21 scenario headers,
   exit 1, 182 failures, all of the rc 127 / empty-output / missing-script kind.
   This matches the author's count.

Non-blocking notes:
- `blank-lead2` and `blank-trail2` pass on `tree` against a script with no line
  rules. The trimmed file exists but the padded line matches nothing, so the
  "matches nothing" refusal satisfies them. Their purpose is to catch an
  implementation that trims, which they do through the `paths` exit-code check.
  The sibling `blank-lead` and `blank-trail` entries cover the no-rule case.
- The absolute-path `paths` case resolves to a real file only if the
  implementation uses the path as given. An implementation that joins it onto
  the root would refuse it with "missing" and pass for the wrong reason. In the
  naive run the case failed only on the stdout-empty assertion, because the
  naive script printed earlier valid paths before dying. A cheap hardening:
  `mkdir -p "$repo/${repo#/}"` and put a `README.md` there, so the joined
  spelling exists too.

## Review-fix red

Added to `tests/dist-test.sh` (shellcheck clean), run against the current
`toolkit/dist.sh`: only new assertions fail, each as a failed assertion; the
suite reaches its end.

- Subdirectory: `run_dist` takes an optional `run_cwd`; `enabled` and `tree` run
  from `skills/`, expecting exit 0 and the same tree sha as from the root.
- Bad lines `.`, `./README.md`, `.git`, `skills//demo`, `skills/./demo` added to
  the table, through both `tree` and `paths`, one `dist:` line naming the line.
  `skills//demo` and `skills/./demo` resolve to the real `skills/demo`; `.`,
  `./README.md` and `.git` resolve to real things in the worktree. For `.` the
  needle is `.` itself and so only weakly discriminates; the strong check is the
  next one.
- Because `tree` already refuses these as absent, which would pass the exit code
  and one-line checks vacuously, every bad-line case (old and new) now also
  asserts the refusal does not say `matches nothing` (pins one phrase of the
  existing message, deliberately). This is what makes the `tree` side red.
- CRLF `dist.include`: `tree` and `paths` must exit 1 with a `dist:` line naming
  CR, CRLF, carriage return or line ending, and not `matches nothing`. No line
  count pinned (one per line or one per file are both acceptable).
- No normalisation proposed: `./README.md` and `skills//` are tested as
  refusals, per the default.

FAIL lines (trimmed to 200 chars):

```
FAIL: bad line '.' (tree): refused by the line rule, not as absent: output unexpectedly contained 'matches nothing'
FAIL: bad line '.' (paths): exit code: expected '1', got '0'
FAIL: bad line '.' (paths): stdout is empty: expected '', got '.claude-plugin|skills|README.md|LICENSE|.|'
FAIL: bad line '.' (paths): stderr is empty, expected dist: lines
FAIL: bad line '.' (paths): stderr names the offender: output did not contain '.'
FAIL: bad line './README.md' (tree): refused by the line rule, not as absent: output unexpectedly contained 'matches nothing'
FAIL: bad line './README.md' (paths): exit code: expected '1', got '0'
FAIL: bad line './README.md' (paths): stdout is empty: expected '', got '.claude-plugin|skills|README.md|LICENSE|./README.md|'
FAIL: bad line './README.md' (paths): stderr is empty, expected dist: lines
FAIL: bad line './README.md' (paths): stderr names the offender: output did not contain './README.md'
FAIL: bad line '.git' (tree): refused by the line rule, not as absent: output unexpectedly contained 'matches nothing'
FAIL: bad line '.git' (paths): exit code: expected '1', got '0'
FAIL: bad line '.git' (paths): stdout is empty: expected '', got '.claude-plugin|skills|README.md|LICENSE|.git|'
FAIL: bad line '.git' (paths): stderr is empty, expected dist: lines
FAIL: bad line '.git' (paths): stderr names the offender: output did not contain '.git'
FAIL: bad line 'skills//demo' (tree): refused by the line rule, not as absent: output unexpectedly contained 'matches nothing'
FAIL: bad line 'skills//demo' (paths): exit code: expected '1', got '0'
FAIL: bad line 'skills//demo' (paths): stdout is empty: expected '', got '.claude-plugin|skills|README.md|LICENSE|skills//demo|'
FAIL: bad line 'skills//demo' (paths): stderr is empty, expected dist: lines
FAIL: bad line 'skills//demo' (paths): stderr names the offender: output did not contain 'skills//demo'
FAIL: bad line 'skills/./demo' (tree): refused by the line rule, not as absent: output unexpectedly contained 'matches nothing'
FAIL: bad line 'skills/./demo' (paths): exit code: expected '1', got '0'
FAIL: bad line 'skills/./demo' (paths): stdout is empty: expected '', got '.claude-plugin|skills|README.md|LICENSE|skills/./demo|'
FAIL: bad line 'skills/./demo' (paths): stderr is empty, expected dist: lines
FAIL: bad line 'skills/./demo' (paths): stderr names the offender: output did not contain 'skills/./demo'
FAIL: CRLF (tree): stderr does not name CR or line endings: dist: dist.include lists '.claude-plugin', which matches nothing in 7dd4740750d6f00125ea44c69266a24a2663a534
FAIL: CRLF (tree): refused for the line endings, not as absent: output unexpectedly contained 'matches nothing'
FAIL: CRLF (paths): stderr does not name CR or line endings: dist: dist.include lists '.claude-plugin', which matches nothing in /tmp/claude-1000/tmp.Ind2B6ecUX/plug in
FAIL: CRLF (paths): refused for the line endings, not as absent: output unexpectedly contained 'matches nothing'
FAIL: enabled from skills/: exit code: expected '0', got '1'
FAIL: tree from skills/: exit code: expected '0', got '1'
FAIL: tree from skills/: stdout is not a bare object id: ''
FAIL: tree from skills/: same sha as from the root: expected '578739d453b00348dd7bd3bd79a24eef2ed1e823', got ''

```

Totals: 33 failure(s), suite ran to its last scenario. The `tree` bad-line cases
fail only on the not-absent check; the `paths` ones fail on exit code, stdout
and stderr.
