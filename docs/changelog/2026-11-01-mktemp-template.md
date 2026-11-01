# Every mktemp call names its directory

Every `mktemp` call with no template in the toolkit scripts, the justfile and
the test suites now reads `mktemp [-d] "${TMPDIR:-/tmp}/<name>.XXXXXX"`. macOS
`mktemp` without a template ignores `TMPDIR` and writes under `/var/folders`,
which the Claude Code command sandbox refuses; GNU honours `TMPDIR`, so Linux
never showed it. BSD randomises only a trailing run of Xs, so the template ends
in them.

`tests/mktemp-template-test.sh` pins it as a static scan of every shell file
rather than the stub the brief proposed, because a stub sees only the paths a
test reaches and most of these calls sit on a failure path or in a fixture.
