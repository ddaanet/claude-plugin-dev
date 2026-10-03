# Item 1.3 — test hardening

Scripts under test unchanged (`git diff toolkit/` empty). Three suites changed.

## Changes

- m10, `tests/dogfood-pre-tool-test.sh`: `run_pre_tool` and the two hand-built
  payloads (jq-less scenario, deny-build stub scenario) carry
  `cwd: "$sandbox/elsewhere"`, the real directory `run_dogfood` creates and also
  exports as `CLAUDE_PROJECT_DIR`.
- m11, `tests/dogfood-launcher-test.sh`: "the shim exports the copy" runs
  `CLAUDE_PROJECT_DIR="$sandbox/elsewhere" run_claude`, the elsewhere being the
  existing viable decoy consumer.
- m12: the `session_start` helper and its two assertions are removed from the
  launcher suite. The session-start suite did not cover an invocation through a
  symlinked repo (its existing symlink test links the variable's entry, with the
  script invoked at the physical path), so a new scenario "session-start invoked
  through a symlinked repo matches the physical copy" invokes the script via
  `$sandbox/link/plugin-dev/dogfood.sh` with the variable at the physical copy
  and asserts silence. The "another repo's copy" framing is not carried over.
- Review recommendation, launcher suite: new scenario "a variable equal to a
  glob-named copy skips the sync", consumer root `my [consumer]`. Note: the shim
  as shipped already quotes the comparison, so the scenario is green on
  unchanged code.

## Mutation proof

1. m10, `toolkit/dogfood.sh` `pre_tool`: replaced the `path="$(jq -j ...` line
   with `payload="$(cat)"; root="$(jq -j '.cwd' <<<"$payload")"` plus the path
   read from `$payload`. Pre-tool suite red: 69 FAIL lines, first
   `pre-tool denies an Edit into the copy: stdout is one JSON object ... over stdout ''`.
   Restored by swapped Edit; `rg 'payload="\$\(cat\)"'` no hit,
   `git diff --stat toolkit/` empty.
2. m11, `toolkit/bin/claude`: inserted `root="${CLAUDE_PROJECT_DIR:-$root}"`
   after `root="${root%x}"`. Launcher suite red, 2 failures:
   `the shim exports the copy: expected '.../my consumer/dist/plugin', got '.../elsewhere/dist/plugin'`
   and
   `...the launch directory's repo is not synced: '.../elsewhere/dist' exists`.
   Removed by the exact reverse edit; grep for `CLAUDE_PROJECT_DIR:-` no hit,
   diff empty.
3. Session-start scenario, `toolkit/dogfood.sh` `root_dir`: `cd -P --` changed
   to `cd -L --`. Session-start suite red, 1 failure:
   `session-start invoked through a symlinked repo is silent on the physical copy prints nothing on stdout: expected '', got '{"systemMessage":"... does not load .../link/dist/plugin ..."`.
   Swapped back; grep for `cd -L` no hit, diff empty.
4. Glob root, `toolkit/bin/claude`: `!= "$root/dist/plugin" ]]` changed to
   `!= $root/dist/plugin ]]`. Launcher suite red, 1 failure:
   `a variable equal to a glob-named copy skips the sync: no copy made: '.../my [consumer]/dist' exists`.
   Swapped back; grep for `!= $root` in the shim no hit, diff empty.

Final check after all restores: `git diff --stat toolkit/` empty.

## Gates

Each of the three suites green in the foreground, `shellcheck` clean on each,
`just precommit` green in the foreground on the first run (no flake).
