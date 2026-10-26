#!/usr/bin/env bash
# Hygiene over `docs/`: the 400-line cap.
#
# The cap is 400 lines, and it only means anything because `just format-docs`
# hard-wraps these paths at 80 columns first: without the wrap a file stays
# under the cap by cramming paragraphs onto 300-character lines, which is worse
# to read than the overage. Wrapped, 400 lines is a node a session can read in
# one go. It is hard for the design docs under `docs/`, `docs/changelog/`
# included. `plans/` is out of the count: the cap is soft there, judged at
# review, and a warning would repeat on every gate run for a plan that is
# frozen once it lands. A living doc that outgrows the cap is split, never
# marked.
#
# Whether a link resolves is `toolkit/check-refs.sh`'s check, over every
# Markdown file, with `plans/` and `docs/changelog/` exempt on purpose: dated
# records are never revised, so a link in one to a file deleted later stays true
# of its day. This suite reads no link.
set -euo pipefail
unset CDPATH
cd "$(dirname "$0")/.."

max_lines=400
status=0

# Every markdown file under `docs/`, untracked ones included (`-co`): a draft has
# to fail the cap while it is being written, not on the commit that tracks it.
# NUL-delimited, so a path containing whitespace is one path.
docs_md_files() {
    git ls-files -z -co --exclude-standard -- docs | while IFS= read -r -d '' f; do
        case "$f" in *.md) printf '%s\0' "$f" ;; esac
    done
}

echo "=== docs: no file under docs/ exceeds the $max_lines-line cap ==="
while IFS= read -r -d '' f; do
    n=$(wc -l < "$f")
    [ "$n" -gt "$max_lines" ] || continue
    echo "oversized-file: $f is $n lines (cap $max_lines)" >&2
    echo "  split it on a need-time seam, or move an argument into a node" >&2
    status=1
done < <(docs_md_files)

[ "$status" -eq 0 ] || exit 1
echo
echo "docs ok (cap $max_lines lines over docs/)"
