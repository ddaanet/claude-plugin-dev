#!/usr/bin/env bash
# Refuses a `<name>.sh:<digits>`, `<name>.just:<digits>` or `justfile:<digits>`
# citation into a tracked source file. Citing a script by line number rots the
# moment either file is next edited: the number keeps parsing, and a reader who
# follows it lands on different real code with no error raised. The
# convention this check enforces -- cite the enclosing symbol plus a short
# quoted fragment instead -- lives only in the failure message below; there is
# no CLAUDE.md Conventions bullet, because a bullet duplicating a rule proposed
# upstream (see the brief filed against edify) would rot silently the day
# upstream ships its own version, while a check cannot become a stale
# duplicate.
#
# Scope, and why: over `git ls-files -z`, excluding `plans/` and
# `docs/changelog/` -- this repo's dated write-time records, which this
# convention does not bind, per the design-and-changelog split in CLAUDE.md.
#
# Residual bound: a citation INTO a `.md` file (e.g. an executed outline) is
# not one of the three forbidden target forms and is never flagged, because an
# extension alone cannot tell a living document from a frozen dated one --
# tests/version-guard-test.sh's own citation of the executed outline by line
# number is correct forever and is meant to stay exactly as it is.
#
# Usage: bash tests/citation-test.sh   (run from repo root)
set -euo pipefail

# When run as this repo's own pre-commit hook, the enclosing `git commit`
# leaks GIT_DIR/GIT_INDEX_FILE/etc. into this process's environment. The
# self-fixture below runs real git commands of its own (`init`, `add`,
# `commit`), and a leaked GIT_DIR would redirect them at this repo instead.
# See `tests/release-test.sh`'s own header comment, just above its own
# `unset $(git rev-parse --local-env-vars)` line, for the same explanation.
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
assert_contains() {
    # $1=haystack $2=needle $3=label
    if ! printf '%s' "$1" | grep -q -- "$2"; then
        fail "$3: output did not contain '$2'"
        printf '  --- output ---\n%s\n  --------------\n' "$1" >&2
    fi
}
assert_not_contains() {
    # $1=haystack $2=needle $3=label
    if printf '%s' "$1" | grep -q -- "$2"; then
        fail "$3: output contained '$2'"
        printf '  --- output ---\n%s\n  --------------\n' "$1" >&2
    fi
}

# The three forbidden target forms, as a regex -- never written out as a
# literal matching instance anywhere in this file. This file is itself a
# tracked file the check below walks, so a literal sample here would flag
# itself; every sample used below is assembled with printf at runtime
# instead, so the matching text exists only in a fixture's generated content,
# never in this source.
citation_pattern='([[:alnum:]_./-]+\.(sh|just)|justfile):[0-9]+'

# Walks $1 (a git worktree root) over `git ls-files -z` -- NUL-delimited, so a
# path holding whitespace is still one path -- excluding plans/ and
# docs/changelog/, and reports every line in a tracked file matching
# $citation_pattern. Prints one block per hit, exits non-zero iff any hit was
# found. Residual: a matched line itself containing an embedded NUL would
# still mis-split; no tracked file in this repo does, and NUL-delimiting the
# per-file walk is the bound every suite here states rather than claiming
# full coverage.
check_citations() {
    local root="$1" rel f hits=0 lineno rest
    while IFS= read -r -d '' rel; do
        case "$rel" in
        plans/* | docs/changelog/*) continue ;;
        esac
        f="$root/$rel"
        [ -f "$f" ] || continue
        while IFS=: read -r lineno rest; do
            [ -n "${lineno:-}" ] || continue
            hits=$((hits + 1))
            printf 'citation-not-allowed: %s:%s\n' "$rel" "$lineno"
            printf '  found: %s\n' "$rest"
            printf '  convention: cite the enclosing symbol plus a short quoted fragment of\n'
            printf '    the cited line, not a line number -- e.g. "release.sh, the mode\n'
            printf '    dispatch in main, the --resume branch". A line number rots silently\n'
            printf '    the moment either file is next edited, landing a reader on different\n'
            printf '    real code with no error raised. Frozen dated artifacts under plans/\n'
            printf '    and docs/changelog/ are exempt; a target in a .md file is not one of\n'
            printf '    the forbidden forms, since an extension alone cannot tell a living\n'
            printf '    document from a frozen one.\n'
        done < <(grep -noE "$citation_pattern" -- "$f" 2>/dev/null || true)
    done < <(git -C "$root" ls-files -z)
    [ "$hits" -eq 0 ]
}

echo "=== citation gate: self-fixture discriminates tracked from plans/ ==="
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
git -C "$fixture" init -q
git -C "$fixture" config user.email "citation-test@example.com"
git -C "$fixture" config user.name "citation-test"
# Assembled at runtime -- see the note on $citation_pattern above.
probe_name="probe"
probe_ext="sh"
probe_line="7"
mkdir -p "$fixture/plans"
printf '#!/usr/bin/env bash\n# see %s.%s:%s for the mechanism\n' \
    "$probe_name" "$probe_ext" "$probe_line" >"$fixture/tracked.sh"
printf '#!/usr/bin/env bash\n# see %s.%s:%s for the mechanism\n' \
    "$probe_name" "$probe_ext" "$probe_line" >"$fixture/plans/tracked.sh"
git -C "$fixture" add tracked.sh plans/tracked.sh
git -C "$fixture" commit -q -m fixture

fixture_out="$(check_citations "$fixture")" && fixture_rc=0 || fixture_rc=$?
# Built at runtime, same reason as $citation_pattern above: "tracked.<ext>:2"
# written out literally here would itself be a citation-shaped string in this
# tracked file.
expected_hit="citation-not-allowed: tracked.${probe_ext}:2"
assert_contains "$fixture_out" "$expected_hit" \
    "self-fixture: reports the tracked planted citation"
assert_not_contains "$fixture_out" "plans/tracked.sh" \
    "self-fixture: does not report the plans/-excluded planted citation"
[ "$fixture_rc" -ne 0 ] || fail "self-fixture: check_citations exited 0 with a planted citation present"

echo "=== citation gate: this repo ==="
repo_out="$(check_citations "$repo_root")" && repo_rc=0 || repo_rc=$?
if [ "$repo_rc" -ne 0 ]; then
    printf '%s\n' "$repo_out" >&2
    fail "citation gate: the citation(s) above must be converted to enclosing-symbol form"
fi

if [ "$failures" -ne 0 ]; then
    printf '\n%d citation assertion(s) failed\n' "$failures" >&2
    exit 1
fi
echo
echo "citations ok (self-fixture discriminates tracked from plans/, no <script>.sh:<line> citation in tracked files outside plans/ and docs/changelog/)"
