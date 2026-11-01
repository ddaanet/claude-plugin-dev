#!/usr/bin/env bash
# Refuses a `mktemp` call with no template in this repo's shell code. macOS
# mktemp without a template places its file under _CS_DARWIN_USER_TEMP_DIR and
# reads TMPDIR only as a fallback, so inside a command sandbox that grants TMPDIR
# and not /var/folders the call fails outright; GNU honours TMPDIR, so Linux
# never shows it. The portable form names the directory, and ends in the Xs
# because BSD randomises only a trailing run:
#
#     mktemp [-d] "${TMPDIR:-/tmp}/<name>.XXXXXX"
#
# A static scan rather than a run under a stub: a stub sees only the paths a
# test reaches, and most of these calls sit on a failure path or in a fixture.
#
# Scope: every `*.sh`, `*.just` and `justfile` on disk, tracked or not, by the
# listing the precommit sentinel hashes, less this file, whose fixture holds the
# forms it refuses.
#
# Residual bound: only a `$(mktemp ...)` command substitution is read, on one
# line. A backticked call, or one whose output goes to a file, is not seen.
#
# Usage: bash tests/mktemp-template-test.sh   (run from repo root)
set -euo pipefail

# See tests/citation-test.sh for why a leaked hook environment is unset.
# shellcheck disable=SC2046  # word-splitting is the point: a var-name list
unset $(git rev-parse --local-env-vars)

unset CDPATH # else `cd` may echo its target into the $(cd … && pwd) capture below
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

failures=0
fail() {
    printf 'FAIL: %s\n' "$1" >&2
    failures=$((failures + 1))
}

main() {
    echo "=== mktemp-template (the scan refuses what it should, and only that) ==="
    check_fixture
    echo "=== mktemp-template (no call in this repo lacks a template) ==="
    check_tree

    if [ "$failures" -gt 0 ]; then
        printf '\n%s failure(s)\n' "$failures" >&2
        exit 1
    fi
    printf '\nmktemp-template ok (fixture forms, %s files scanned)\n' "$scanned"
}

# Prints `<file>:<line>:<text>` for each line holding a call with no template, or
# whose Xs are not the template's end.
bare_mktemp_lines() {
    awk '
        /^[[:space:]]*#/ { next }
        {
            rest = $0
            while (match(rest, /\$\( *mktemp( [^)]*)?(\)|$)/)) {
                call = substr(rest, RSTART, RLENGTH)
                if (call !~ /XXXXXX["'\'']?([ )]|$)/) {
                    print FILENAME ":" FNR ":" $0
                    break
                }
                rest = substr(rest, RSTART + RLENGTH)
            }
        }
    ' "$1"
}

check_fixture() {
    local dir bad good out
    dir="$(mktemp -d "${TMPDIR:-/tmp}/mktemp-template.XXXXXX")"
    # shellcheck disable=SC2064  # $dir is meant to expand now
    trap "rm -rf '$dir'" EXIT

    bad="$dir/bad.sh"
    cat >"$bad" <<'EOF'
a=$(mktemp)
b="$(mktemp -d)"
c=$(mktemp -t name)
d="$(cd "$(mktemp -d)" && pwd -P)"
e=$(mktemp -d "$TMPDIR/name.XXXXXX.d")
f=$(mktemp "$TMPDIR/name.XXXXXX"); g=$(mktemp)
EOF
    out="$(bare_mktemp_lines "$bad")"
    if [ "$(wc -l <"$bad")" -ne "$(printf '%s\n' "$out" | wc -l)" ]; then
        fail "a bare form went unrefused; refused only:"
        printf '%s\n' "$out" >&2
    fi

    good="$dir/good.sh"
    cat >"$good" <<'EOF'
a=$(mktemp "${TMPDIR:-/tmp}/name.XXXXXX")
b="$(mktemp -d "${TMPDIR:-/tmp}/name.XXXXXX")"
c="$(cd "$(mktemp -d "$TMPDIR/name.XXXXXX")" && pwd -P)"
d=$(mktemp "$dir/.name.XXXXXX" 2>&1)
# mktemp creates 0600, and $(mktemp) in a comment is not a call
for t in git mktemp tar; do :; done
EOF
    out="$(bare_mktemp_lines "$good")"
    if [ -n "$out" ]; then
        fail "a templated form was refused:"
        printf '%s\n' "$out" >&2
    fi
}

check_tree() {
    local f hits
    scanned=0
    while IFS= read -r -d '' f; do
        case "$f" in
            tests/mktemp-template-test.sh) continue ;;
            justfile | */justfile | *.just | *.sh) ;;
            *) continue ;;
        esac
        [ -f "$f" ] || continue
        scanned=$((scanned + 1))
        hits="$(bare_mktemp_lines "$f")"
        if [ -n "$hits" ]; then
            fail "mktemp with no template; use mktemp [-d] \"\${TMPDIR:-/tmp}/<name>.XXXXXX\":"
            printf '%s\n' "$hits" >&2
        fi
    done < <(git ls-files -z -co --exclude-standard)
    # A scan that found no files would pass while checking nothing.
    if [ "$scanned" -eq 0 ]; then
        fail "the scan read no files"
    fi
}

main "$@"
