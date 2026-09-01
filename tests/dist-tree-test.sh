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

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

failures=0
fail() {
    printf 'FAIL: %s\n' "$1" >&2
    failures=$((failures + 1))
}

# Everything a consumer is meant to receive, and nothing else. Sorted, since
# it is compared against `git ls-tree` output.
expected="$(sort <<'EOF'
LICENSE
README.md
VERSION
check-version.sh
install.sh
release.just
update.sh
release.sh
version-guard.sh
EOF
)"

# Asserted against the index, not against `git subtree split` output. split
# reads committed history, so a split-based assertion answers for the previous
# commit -- it would pass on a run where the file being added right now is the
# one that leaks. The index is what the next dist tag will be cut from.
echo "=== toolkit/ holds exactly the consumer-facing set ==="
actual="$(git ls-files toolkit/ | sed 's|^toolkit/||' | sort)"

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
    actual="$(printf '%s\n' "$actual" | grep -v '^migrations/')"
fi

if [ "$actual" != "$expected" ]; then
    fail "toolkit/ does not match the shipped set"
    diff <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") \
        | sed 's/^/    /' >&2 || true
fi

# Named separately from the exact-set check above: this is the specific
# breakage consumers reported, and a bare `git submodule status` in a
# consumer fatals repo-wide on an unregistered gitlink.
echo "=== toolkit/ carries no submodule gitlink ==="
if git ls-files -s toolkit/ | grep -q '^160000'; then
    fail "toolkit/ contains a gitlink (breaks consumers' git submodule status)"
fi

if [ "$failures" -ne 0 ]; then
    printf '\n%d dist-tree assertion(s) failed\n' "$failures" >&2
    exit 1
fi
echo
echo "dist tree ok ($(printf '%s\n' "$expected" | wc -l | tr -d ' ') files, no gitlink)"
