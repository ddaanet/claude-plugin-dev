# Item 1.1/5 RED — pattern characters

Test added to tests/dogfood-test.sh (367 lines): a loop over `a*b.log`,
`a?b.log`, `a[b.log`, `a]b.log`, `a\b.log`, a fresh consumer per name. `bash -n`
and `shellcheck` clean. `toolkit/dogfood.sh` untouched.

Fixture per name: `*.log` ignored, the name committed-around (ignored), a new
tracked `skills/demo/new.md` committed, then `dist/plugin/sentinel` placed after
the fixture ignore-list assertion (which passes: list is exactly `<name>|`).

Committed SUT, each of the five names fails exactly four assertions, none a
harness error (the fixture-list assertion passes for all five):

- `a pattern character (<name>) exit code: expected '1', got '0'`
- `a pattern character (<name>): stderr does not name it: ''`
- `a pattern character (<name>): the copy is untouched: '.../dist/plugin/sentinel' is not a regular file`
- `a pattern character (<name>): rsync never ran: '.../dist/plugin/skills/demo/new.md' exists`

Suite total: 20 failures, all from this slice; slices 1-4 and the rest pass.

Notes: the name is matched with `[[ == *"$name"* ]]`, not `assert_contains`,
whose needle is a live BRE. The sentinel is created after the ignore-list check
because creating `dist/plugin/` first adds `dist/` and `dist/plugin/` to the
list.
