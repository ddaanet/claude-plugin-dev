#!/usr/bin/env bash
# Static consistency between prose and the tree it describes. Two facts that
# CLAUDE.md states as rules and nothing enforced:
#
#   1. The install and update instructions live in BOTH READMEs. `README.md`
#      presents this repo; `toolkit/README.md` is the manual that ships in the
#      dist tree. Only one of the two ships, which is exactly why a change to
#      one is easy to forget in the other. The prose differs on purpose --
#      audience, depth -- so only the commands are compared: every fenced block
#      in the root README's install/update sections must appear verbatim in the
#      toolkit README's. That is one-directional by construction (the manual
#      says more), and it still catches an edit to either side of a shared
#      block, which is the drift that actually happens.
#   2. CLAUDE.md's Layout list names every shipped file and says what it is for.
#      A file added to `toolkit/` and not to the list is invisible to the next
#      session; a bullet left behind after a rename points at nothing.
#      `tests/dist-tree-test.sh` pins the tree itself -- this ties the prose to
#      that same tree.
#
# Usage: bash tests/doc-sync-test.sh   (run from repo root)
set -euo pipefail

unset CDPATH   # else `cd` may echo its target into the $(cd … && pwd) capture below
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

failures=0
fail() {
    printf 'FAIL: %s\n' "$1" >&2
    failures=$((failures + 1))
}

# Fenced code blocks inside the named `## ` sections of a markdown file, each
# terminated by NUL so a block containing blank lines stays one block.
# $1=file, rest=section headings (without the leading `## `).
blocks_in() {
    local file="$1"
    shift
    printf '%s\n' "$@" | awk -v file="$file" '
        NR == FNR { want[$0] = 1; next }
        /^## / {
            insec = (substr($0, 4) in want)
            next
        }
        /^```/ {
            if (!insec) next
            if (infence) { printf "%s%c", buf, 0; buf = ""; infence = 0 }
            else         { infence = 1 }
            next
        }
        insec && infence { buf = buf $0 "\n" }
    ' - "$file"
}

echo "=== the root README's install/update commands appear in the toolkit README ==="
toolkit_blocks=""
while IFS= read -r -d '' b; do
    # A record separator no markdown block can contain, so a substring match
    # below is an exact whole-block match.
    toolkit_blocks="$toolkit_blocks$(printf '\001')$b$(printf '\001')"
done < <(blocks_in toolkit/README.md "Installing in a plugin" "Updating in a plugin")

root_block_count=0
while IFS= read -r -d '' b; do
    root_block_count=$((root_block_count + 1))
    case "$toolkit_blocks" in
        *$'\001'"$b"$'\001'*) ;;
        *)
            fail "this block from README.md is not in toolkit/README.md verbatim:"
            printf '%s' "$b" | sed 's/^/    /' >&2
            printf '  a change to the install or update flow has to land in both files.\n' >&2
            ;;
    esac
done < <(blocks_in README.md "Installing in a plugin" "Updating in a plugin")

# A section renamed on one side yields zero blocks and would otherwise pass
# silently, which is the failure mode this check exists to prevent.
[ "$root_block_count" -gt 0 ] \
    || fail "no code blocks found in README.md's install/update sections (renamed heading?)"

echo "=== CLAUDE.md's Layout list matches toolkit/ ==="
# LICENSE ships but carries no explanation worth a bullet. Migration notes are
# one optional file per release, covered by the single `vX.Y.Z.md` pattern
# bullet rather than named individually -- both mirror the exemptions in
# tests/dist-tree-test.sh.
shipped="$(git ls-files toolkit/ \
    | grep -v '^toolkit/LICENSE$' \
    | grep -v '^toolkit/migrations/' \
    | sort)"
shipped="$(printf '%s\ntoolkit/migrations/vX.Y.Z.md\n' "$shipped" | sort)"

# Backtick-quoted `toolkit/...` paths anywhere in CLAUDE.md, not just the Layout
# bullets: a path named in the Conventions section is a reference to the same
# file and should not go stale either.
# shellcheck disable=SC2016  # the backticks are markdown delimiters to match on, not command substitution
documented="$(grep -oE '`toolkit/[A-Za-z0-9._/-]+`' CLAUDE.md \
    | tr -d '`' \
    | sed 's|^toolkit/migrations/v[0-9X][0-9XYZ.]*\.md$|toolkit/migrations/vX.Y.Z.md|' \
    | sort -u)"

if [ "$shipped" != "$documented" ]; then
    fail "CLAUDE.md's toolkit/ paths do not match the shipped tree"
    diff <(printf '%s\n' "$shipped") <(printf '%s\n' "$documented") \
        | sed 's/^/    /' >&2 || true
    printf '  < only in toolkit/ (add a Layout bullet)\n' >&2
    printf '  > only in CLAUDE.md (stale path, or a file that was removed)\n' >&2
fi

if [ "$failures" -ne 0 ]; then
    printf '\n%d doc-sync assertion(s) failed\n' "$failures" >&2
    exit 1
fi
echo
echo "doc sync ok ($root_block_count shared command blocks, Layout matches toolkit/)"
