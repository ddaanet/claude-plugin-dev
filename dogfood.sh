#!/usr/bin/env bash
# Dogfood launcher for a plugin that vendors this toolkit. Vendored at
# <root>/plugin-dev/dogfood.sh; <root> is always found from the script's own
# location, never from CLAUDE_PROJECT_DIR or a hook payload's cwd (a resumed
# session can carry a foreign one).
#
#   sync   mirror the plugin tree into <root>/dist/plugin/
set -euo pipefail
unset CDPATH # else cd prints its target into a $(cd … && pwd -P) capture

main() {
    case "${1:-}" in
        sync) sync_copy ;;
        *) usage ;;
    esac
}

usage() {
    echo "usage: dogfood.sh sync|pre-tool|session-start" >&2
    exit 2
}

# The copy is the source tree minus what git ignores, minus .git, minus the
# copy itself. rsync gets the ignored paths as an exclude list, each anchored
# with a leading slash and NUL-separated, so a name holding a space or a
# newline survives. The list is written out in full before rsync starts: fed
# through a pipe, a git failure would leave rsync running on a partial list,
# copying .git and recursing into the copy. Deletions propagate: a path that
# stops being source leaves the copy. rsync's stderr is left alone, and its
# exit status is the script's. An entry holding * ? [ ] or a backslash aborts
# the sync before rsync runs or dist/ is touched: rsync reads the first four as
# wildcards and a backslash as an escape only when a wildcard is present, so
# such names are refused rather than escaped. The exit leaves only the loop's
# subshell; errexit ends the script on the pipeline's status, which is the
# loop's 1 even when git dies of SIGPIPE (pipefail reports the rightmost).
# Before anything else touches the tree, sync refuses a root with no plugin
# manifest and a root where git does not ignore dist/plugin/; each refusal is
# one dogfood: line naming the path, exit 1, dist/ untouched.
sync_copy() {
    local root
    root="$(root_dir)"
    require_manifest "$root"
    require_ignored_copy "$root"
    # Not local: the EXIT trap reads it after sync_copy has returned.
    excludes="$(mktemp "${TMPDIR:-/tmp}/dogfood.XXXXXX")"
    trap 'rm -f "$excludes"' EXIT
    git -C "$root" ls-files -z -o -i --exclude-standard --directory |
        while IFS= read -r -d '' entry; do
            case "$entry" in
                *'*'* | *'?'* | *'['* | *']'* | *\\*)
                    printf "dogfood: ignored entry '%s' holds a pattern character (* ? [ ] or \\\\); sync refused\n" "$entry" >&2
                    exit 1
                    ;;
            esac
            printf '/%s\0' "$entry"
        done >"$excludes"
    printf '%s\0' '.git' '/dist/plugin/' >>"$excludes"
    mkdir -p "$root/dist/plugin"
    rsync -a --delete --delete-excluded --from0 --exclude-from=- \
        "$root/" "$root/dist/plugin/" <"$excludes"
}

require_manifest() {
    if [[ ! -f "$1/.claude-plugin/plugin.json" ]]; then
        printf 'dogfood: %s/.claude-plugin/plugin.json not found; sync refused\n' "$1" >&2
        exit 1
    fi
}

# The trailing slash matters: a first sync has no dist/plugin yet, and git
# check-ignore on the bare name misses a /dist/plugin/ pattern. check-ignore
# exits 1 for "not ignored" and 128 for a git error; only the 1 is a refusal,
# a git error stops the script with git's own stderr.
require_ignored_copy() {
    local status=0
    git -C "$1" check-ignore -q dist/plugin/ || status=$?
    case "$status" in
        0) ;;
        1)
            printf 'dogfood: %s/dist/plugin/ is not git-ignored; sync refused\n' "$1" >&2
            exit 1
            ;;
        *) exit "$status" ;;
    esac
}

# root_dir: the physical parent of this script's directory. Runs inside $(),
# where errexit is off, so each step is chained: a failed cd must fail the
# call, not fall through to the parent of an empty path, which is /.
root_dir() {
    local here
    here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" &&
        (cd "$here/.." && pwd -P)
}

main "$@"
