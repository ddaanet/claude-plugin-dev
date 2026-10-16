#!/usr/bin/env bash
# Hygiene over `docs/` and `plans/`: the line cap over `docs/`, and the
# pointers the split design doc depends on, over both.
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

# Every markdown file under the paths `format-docs` wraps, untracked ones
# included (`-co`): a draft has to fail the cap while it is being written,
# not on the commit that tracks it. NUL-delimited, so a path containing
# whitespace is one path.
md_files() {
    git ls-files -z -co --exclude-standard -- docs plans | while IFS= read -r -d '' f; do
        case "$f" in *.md) printf '%s\0' "$f" ;; esac
    done
}

# The same list narrowed to `docs/`, the only tree the cap counts.
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
echo "docs ok (cap $max_lines lines over docs/, pointers resolve over docs/ and plans/)"
