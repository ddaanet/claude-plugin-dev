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
# exit status is the script's.
sync_copy() {
    local root
    root="$(root_dir)"
    # Not local: the EXIT trap reads it after sync_copy has returned.
    excludes="$(mktemp "${TMPDIR:-/tmp}/dogfood.XXXXXX")"
    trap 'rm -f "$excludes"' EXIT
    git -C "$root" ls-files -z -o -i --exclude-standard --directory |
        while IFS= read -r -d '' entry; do
            printf '/%s\0' "$entry"
        done >"$excludes"
    printf '%s\0' '.git' '/dist/plugin/' >>"$excludes"
    mkdir -p "$root/dist/plugin"
    rsync -a --delete --delete-excluded --from0 --exclude-from=- \
        "$root/" "$root/dist/plugin/" <"$excludes"
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
