#!/usr/bin/env bash
# Hygiene over `docs/` and `plans/`: the line cap, and the pointers the split
# design doc depends on.
#
# The cap is 400 lines, and it only means anything because `just format-docs`
# hard-wraps these paths at 80 columns first: without the wrap a file stays
# under the cap by cramming paragraphs onto 300-character lines, which is worse
# to read than the overage. Wrapped, 400 lines is a node a session can read in
# one go.
#
# `docs/design.md` is the hub and carries a one-line conclusion per decision;
# the argument lives in a node under `docs/references/`. That shape is only
# safe while the pointers resolve — a stub whose node has moved strands the
# argument silently, and the next reader re-litigates a settled decision.
# Only existence is checked here, not the graph's semantics: this is
# deliberately a smaller check than gitlore's `scripts/check-docs-links.py`,
# whose nine checks assume a `D<n>` decision numbering this repo does not use.
set -euo pipefail
unset CDPATH
cd "$(dirname "$0")/.."

max_lines=400
status=0

# Every tracked markdown file under the paths `format-docs` wraps. NUL-
# delimited, so a path containing whitespace is one path.
md_files() {
    git ls-files -z -- docs plans | while IFS= read -r -d '' f; do
        case "$f" in *.md) printf '%s\0' "$f" ;; esac
    done
}

echo "=== docs: no file exceeds the $max_lines-line cap ==="
while IFS= read -r -d '' f; do
    n=$(wc -l < "$f")
    [ "$n" -gt "$max_lines" ] || continue
    # `<!-- cap-ok -->` exempts a file whose overage is deliberate. It is for
    # a plan that already landed: splitting one retroactively churns a record
    # nobody is going to read again, and the cap exists to bound what a
    # session must read *before* working. A living doc does not get the
    # marker -- it gets split.
    if grep -q '<!-- cap-ok' "$f"; then
        echo "  exempt (cap-ok): $f, $n lines"
        continue
    fi
    echo "oversized-file: $f is $n lines (cap $max_lines)" >&2
    echo "  split it on a need-time seam, or move an argument into a node" >&2
    status=1
done < <(md_files)

echo "=== docs: every relative pointer resolves ==="
while IFS= read -r -d '' f; do
    dir=$(dirname "$f")
    # Fenced blocks are skipped: a link inside an example is not a pointer.
    # `grep -o` yields one `](target)` per line, so a line with two links is
    # fully covered.
    while IFS= read -r target; do
        case "$target" in
            ''|http://*|https://*|mailto:*|'#'*) continue ;;
        esac
        # An anchor on a real file is still that file; a bare anchor was
        # skipped above.
        target=${target%%#*}
        [ -n "$target" ] || continue
        [ -e "$dir/$target" ] || {
            echo "broken-link: $f -> $target" >&2
            status=1
        }
    done < <(
        awk '/^```/ { fence = !fence; next } !fence' "$f" \
            | grep -oE '\]\([^)]+\)' \
            | sed -e 's/^](//' -e 's/)$//'
    )
done < <(md_files)

[ "$status" -eq 0 ] || exit 1
echo
echo "docs ok (cap $max_lines lines, pointers resolve)"
