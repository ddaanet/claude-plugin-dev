# Item 2.1 slice 1 RED

Files (uncommitted): `toolkit/bin/claude` (inert stub: `exit 0`, mode 0755),
`tests/dogfood-launcher-test.sh` (four tests). `bash -n` and `shellcheck` clean
on both. Run in the foreground: `bash tests/dogfood-launcher-test.sh`.

Fixture: consumer at `$sandbox/my consumer` with `plugin-dev/dogfood.sh` and
`plugin-dev/bin/claude` vendored; stub claude in `$sandbox/stub` recording argv
(NUL-separated), PWD, PATH, CDPATH-or-`<unset>`, CLAUDE_CODE_PLUGIN_DIRS under
`$sandbox/rec/`. Launch by PATH lookup with CDPATH=/tmp, behind a 10 s
background watchdog that fails on the kill.

## Per-test failures (all on their own assertion; 4 failures, none pass)

- the shim execs the next claude with argv intact: expected '--foo|a b|', got
  '<stub did not record argv>'
- the shim syncs before exec: '.../my
  consumer/dist/plugin/.claude-plugin/plugin.json' is not a regular file
- the shim exports the copy: expected '<root>/dist/plugin', got
  '<stub did not record plugin_dirs>'
- the shim unsets CDPATH: expected '<unset>', got '<stub did not record cdpath>'

Mutation proof: none needed; every test reds against the inert stub.
