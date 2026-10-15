# Slice 1 green: toolkit/dist.sh

## Gates

- `shellcheck toolkit/dist.sh`: clean.
- `bash tests/dist-tree-test.sh`: exit 0,
  `dist tree ok (12 files, bin/claude executable, no gitlink)`.
- `bash tests/doc-sync-test.sh`: exit 0,
  `doc sync ok (5 shared command blocks, Layout matches toolkit/)`.
- `bash tests/dist-test.sh`: exit 1, `10 failure(s)`. All ten are one defect in
  the test, described below. Every other assertion passes.

## toolkit/dist.sh

268 lines, mode 755, staged with `git add toolkit/dist.sh`, not committed.

## Wiring

- `justfile` `precommit`: `toolkit/dist.sh` in the shellcheck line after
  `toolkit/dogfood.sh`; `tests/dist-test.sh` in the `bash -n` line and in the
  run list after `tests/dist-tree-test.sh`. `just --list` parses.
- `tests/dist-tree-test.sh`: `dist.sh` added to the expected list after
  `check-version.sh`.
- `CLAUDE.md`: Layout bullet for `toolkit/dist.sh` inserted before the
  `toolkit/dogfood.sh` bullet; `dist-test.sh` added to the quality-gate test
  list after `dist-tree-test.sh`.

## Test defect (not edited)

`tests/dist-test.sh`, bad-line table in the "tree and paths: refuses each
malformed allowlist line" scenario. Five entries use a needle that is a label,
not a substring of the line the script names:

- `glob-star` for line `glob-st*ar`
- `glob-query` for line `glob-qu?ery`
- `br-open` for line `br-op[en`
- `br-close` for line `br-clo]se`
- `back-slash` for line `back\slash`

The assertion `stderr names the offender` requires the stderr to contain the
needle, so it fails for each of the five, in both `tree` and `paths` mode: 10
failures. The script's stderr is correct, for example:

`dist: dist.include line 5 'glob-st*ar' has a glob or escape character (* ? [ ] or backslash); listed paths are literal`

The needle should be the line itself (or a substring of it such as `st*ar`), not
the label. The `dotdot`, blank, absolute and `..` entries use needles that are
substrings of their lines and pass.

## Notes on choices the contract left open

- Unknown subcommand exits 1 with a `dist:` line (the contract's refusal exit),
  not 2.
- `enabled` and `tree` test presence with
  `git ls-tree <commit> -- dist.include`, not `git cat-file -e`. The latter
  exits 128 for an absent path, which broke the "only in the worktree" case.
- A missing root `README.md` in the result tree is warned as absent (treated as
  under 40 words), not silently skipped.
- `validate` sends claude's stdout to stderr, so this script's stdout stays
  empty there.
- `validate` extracts with `git archive`, as the plan says, so `export-ignore`
  attributes in the tree would apply.

## Green review

Verdict: CHANGES (two real defects, both small; the rest is sound)

Gates re-run: `shellcheck toolkit/dist.sh` is clean, `dist-tree-test.sh` and
`doc-sync-test.sh` pass, and `dist-test.sh` prints "all dist scenarios passed".
The justfile wiring (shellcheck list, `bash -n` list, run list), the
`dist-tree-test.sh` list entry and the CLAUDE.md Layout bullet and gate-list
entry are correct and complete. The five corrected needles are the line text
(`glob-st*ar`, `glob-qu?ery`, `br-op[en`, `br-clo]se`, `back\\slash`). Each is a
substring of the line the script names, and they remain strong because the
fixtures create the real files. The edit is fine.

Changes:

1. **Medium: `enabled` and `tree` break when run from a subdirectory.**
   `git ls-tree` without `--full-tree` is relative to the cwd and limited to it.
   `cmd_enabled`, the `dist.include` probe in `cmd_tree`, and the
   `ls-tree -r -l -z` listing all use it.
   - Reproducer: in a fixture repo with a committed `dist.include`, run
     `cd skills && bash toolkit/dist.sh enabled HEAD; echo $?`. It prints 1.
     `dist.sh tree HEAD` from there prints
     `dist: no dist.include in <sha>: the plugin is not opted in`.
   - Worse, a script that is opted in reports "not opted in". `release.sh` would
     silently skip publication.
   - Fix: add `--full-tree` to all three `git ls-tree` calls.
   - Verified in a scratch copy: with
     `sed 's/git ls-tree /git ls-tree --full-tree /'`, `enabled` returns 0 and
     `tree` gives the same sha from the subdirectory and the root.
   - Alternatively `cd "$(git rev-parse --show-toplevel)"` at the top of `main`.
     The header says "run from a plugin repo's root", but nothing enforces it,
     and the failure mode is a silent skip.
2. **Medium-low: `paths` accepts spellings that `tree` refuses.**
   `read_allowlist` has no rule for `.`, `./x`, `skills/.` or a doubled slash,
   and its `-e` check is satisfied by the worktree.
   - Reproducer: a `dist.include` holding `.` makes `dist.sh paths "$PWD"` print
     `.` with rc 0. `./README.md`, `.git` and `skills//` (printed as `skills/`,
     with the trailing slash left in) also pass.
   - `tree` refuses each of them as "matches nothing" (verified for `.`,
     `./README.md`, `skills//`, `skills/.`).
   - Impact: `dogfood.sh sync` would receive `.` or `.git` and ship everything,
     or a path with a stray slash, while `release` refuses the same file. The
     plan says `paths` applies "the same line rules".
   - Fix: in `read_allowlist`, refuse any line with an empty or `.` component
     (`*//*`, `./*`, `*/.`, `.`, and `.git` as a first component if you want
     it), and strip trailing slashes consistently.
   - Add a test line for `.` and `./README.md` through `paths`, which currently
     pass.
3. **Low: a CRLF `dist.include` gives a misleading refusal.** The `\r` stays in
   each path and the message is "lists '.claude-plugin', which matches nothing",
   with the `^M` invisible. Either refuse a line ending in `\r` with a clear
   message or strip it. Reproducer:
   `printf '.claude-plugin\r\nskills\r\n' > dist.include; dist.sh paths "$PWD"`.
4. **Low: the license warning is wrong without `jq` or with an unparseable
   manifest.** `jq ... 2>/dev/null` failing is read as "no license".
   Reproducers: run `tree` with a PATH lacking `jq`, or commit `{bad` as
   `plugin.json`. Both print "no LICENSE file at the root and no license in
   plugin.json" for a plugin that has one. jq is already a toolkit dependency,
   so fix this by failing with a `dist:` line when `jq` is absent. A warning
   that claims something false is worse than none.
5. **Style, optional:**
   - `cmd_commit` repeats the whole env-plus-`commit-tree` command in its two
     branches. One array, `args=(-p "$parent")` when set, removes the
     duplication.
   - In `cmd_tree`, `listed` and `matched` are globals, not declared `local`.
   - `matched` is filled by a counted `while` loop.
   - A run outside a git repo reports "'X' is not a commit".

Probed and found correct:
- **Literal pathspecs and NULs:** a newline or space in a path round-trips.
- **Gitlink and symlink detection:** both are caught anywhere in the result.
- **Warnings:** computed on the result only, per the suite's unlisted-bulk case.
- **Commit reproducibility:** the raw date round-trips exactly for `+0530`,
  `-0930` and `+0000`. `commit.gpgsign=true` with a failing `gpg.program` does
  not affect `commit-tree`.
- **Dashed arguments:** `tree -x` and `commit -x y z` fail cleanly with a
  `dist:` line.
- **`validate`:** a failing `claude` stub's status 3 propagates, and it refuses
  without `claude` on PATH.
- **Temp cleanup:** the trap leaves no temp dir after refusals or a failing
  validate.
- **Performance:** a 6000-file listed directory builds in about 2.8 s.
- **Portability:** no GNU-only flag, and bash 3.2 is safe. There is no `stat`,
  `sed -i`, `head -c`, `find` or `date -d`. `mktemp -d` and `wc -w | tr -d ' '`
  are portable, and the empty `listed` array is never indexed.

## Review fixes

Changes to toolkit/dist.sh (staged, not committed; 283 lines):

- `enabled` and `tree` use `git ls-tree --full-tree` for all three calls (the
  dist.include probe in each and the listing), so a subdirectory cwd behaves as
  the root does.
- `read_allowlist`, shared by `tree` and `paths`: after stripping one trailing
  `/`, refuses a `.` or `.` component, a `.git` component, and an empty
  component (`//` or a trailing `/`). Each is a line-rule refusal naming the
  line and runs before the absence check. A file with any carriage return is
  refused once as "dist.include has CRLF line endings" and the script exits.
- `read_allowlist` exits 1 after its line-rule refusals, so no matching or
  absence check runs on a list that already failed.
- `tree` refuses without `jq` on PATH, and refuses a `plugin.json` that is not
  valid JSON, so a missing or broken license read can no longer produce the
  false "no license" warning.
- Left alone (style nits, per the instruction): the duplicated commit-tree
  branches in `cmd_commit`, the global `listed` and `matched` in `cmd_tree`, and
  the counted `while` filling `matched`.

Gates:

- `bash tests/dist-test.sh`: exit 0, "all dist scenarios passed" (0 failures).
- `shellcheck toolkit/dist.sh`: clean.
- `bash tests/dist-tree-test.sh`: exit 0, "dist tree ok (12 files, bin/claude
  executable, no gitlink)".
- `bash tests/doc-sync-test.sh`: exit 0, "doc sync ok (5 shared command blocks,
  Layout matches toolkit/)".

## Fix re-review

Verdict: APPROVE

Re-run on a scratch repo under `$TMPDIR`; `dist-test.sh` prints "all dist
scenarios passed". Nothing in the tracked tree was edited.

Findings fixed:

- **1 (Medium, subdirectory cwd): fixed.** From `skills/`,
  `dist.sh enabled HEAD` returns 0, and `tree HEAD` prints the same sha as from
  the root. The three `ls-tree` calls carry `--full-tree`.
- **2 (Medium-low, `paths` vs `tree` rules): fixed.** I ran `.`, `./README.md`,
  `skills//`, `skills/.`, `skills/./s.md`, `./`, `skills///`, `.git`, `.git/x`,
  `a/.git`, `/`, `//` and `.claude-plugin/..` through both subcommands. Each is
  refused with the identical stderr text. The two subcommands share
  `read_allowlist`.
- **3 (Low, CRLF): fixed.** CRLF, a lone trailing `\r` without a newline, and
  `.claude-plugin\r\n.git` each give one "CRLF line endings" refusal, exit 1, in
  both modes. It never reports "matches nothing" for them.
- **4 (Low, false license warning): fixed.** `tree` with no `jq` on PATH exits 1
  with a `dist:` line. A committed `{bad` `plugin.json` is refused as "not valid
  JSON".

Regression probes, all clean:

- **Legitimate lines:** these pass in both modes: `.claude-plugin`,
  `.claude-plugin/` (trailing slash), `skills/`, `a..b`, `..hid`, `a.b`,
  `.gitignore`, `.github`, a name with a space (`sp ace`), and a final line
  without a trailing newline.
- **Newline in a name:** a file `nld/x<LF>y` under a listed directory
  round-trips into the result tree. A newline inside a listed line cannot be
  expressed, which follows from the line format and is not a regression.
- **CR detection:** a `grep` for a literal CR. It does not fire on lines
  containing the letters "CR" or on LF-only files. It fires on a CR anywhere in
  the file, including mid-line.
- **Other paths:** `paths` with no `dist.include` still exits 3 silently.
  `enabled nonsense` gives a `dist:` line.
- **Low items:** the style nits stay unfixed as stated, and the behaviour is
  unchanged for them.

Remaining nits, none blocking:

1. `tree` now checks `jq` before it checks for `dist.include`. A plugin that is
   not opted in and has no `jq` is told about `jq`, not "not opted in".
   Reproducer: `PATH` without `jq`, `tree` on a commit with no `dist.include`.
   This is harmless because `release.sh` already needs `jq`, and `enabled` does
   not need it.
2. A path with a literal CR in its name is unlistable, since any CR refuses the
   file. This is acceptable.
