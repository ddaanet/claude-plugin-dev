# Review: dist-copy dogfood launcher — code and test group

**Scope**: `git diff fd16ae65f4b244f1098b94b7ee848f5a7f74c8f2` over
`toolkit/dogfood.sh`, `toolkit/bin/claude`, `toolkit/install.sh`,
`toolkit/release.just`, `justfile`, the five `tests/dogfood-*-test.sh` suites,
`tests/install-test.sh`, `tests/update-plugin-dev-test.sh` and
`tests/dist-tree-test.sh`. Checked against outline decisions D1–D12 and runbook
Items 1.1–1.3, 2.1–2.2 and 3.1.

**Date**: 2026-09-30

**Mode**: review + fix

## Summary

The implementation matches D1–D11 on every code-side point. Phases 1 and 2
already settled the hard parts: newline-safe roots, physical-path comparison,
the fail-closed wiring pipeline and hook composition. Re-examining them found no
defect. This pass found three test-side gaps and no production defect:

- one suite ran its fixture twice, which hid the one sync that only the hard
  `/dist/plugin/` exclude protects;
- two harness helpers threw away jq's stderr without a reason;
- one `_import-check` block claimed a check it did not make.

All three are fixed, each with a mutation that proves the new assertion goes
red.

Starting gate: `just precommit` was green on the first run, with no intermittent
failure. Final gate: green (see Gate below).

**Overall Assessment**: Ready

## Issues Found

### Critical Issues

None.

### Major Issues

1. **The hard `/dist/plugin/` exclude was unpinned, although it could be
   pinned**
   - Location: `tests/dogfood-sync-test.sh`, scenario
     `sync never recurses into the copy`
   - Problem: the scenario ran `sync` twice and checked only after the second
     run. Its own comment called the hard exclude an accepted residual. That is
     wrong for the first sync:
     - `git ls-files` runs before `mkdir -p dist/plugin`, so on a first sync the
       ignore list cannot name the copy;
     - only the script's own `/dist/plugin/` entry keeps rsync from recursing
       into the copy it is writing.

     Probed with the hard exclude removed: the first sync leaves
     `dist/plugin/dist/plugin/plugin-dev/…`. The second sync's ignore list plus
     `--delete-excluded` clears it, which is why the double run stayed green. D2
     names this exclude explicitly ("so a sync never recurses into it"), and
     outline item 1 lists it as a case.
   - Fix: assert the exit code and the absence of `dist/plugin/dist/plugin`
     after the first sync, keep the post-second-sync checks, and rewrite the
     comment to say which run each check protects.
   - Mutation proof: removed `'/dist/plugin/'` from the
     `printf '%s\0' '.git' '/dist/plugin/'` line in `toolkit/dogfood.sh`, and
     the suite failed with
     `FAIL: sync never recurses into the copy: first sync: '…/my consumer/dist/plugin/dist/plugin' exists`
     (1 failure). The line was restored by the inverse `sed`,
     `git diff --quiet toolkit/dogfood.sh` came back clean, and the suite was
     green again.
   - **Status**: FIXED

### Minor Issues

1. **`jq_holds` discarded jq's stderr with no stated reason**
   - Location: `tests/dogfood-pre-tool-test.sh` (`jq_holds`),
     `tests/dogfood-session-start-test.sh` (`jq_holds`)
   - Problem: `jq -e … >/dev/null 2>&1`. The helper backs only positive
     assertions, so on a passing run jq writes nothing to stderr. The redirect
     therefore hides only the one thing worth seeing when an assertion fails:
     jq's parse error on output that is not JSON. The rule in
     `no-stderr-suppression` applies: guard the case instead, or justify the
     redirect.
   - Fix: dropped `2>&1`. The `>/dev/null` on stdout stays, since it carries
     only the boolean. Both suites were re-run alone: exit 0, 0 bytes on stderr.
   - **Status**: FIXED

2. **`_import-check`'s dogfood block claimed a check it did not make**
   - Location: `justfile`, `_import-check`, the `dogfood` block
   - Problem: the comment says the recipe "must never run a consumer's commit
     gate or start a `claude`" (D10). The code only grepped for
     `dogfood.sh" sync` and for `stub-precommit`, so a recipe that also ran
     `claude` passed. A grep for `claude` cannot fix this, because the dry run's
     own path holds the string.
   - Fix: compare the whole dry run against `bash "plugin-dev/dogfood.sh" sync`.
     That one check covers reaching the sync, running no gate and starting
     nothing else. The comment now says why the comparison is whole.
   - Mutation proof:
     - with `claude --version` appended to the recipe, `_import-check` failed
       with
       `error: dogfood ran more or less than dogfood.sh sync: … claude --version`;
     - with `dogfood: precommit`, it failed showing `echo stub-precommit`.

     Both mutations were reverted, and `git diff --quiet toolkit/release.just`
     came back clean.
   - **Status**: FIXED

## Fixes Applied

- `tests/dogfood-sync-test.sh`: `sync never recurses into the copy` asserts
  after the first sync as well, and its comment is rewritten (Major 1). The file
  is now 355 lines.
- `tests/dogfood-pre-tool-test.sh`: `jq_holds` no longer redirects stderr (Minor
  1). 384 lines.
- `tests/dogfood-session-start-test.sh`: the same change (Minor 1). 323 lines.
- `justfile`: `_import-check` compares the `dogfood` dry run whole (Minor 2).
  174 lines.
- No production file changed. Every mutation was reverted, and
  `git diff --quiet` is clean on `toolkit/dogfood.sh` and
  `toolkit/release.just`.

## Divergences from the outline (code's version judged sound)

- **D9, PATH stripping.** The outline says the shim "passes an explicit `-` to
  `paste`". The shim uses no `paste`. It rebuilds PATH by parameter expansion
  and tests each entry with `-ef`. This removes the GNU/BSD `paste` hazard
  outright, and an empty entry keeps its working-directory meaning.
- **D6, leaf symlinks.** The outline names only the nearest-existing-ancestor
  resolution. The code also resolves an existing leaf link with `readlink -fn`,
  which matches Claude Code's `realpathSync` on the leaf. That needs macOS 12.3
  or later for `-f`, as Phase 1 accepted. On an older macOS, a leaf-link edit
  fails loudly rather than being allowed silently.

## Checked, no finding

- **Scope completeness.** Every code-side decision has a deliverable:
  - D1–D3, D5 and D8 are `sync_copy`;
  - D4 holds because no `PostToolUse` hook is wired;
  - D6 is `pre_tool`;
  - D7 is `session_start`;
  - D9 is `toolkit/bin/claude`;
  - D10 is the `dogfood` recipe;
  - D11 is `add_hook` and its three calls.

  D12 and the docs are outside this group.
- **A symlinked `dist/plugin`.** Probed with `dist/plugin -> ..`. Had rsync run,
  `--delete-excluded` would have deleted the root's `.git`. It did not run:
  `git check-ignore dist/plugin/` fails with
  `fatal: pathspec 'dist/plugin/' is beyond a symbolic link` (exit 128), and
  `require_ignored_copy` stops the sync. That is the accepted-unpinned exit-128
  branch, so no test was added. See Recommendations.
- **handoff:restart and D4.** The shim strips itself from PATH before the exec,
  so a `claude` started from inside the session does not pass through it.
  handoff's restart, though, types the replayed argv into the user's tmux pane,
  whose direnv PATH puts the shim first again, so a restart does re-sync.
  Checked read-only in `handoff/skills/restart/SKILL.md`.
- **install.sh step 3.** The script runs with `set -euo pipefail`, so an
  unwirable file fails closed. Phase 2 pinned this with a test.
  - A mutation making presence require a matcher would already turn
    `a re-run is a no-op` red, because SessionStart entries carry no matcher. A
    separate PreToolUse missing-matcher presence test would add nothing.
  - `hook_cmd`, `pretool_cmd` and `session_cmd` are single-quoted, each with its
    own SC2016 disable.
  - version-guard's unquoted spelling is left as it was, per D11.
- **Recipe doc comment.** `dogfood`'s comment is one line.
- **Whitespace safety.**
  - The ignore list is NUL-delimited with `read -r -d ''`.
  - `CLAUDE_CODE_PLUGIN_DIRS` and PATH are split by parameter expansion.
  - Every captured path carries an `x` shield.
  - Test fixtures cover a spaced root, a leading space, a name holding a newline
    and a root ending in one.
- **Error surfacing.** Neither `toolkit/dogfood.sh` nor `toolkit/bin/claude`
  holds a `2>/dev/null`. The `cat … 2>/dev/null` calls in
  `tests/install-test.sh` were moved in unchanged from the update suite, so they
  are not new.
- **Portability.** Nothing needs bash 4:
  - `read -d ''`, `[[ -ef ]]` and `+=` all exist in bash 3.2;
  - `mktemp` gets an explicit template;
  - there is no `paste`, `sed -i`, `stat` or `timeout`.

  The rsync flags under openrsync are the macOS run, which is out of scope.
- **shellcheck.** Clean on both production scripts and on all six new or split
  suites. The suites are not in the gate's shellcheck line, which follows the
  existing pattern.
- **Harness convention.** Each suite carries its own copy of the assertion
  harness and runs alone.

## Requirements Validation

| Requirement | Status | Evidence |
|---|---|---|
| D1 real copy | Satisfied | rsync into `dist/plugin/`; `sync copies a tracked file` checks `-ef` against the source |
| D2 source set | Satisfied | ignore list with a leading `/` and NUL separators, plus the `.git` and `/dist/plugin/` excludes; the pattern-character refusal; the first-sync recursion is now pinned |
| D3 root layout | Satisfied | `require_manifest`; install.sh's run-in-target guard |
| D4 sync on promotion only | Satisfied | the shim and `just dogfood` are the only callers of `sync`; no `PostToolUse` |
| D5 self-located root | Satisfied | `root_dir`; decoy cwd and `CLAUDE_PROJECT_DIR` in the suites |
| D6 copy guard | Satisfied | three-channel deny, `notebook_path`, physical comparison, silent without jq |
| D7 session-start | Satisfied | whole-entry match, resolved; ANSI reset; jq notice on `systemMessage` only |
| D8 loud failure | Satisfied | rsync status and stderr passed through; the shim aborts before exec |
| D9 shim | Satisfied | sync, export, `unset CDPATH`, `-ef` strip, 127 |
| D10 recipe | Satisfied | `dogfood` recipe; `_import-check` now pins that the dry run is exactly the sync |
| D11 install wiring | Satisfied | `add_hook`, presence by command under any matcher, quoted commands, fail-closed |

**Gaps:** none.

## Gate

`just precommit`, run in the foreground after the fixes: exit 0. Checks that
passed:

- whitespace and format-docs;
- shellcheck and `bash -n`;
- `release.just import: ok (plain + widened + missing gate, resume-release, dogfood)`;
- the version-guard, check-version, release, self-release, update-plugin-dev and
  install suites;
- dist tree (11 files, bin/claude executable, no gitlink);
- docs, doc-sync and citation;
- dogfood sync, sync refusal, pre-tool, session-start and launcher.

No intermittent failure occurred in either run.

## Positive Observations

- Where a guard could go vacuous, the suites pair each negative with a positive
  over the same fixture: the jq-less runs against a jq-present control, the deny
  against the allow, a sibling that stays beside a file that goes.
- Stubs stand in for exactly one command, `git ls-files` or `rsync`, so the run
  reaches the code path under test rather than failing earlier.
- `install-test.sh` runs the hook commands as written, through `sh -c` with a
  spaced project dir. That closes the gap between the settings string and the
  script.

## Recommendations

- Nothing but git's pathspec check keeps a symlinked `dist/plugin` from rsync
  with `--delete-excluded`, which would delete the root's `.git`. If
  `require_ignored_copy` ever changes, for example to `--no-index` or a
  path-free check, add an explicit `[[ -L ]]` refusal on `dist` and
  `dist/plugin` and a test that the root's `.git` survives.
