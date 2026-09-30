# Item 1.2/5 RED: silent without jq

Added to tests/dogfood-test.sh: the helper `make_jqless_bin <dir>` (symlinks to
`bash`, `dirname`, `mkdir`, `cat`, resolved with `command -v`; `jq` left out;
named generically for Item 1.3/4) and the test `pre-tool is silent without jq`.
`shellcheck` clean. toolkit/dogfood.sh is untouched.

The symlink set is what the `pre-tool` path invokes (`dirname` in `root_dir`)
plus what `run_dogfood` invokes (`bash`, `mkdir`, `cat`). The payload is built
with the real jq before the PATH narrows, since `run_pre_tool` calls jq.

## Per-test output

- `pre-tool is silent without jq`: red on its own assertions against the
  committed SUT.
  - Precondition (`command -v jq` fails under the jq-less PATH): passes.
  - `FAIL: pre-tool is silent without jq exit code: expected '0', got '127'`
  - `FAIL: pre-tool is silent without jq prints nothing on stderr: expected '', got '.../my consumer/plugin-dev/dogfood.sh: line 86: jq: command not found'`
  - The stdout assertion passes (empty), as expected.
- All other scenarios pass; suite total: 2 failures, both from this test.
