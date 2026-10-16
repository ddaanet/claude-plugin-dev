#!/usr/bin/env bash
# The 400-line cap over every tracked file. The cap bounds what a reader takes
# in at one go, so it binds a test suite and a script as it binds a document;
# an oversized suite is split along its scenario groups, not exempted.
#
# Scope, and why this is not part of docs-test.sh: that suite owns the cap over
# the markdown under `docs/`, where it also counts untracked drafts. This one
# owns every other tracked file. It skips what docs-test.sh already governs (a
# `.md` under `docs/`) and `docs/changelog/` wholesale, which holds dated
# records that are never revised. It also skips `plans/` wholesale, any file
# type: the cap is soft for plans, judged at review and gated by neither suite,
# because a warning would repeat on every gate run for a plan that is frozen
# once it lands. A non-markdown file under `docs/` is not governed by
# docs-test.sh, so it is counted here.
#
# Also skipped, because a line count says nothing about them: a gitlink (the
# `memory` submodule is another repo's content), a symlink, a binary file (the
# count is of text lines) and a file listed in the `exempt` array below, which
# is empty and takes an entry only with a stated reason.
#
# The scan runs first against a fixture repo, so the report format and each
# exclusion are pinned by an assertion that goes red when the scan stops
# honouring it; then against this repo.
#
# Usage: bash tests/line-cap-test.sh   (run from repo root)
set -euo pipefail

# When run as this repo's own pre-commit hook, the enclosing `git commit`
# leaks GIT_DIR/GIT_INDEX_FILE/etc. into this process's environment. The
# fixture below runs real git commands of its own (`init`, `add`), and a
# leaked GIT_DIR would redirect them at this repo instead.
# shellcheck disable=SC2046  # word-splitting is the point: a var-name list
unset $(git rev-parse --local-env-vars)

unset CDPATH   # else `cd` may echo its target into the $(cd … && pwd) capture below
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

max_lines=400

failures=0
fail() {
    printf 'FAIL: %s\n' "$1" >&2
    failures=$((failures + 1))
}
assert_eq() {
    # $1=actual $2=expected $3=label
    if [[ "$1" != "$2" ]]; then
        fail "$3: expected '$2', got '$1'"
    fi
}

sandboxes=()
cleanup() {
    local s
    for s in "${sandboxes[@]:-}"; do
        [ -n "$s" ] && rm -rf "$s"
    done
}
trap cleanup EXIT

passed=()

echo "=== the scan reports each oversized file in the fixture, and only those ==="
sandbox="$(mktemp -d)"
sandboxes+=("$sandbox")
fixture="$sandbox/fixture repo"
mkdir -p "$fixture/docs/changelog" "$fixture/plans" "$fixture/tests"
git init -q "$fixture"
lines() {
    # $1=count. That many text lines on stdout.
    local i
    for ((i = 1; i <= $1; i++)); do printf 'line %d\n' "$i"; done
}
lines 400 > "$fixture/tests/at-cap.sh"
lines 401 > "$fixture/tests/over-cap.sh"
lines 401 > "$fixture/my big file.txt"
lines 401 > "$fixture/plans/data.json"
lines 401 > "$fixture/docs/changelog/2026-01-01-record.md"
lines 401 > "$fixture/docs/node.md"
lines 401 > "$fixture/plans/plan.md"
lines 401 > "$fixture/untracked.sh"
{ lines 401; printf '\0'; } > "$fixture/blob.bin"
# A symlink to a file within the cap; the link itself has no lines to count.
ln -s tests/at-cap.sh "$fixture/link.txt"
git -C "$fixture" add -A -f -- . ':!untracked.sh'
git -C "$fixture" update-index --add --cacheinfo \
    "160000,1111111111111111111111111111111111111111,memory"
# scan <root>: one `oversized-file: <path>: <n> lines > <cap>` line per
# tracked file over the cap. NUL-delimited end to end, so a path holding a
# space or a newline is one path.
scan() {
    local root="$1" record meta mode path n
    while IFS= read -r -d '' record; do
        meta="${record%%$'\t'*}"
        path="${record#*$'\t'}"
        mode="${meta%% *}"
        case "$mode" in 160000 | 120000) continue ;; esac
        case "$path" in
            docs/changelog/*) continue ;;
            plans/*) continue ;;
            docs/*.md) continue ;;
        esac
        is_exempt "$path" && continue
        [ -f "$root/$path" ] || continue
        # grep -I counts 0 matching lines in a binary file, so one is skipped.
        n="$(grep -Ic '' -- "$root/$path" || true)"
        if [ "$n" -gt "$max_lines" ]; then
            printf 'oversized-file: %s: %s lines > %s\n' "$path" "$n" "$max_lines"
        fi
    done < <(git -C "$root" ls-files -z -s)
}

# exempt: tracked files left over the cap on purpose, one per line as
# "path|reason". A reason is mandatory; an entry without one is a defect.
# Empty today: every tracked file outside the governed docs is under the cap.
exempt=()

is_exempt() {
    local entry
    for entry in ${exempt[@]+"${exempt[@]}"}; do
        [ "${entry%%|*}" = "$1" ] && return 0
    done
    return 1
}

got="$(scan "$fixture")"
assert_eq "$got" "oversized-file: my big file.txt: 401 lines > 400
oversized-file: tests/over-cap.sh: 401 lines > 400" \
    "fixture report: the two non-governed oversized files, in git's order, no others"
passed+=("report format and each exclusion pinned on a fixture")

echo "=== no tracked file in this repo exceeds the cap ==="
real="$(scan "$repo_root")"
if [ -n "$real" ]; then
    printf '%s\n' "$real" >&2
    echo "  split the file along its scenario groups or seams, not by cramming lines" >&2
    fail "tracked files over the $max_lines-line cap"
fi
passed+=("every tracked file outside the governed docs is within $max_lines lines")

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nline-cap ok:\n'
printf '  - %s\n' "${passed[@]}"
