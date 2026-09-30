# Item 2.1/6 RED: no next claude exits 127

Test added: scenario `=== no next claude exits 127 ===` in
tests/dogfood-launcher-test.sh, lines 299-326 (incl. comment). run_claude gained
a `$path_exact` option (whole PATH, nothing appended). SUT untouched.

Fixture PATH: `<shim dir>:<sandbox>/tools`; tools holds symlinks to bash,
dirname, git, rsync, mktemp, rm, mkdir (no claude). Nothing inherited.

Assertions: `command -v claude` under that PATH equals the shim (passes); tools
has no claude (passes); rc == 127 (passes, bash's exec failure); stderr contains
`no other claude on PATH` (RED); copy manifest exists (passes, sync ran).

Red run:

    === no next claude exits 127 ===
    FAIL: no next claude exits 127: stderr does not say so: .../plugin-dev/bin/claude: line 22: exec: claude: not found
    1 failure(s)

All other scenarios pass. The failure is on the assertion, not a fixture error.
shellcheck clean; file is 327 lines.
