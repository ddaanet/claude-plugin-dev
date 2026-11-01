# The mktemp scan whitelists the call's shape and states its scope

`tests/mktemp-template-test.sh` asked only whether a `$(mktemp ...)` ended a
word in Xs, so `mktemp -t name.XXXXXX` and
`mktemp -d 2>/dev/null || mktemp -d -t x.XXXXXX` passed, though macOS
`mktemp -t x` was probed landing under `/var/folders` and the second holds a
bare call. It now admits only an optional `-d` followed at once by the template,
double-quoted, single-quoted or unquoted, ending in the Xs and followed by a
space, `)` or the end of the line.

The scan reads `*.sh`, `*.just` and justfiles. The record "Every mktemp call
names its directory" says "every shell file", which overstates that: an
extensionless script such as `toolkit/bin/claude` is not read. The scope stays
as it is, and the suite header and `tests/CLAUDE.md` now name it.
