# 2026-09-01 — Fixes from a whole-toolkit shell-gotchas audit

An audit of all five shipped scripts, the four test suites and both
justfiles against the shell-gotchas catalog — the class `shellcheck`
cannot see, which was already clean on every file. `version-guard.sh`'s
findings are deliberately left for a separate pass: they change the hook's
output channel and need their own test rewrite.

**`install.sh` could replace a consumer's whole `.claude/settings.json`.**
The jq pass that appends the hook filtered existing entries with
`select(.matcher | test("Write|Edit"))`. A `PreToolUse` entry with no
`matcher` key is legal — it matches every tool, and it is the ordinary
shape of a hand-written block — and `null | test(...)` aborts jq with
exit 5. `2>/dev/null` swallowed the diagnosis and the `||` fallback wrote
a document holding nothing but the version-guard hook, which then
replaced the consumer's permissions, env, status line and their own
hooks. The script printed `installed.` over it.

The fallback is now a genuine branch on whether the file exists, rather
than an error path that a failed rewrite can fall into: a jq failure over
an existing file is a hard error that leaves the file alone. The matcher
test treats a null matcher as matching, which is what Claude Code itself
does. Both `2>/dev/null` redirections in the script are gone — jq's parse
error names the line and column, and that was the only actionable half of
the "not valid JSON" report.

**Files are no longer replaced by `mv`-ing a `mktemp` file over them.**
`mktemp` creates 0600 and `mv` carries that mode to the destination, so
every install narrowed `settings.json`, every marketplace bump narrowed
`marketplace.json`, and this repo's own `whitespace` recipe would have
staged a mode change on any 755 script it rewrote. `install.sh` and the
`whitespace` recipe now write through the destination with `cat >`, which
keeps an existing file's mode, ownership and ACL and creates a new one at
the umask. `bump_marketplace` keeps the `mv` and `chmod 644`s the temp
file first: the no-op guard immediately above it depends on the replace
needing directory write rather than file write, and relaxing that would
change what `check_marketplace_writable` is for.

**The release drift check no longer reads any tag as the last release.**
`release_preflight` used `git describe --tags --abbrev=0`, which returns
the nearest tag of any name, distance-ordered rather than
version-ordered. A consumer with a `nightly-*` or docs tag on a later
commit had releases refused by `plugin.json version (1.2.3) does not
match latest tag (vnightly-2026)`, with a hint telling them to revert a
bump they never made. It now uses `git tag --list 'v*' --sort=-v:refname`
— the same reasoning the first-release check thirteen lines above already
carried in a comment, and which this line contradicted.

**A detached-HEAD marketplace repo is refused in preflight.** It was
discovered only by the marketplace push, which runs after the plugin's
commit, tag, tag push and GitHub release are all public; recovery was a
`resume-release` the failure never mentioned. `common_preflight` already
validated `MARKETPLACE_DIR` three other ways.

**`install.sh` keeps a rewritten justfile's trailing newline.**
`$(cat justfile)` strips every trailing newline and the format string
supplied none, so adding the import line left the file with no final
newline and a `\ No newline at end of file` in the consumer's next diff.

**Recipe arguments are passed through `quote()`.** just interpolates
`{{ref}}` textually before the recipe's shell parses the line, so the
surrounding double quotes never protected anything: a caller's `$(...)`
ran in the recipe's shell. Self-inflicted only — the argument is typed by
the person running the recipe — but a ref containing `$` or a backtick
was mishandled either way. Applied to `release` and `update-plugin-dev`
in `release.just`, and to this repo's own `release` recipe.

**Three test suites gained `unset CDPATH`.** `release-test.sh`,
`update-plugin-dev-test.sh` and `dist-tree-test.sh` all compute
`repo_root` with `$(cd "$(dirname "$0")/.." && pwd)`, whose operand
begins with a path component and so is subject to `CDPATH` search. With
`CDPATH` set, `cd` echoes its target into the capture and all three died
with a two-line path. `hook-test.sh`, `release.sh` and `check-version.sh`
already carried the guard.

Four regression scenarios were added, each watched failing against the
unchanged scripts first: settings preservation over a matcher-less entry
(with mode and justfile-newline assertions), the jq parse error reaching
the user, a non-`v` tag not blocking a release, and a detached-HEAD
marketplace refused before anything is published.
