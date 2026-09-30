# Item 2.1 slice 5 RED: a failed sync aborts the launch

Test added to tests/dogfood-launcher-test.sh (scenario
`a failed sync aborts the launch`): fresh `make_consumer` (empty rec/), manifest
removed, then asserts rc is exactly 1, stderr contains
`.claude-plugin/plugin.json`, and neither rec/argv nor rec/pid exists.

Against HEAD the test passes (expected: the shim's `set -euo pipefail` already
ends it with sync's status). Proven non-vacuous by mutation below.

## Mutation proof

Test: `a failed sync aborts the launch`. SUT: toolkit/bin/claude line 18.

1. `bash "$root/plugin-dev/dogfood.sh" sync` -> `... sync || true`. Red on all
   three assertions:
   - `the shim exits with sync's status: expected '1', got '0'`
   - `the next claude did not run: '.../rec/argv' exists`
   - `the stub left no record: '.../rec/pid' exists`
2. `... sync` -> `... sync || exit 0` (swallows the status, still no exec). Red
   on the status assertion alone: `expected '1', got '0'`; the no-exec
   assertions stay green.

Each restored by the inverse Edit replacement (a first sed-based restore failed
on the `|` delimiter and was redone with Edit). After the final restore: grep
for `|| true` / `|| exit 0` in the SUT: no hit;
`git diff --quiet toolkit/bin/claude` succeeds; suite green
(`all dogfood launcher scenarios passed`); `bash -n` and `shellcheck` clean on
the test file.
