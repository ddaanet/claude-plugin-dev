# Item 1.1/1 test review

Verdict: **fixed, still red on assertions.** Six plausible wrong implementations
went green against the suite as delivered. All six now fail, and a
runbook-conformant `sync` passes. No stub gap: `toolkit/dogfood.sh` is
unchanged. `bash -n` and `shellcheck` are clean. Nothing committed.

## Mechanical check

`bash tests/dogfood-test.sh` against the inert stub exits 1 with 14 failures,
all `FAIL:` assertion lines. There are no errors and no aborts. All four tests
are red:

- `sync copies a tracked file`: regular-file and `cmp` assertions.
- `sync leaves out an ignored file and .git`: three presence assertions.
- `sync resolves the root from its own location`: regular-file assertion.
- `unknown subcommand is usage`: exit code 2 and the stderr words, for both
  `bogus` and no argument.

## Wrong-reason hunt

Method: copy the suite to a scratch tree whose `toolkit/dogfood.sh` is a
candidate implementation, then run it. This is a throwaway probe, deleted
afterwards; nothing in the repo was touched. The candidates:

| Candidate | Before fixes | After fixes |
|---|---|---|
| Runbook-conformant: D2 rsync, root from `$0`, usage exit 2 | green | green |
| `tar` everything except `dist/` | red (`build.log`, `.git`) | red |
| rsync without the `.git` exclude | red (`.git`) | red |
| symlink `skills/` and `.claude-plugin/` into `dist/plugin/` | **green** | red |
| root = cwd if it is a plugin repo, else own location | **green** | red |
| root = `CLAUDE_PROJECT_DIR` if it has a manifest, else own location | **green** | red |
| exclude `.*` (drops `.claude-plugin/`, so the copy cannot load) | **green** | red |
| copy only subdirectories (drops root-level files) | **green** | red |
| hardlink each tracked file | **green** | red |

## Fixes, all in `tests/dogfood-test.sh`

1. **`sync copies a tracked file` accepted a linked copy.** `-f && ! -L` on the
   file cannot see two cases: a path through a symlinked directory
   (`dist/plugin/skills -> ../../skills`), which is exactly the realpath hazard
   behind D1, and a hardlink, which makes every source edit live in the copy and
   defeats D4. Added a `-ef` assertion that the copy is not the source file
   itself.
2. **`sync leaves out an ignored file and .git` had unpaired negatives.** Its
   only positive was the deep `skills/demo/SKILL.md`. A sync that dropped
   root-level files or dot-directories therefore passed both absences.
   - `build.log` is now paired with a tracked `kept.log` beside it: same
     directory, same suffix, only the ignore rule differs.
   - `.git` is now paired with `.claude-plugin/plugin.json`, a tracked root
     dot-directory. It is also the one file the copy needs to load at all (D3).
3. **The root-resolution test's absence checks were proxy-stale.** The cwd
   (`$sandbox`) and `CLAUDE_PROJECT_DIR` (`$sandbox/elsewhere`) were not git
   repos. A script that preferred either one and fell back to its own location
   therefore took the fallback and passed. A new `make_decoy` helper makes both
   directories valid plugin roots, a git repo with a manifest and
   `/dist/plugin/` ignored, so the decoy is found first. The `$sandbox/dist` and
   `elsewhere/dist` absences now go red for a cwd-first or
   `CLAUDE_PROJECT_DIR`-first root. Following the runbook, the cwd is still
   `$sandbox`.
4. **The usage test did not pin the channel.** It now asserts stdout empty for
   `bogus` and for no argument. The interface says the usage goes to stderr, and
   a script that printed it to both passed.
5. **Fixture commits honoured a global `commit.gpgsign=true`.** `commit_all` and
   `make_decoy` now pass `-c commit.gpgsign=false`, as `self-release-test.sh`
   does. Without it, a signing consumer machine (outline Risks: the macOS run)
   would error on the fixture rather than on an assertion.

## Checked, no change

- Fixture matches the runbook.
  - `$sandbox/my consumer` holds a space and is the `pwd -P` spelling.
  - It has a root `plugin.json`, `.gitignore` `/dist/plugin/`, a tracked
    `skills/demo/SKILL.md`, and the vendored `plugin-dev/dogfood.sh`, all
    committed.
  - `unset $(git rev-parse --local-env-vars)` and `unset CDPATH` run before any
    `cd`.
  - There is no `timeout`. Slice 1 has no run that can loop: a sync that
    recurses into its own copy nests once per run and does not spin.
- Whitespace: every path is quoted. The spaced consumer path reaches the script
  as `bash "$consumer/plugin-dev/dogfood.sh"`.
- Harness shape follows the repo convention: its own copy of the assertion
  helpers, one script under test, and non-aborting `fail` so every assertion
  runs. `assert_contains` uses the same `printf | grep -q` pipe as
  `self-release-test.sh` and `citation-test.sh`. Its input is far below a pipe
  buffer, so `pipefail` cannot see a SIGPIPE from it.
- Root spelling (`pwd -P` against the logical path) is not observable through
  `sync`'s output in this slice. The fixture path is already physical. That is a
  limit of the slice, not a gap in the test. The physical comparison is
  exercised by Item 1.2's copy guard.

## Residual, for GREEN

The absence assertions and the `-ef` check are still vacuous against the stub,
because there is no copy for them to inspect. The pairings above make them live
once any copy exists. They have been seen red only in this review's scratch
probe, not in the repo.

When GREEN reaches green, it should prove the `.git` hard exclude and the ignore
list by one mutation each, per `craft:test-discipline`: drop the `.git` exclude,
then drop the ignore-list feed. Each mutation must turn its own assertion red.

Suite length is 186 lines.
