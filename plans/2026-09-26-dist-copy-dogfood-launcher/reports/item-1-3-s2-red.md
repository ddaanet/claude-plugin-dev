# Item 1.3/2 RED

SUT: unchanged (the committed `session_start` compares the whole variable to
`<root>/dist/plugin` as a string, so each non-exact spelling warns). Three
scenarios added to tests/dogfood-test.sh after the 1.3/1 tests, each using
`make_consumer` and `run_session_start` with the variable as a prefix. The
symlink scenario links `$sandbox/link` to the physical root and sets the
variable to `$sandbox/link/dist/plugin`, while the script is invoked at the
physical path, so only `pwd -P` of the entry matches it. `shellcheck` clean.
Suite: 3 failure(s), all `FAIL:` assertions, no harness error. Each test's exit
code and stderr assertions pass; only the stdout assertion reds.

- session-start is silent on one entry of several
  (`/x/other:<root>/dist/plugin`):
  `prints nothing on stdout: expected '', got '{"systemMessage":"\u001b[0mdogfood: this session does not load <root>/dist/plugin ...'`
- session-start is silent on a trailing slash (`<root>/dist/plugin/`): same
  assertion, same warning object on stdout
- session-start is silent on a symlinked spelling (`$sandbox/link/dist/plugin`):
  same assertion, same warning object on stdout

No mutation needed: the tests red against the committed SUT.
