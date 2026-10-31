#!/usr/bin/env bash
# Survey for the line-cap redesign: one TSV row per text file in a repo, over
# the set tests/line-cap-test.sh selects (every file on disk git does not
# ignore, tracked or not; symlinks, gitlinks, binary and empty files skipped),
# plus the paths that scan leaves out, tagged in the `scope` column instead of
# dropped. A consumer's vendored `plugin-dev/` is left out entirely: it is this
# repo's files again.
#
# Columns: repo, path, type, scope, lines, bytes, nonws, words, maxlen.
#   lines  grep -Ic '' — the count the current scan compares against the cap
#   nonws  characters (codepoints, C.UTF-8) left once every whitespace byte is
#          deleted: indentation, padding and line breaks cost nothing
#   maxlen the longest line, in characters
#
# Usage: measure.sh <repo-dir>   (TSV on stdout, header first)
set -euo pipefail

main() {
    local root repo path file lines scope
    root="$(cd "$1" && pwd)"
    repo="$(basename "$root")"
    export LC_ALL=C.UTF-8

    printf 'repo\tpath\ttype\tscope\tlines\tbytes\tnonws\twords\tmaxlen\n'
    while IFS= read -r -d '' path; do
        file="$root/$path"
        [ -L "$file" ] && continue
        [ -f "$file" ] || continue
        case "$path" in plugin-dev/*) continue ;; esac
        lines="$(grep -Ic '' -- "$file" || true)"
        [ "$lines" -gt 0 ] || continue
        case "$path" in
            docs/changelog/*) scope=changelog ;;
            plans/*) scope=plans ;;
            docs/*.md) scope=docs-md ;;
            *) scope=gated ;;
        esac
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$repo" "$path" \
            "$(file_type "$file" "$path")" "$scope" "$lines" \
            "$(wc -c < "$file")" "$(tr -d '[:space:]' < "$file" | wc -m)" \
            "$(wc -w < "$file")" "$(wc -L < "$file")"
done < <(git -C "$root" ls-files -z --cached --others --exclude-standard | sort -z)
}

file_type() {
    # $1=file $2=path. The extension, or for an extensionless file the
    # interpreter its shebang names; `justfile` and `*.just` are `just`.
    local base="${2##*/}" first
    case "$base" in
        justfile | *.just) echo just; return ;;
        *.*) echo "${base##*.}"; return ;;
    esac
    IFS= read -r first < "$1" || true
    case "$first" in
        '#!'*bash* | '#!'*/sh | '#!'*' sh') echo sh ;;
        '#!'*python*) echo py ;;
        *) echo none ;;
    esac
}

main "$@"
