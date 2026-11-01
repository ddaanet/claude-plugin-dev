#!/usr/bin/env bash
# Guards what a consumer actually receives. `git subtree pull` copies the
# ROOT tree of whatever ref it is given, so anything sitting beside the
# shipped scripts ships too. Consumers were receiving the toolkit's whole
# working environment -- the `memory` gitlink (which fatals a consumer's
# `git submodule status` repo-wide), `.claude/settings.json` and `CLAUDE.md`
# (which change a consumer agent's behaviour), plus this repo's own justfile,
# docs, plans and tests.
#
# The fix is that consumers pull a `dist-vX.Y.Z` ref produced by
# `git subtree split --prefix=toolkit`, whose root IS toolkit/. This test
# pins toolkit/'s contents exactly -- the tree the next dist tag is cut from.
# An added file there is shipped to every consumer, so it must be a
# deliberate edit to the list below, not a silent inheritance.
#
# Usage: bash tests/dist-tree-test.sh   (run from repo root)
set -euo pipefail

unset CDPATH   # else `cd` may echo its target into the $(cd … && pwd) capture below
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

failures=0
fail() {
    printf 'FAIL: %s\n' "$1" >&2
    failures=$((failures + 1))
}

# Everything a consumer is meant to receive, and nothing else. Sorted, since
# it is compared against a sorted listing.
expected="$(sort <<'EOF'
LICENSE
README.md
VERSION
bin/claude
check-refs.sh
check-refs-parse.sh
check-size.sh
check-frontmatter.sh
exempt-list.sh
check-version.sh
dist.sh
manual/dist-branch.md
manual/dogfood.md
manual/gates.md
manual/size-check.md
manual/frontmatter-check.md
dogfood.sh
gates.just
install.sh
release.just
run-bats.sh
update.sh
release.sh
release-marketplace.sh
release-preflight.sh
release-publish.sh
release-resume.sh
release-tags.sh
version-guard.sh
EOF
)"

# Asserted against the files on disk, not against `git subtree split` output.
# split reads committed history, so a split-based assertion answers for the
# previous commit -- it would pass on a run where the file being added right now
# is the one that leaks. Every non-ignored file, tracked or not, is what the next
# `git add` can stage and what the precommit sentinel hashes: read from the
# index instead, a file added after a cached pass would never be checked.
echo "=== toolkit/ holds exactly the consumer-facing set ==="
actual="$(git ls-files --cached --others --exclude-standard toolkit/ | sed 's|^toolkit/||' | sort)"

# Migration notes are shipped guidance, one optional note per release. Any
# file of exactly that shape is allowed without editing the list above;
# anything else under migrations/ is still a failure.
migration_notes="$(printf '%s\n' "$actual" | grep '^migrations/' || true)"
if [ -n "$migration_notes" ]; then
    bad="$(printf '%s\n' "$migration_notes" | grep -v '^migrations/v[0-9][0-9.]*\.md$' || true)"
    if [ -n "$bad" ]; then
        fail "unexpected files under toolkit/migrations/:"
        printf '%s\n' "$bad" | sed 's/^/    /' >&2
    fi
    actual="$(printf '%s\n' "$actual" | grep -v '^migrations/' || true)"
fi

if [ "$actual" != "$expected" ]; then
    fail "toolkit/ does not match the shipped set"
    diff <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") \
        | sed 's/^/    /' >&2 || true
fi

# A shim without its execute bit is skipped by PATH lookup without a word.
echo "=== toolkit/bin/claude is executable on disk ==="
[ -f toolkit/bin/claude ] && [ -x toolkit/bin/claude ] \
    || fail "toolkit/bin/claude is not an executable file on disk"

# Consumers call these as `plugin-dev/<name>`, with no `bash` before them, and
# a script without its execute bit fails there with "Permission denied".
for exe in run-bats.sh check-refs.sh check-size.sh check-frontmatter.sh; do
    echo "=== toolkit/$exe is executable on disk ==="
    [ -f "toolkit/$exe" ] && [ -x "toolkit/$exe" ] \
        || fail "toolkit/$exe is not an executable file on disk"
done

# Named separately from the exact-set check above: this is the specific
# breakage consumers reported, and a bare `git submodule status` in a
# consumer fatals repo-wide on an unregistered gitlink.
echo "=== toolkit/ carries no submodule gitlink ==="
# On disk a gitlink, or a nested repository not yet added, is a directory where
# the listing otherwise holds files only.
nested=""
while IFS= read -r -d '' p; do
    [ -d "$p" ] && nested+="$p"$'\n'
done < <(git ls-files -z --cached --others --exclude-standard toolkit/)
if [ -n "$nested" ]; then
    fail "toolkit/ contains a gitlink (breaks consumers' git submodule status)"
fi

if [ "$failures" -ne 0 ]; then
    printf '\n%d dist-tree assertion(s) failed\n' "$failures" >&2
    exit 1
fi
echo
echo "dist tree ok ($(printf '%s\n' "$expected" | wc -l | tr -d ' ') files, bin/claude, run-bats.sh, check-refs.sh, check-size.sh and check-frontmatter.sh executable, no gitlink)"
