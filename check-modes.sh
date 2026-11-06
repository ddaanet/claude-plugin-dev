#!/usr/bin/env bash
# check-modes: every file git does not ignore under the directory this script
# lives in, read from disk, that starts with `#!` must carry the execute bit.
# Consumer recipes call vendored scripts as `bash <script>`, so a file flipped
# to 644 passes every gate while `bin/claude` silently leaves PATH. The rule is
# by content, not a list, so a new vendored script is covered without an edit.
# Residual bound: a path holding a newline is reported as split lines.
#
# Usage: bash <dir>/check-modes.sh   (no arguments, from anywhere in the tree)
# Exit 0 prints one sign-off line on stdout. Exit 1 prints one `mode-lost:`
# stderr line per file, then a `chmod +x` line and a commit line.

unset CDPATH

main() {
    export LC_ALL=C
    locate
    scan
    judge
}

# locate: the script's own directory, absolute, and the work tree holding it.
locate() {
    if ! self_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)"; then
        fail_run "cannot resolve the script's directory"
    fi
    if ! root="$(git -C "$self_dir" rev-parse --show-toplevel 2>/dev/null)"; then
        fail_run "not inside a git work tree"
    fi
    case $self_dir in
        "$root") prefix="" ;;
        "$root"/*) prefix=${self_dir#"$root"/} ;;
        *) fail_run "$self_dir is outside its work tree $root" ;;
    esac
}

# scan: list the directory from disk (tracked and untracked, ignored left out),
# NUL-delimited, and count the #! files and the ones without the execute bit.
# The listing goes to a temporary file so git's exit status is seen and the
# loop runs in this shell, where its counters survive.
scan() {
    local rel full magic
    checked=0
    lost=()
    tmp="$(mktemp "${TMPDIR:-/tmp}/check-modes.XXXXXX")" || fail_run "cannot create a temporary file"
    if [ -n "$prefix" ]; then
        git -C "$root" ls-files -z -co --exclude-standard -- ":(literal)$prefix" >"$tmp" \
            || fail_run "git ls-files exited with an error"
    else
        git -C "$root" ls-files -z -co --exclude-standard >"$tmp" \
            || fail_run "git ls-files exited with an error"
    fi
    while IFS= read -r -d '' rel; do
        full="$root/$rel"
        if [ ! -f "$full" ] || [ -L "$full" ]; then
            continue
        fi
        magic="$(head -c 2 -- "$full")" || fail_run "cannot read $rel"
        if [ "$magic" != '#!' ]; then
            continue
        fi
        checked=$((checked + 1))
        if [ ! -x "$full" ]; then
            lost+=("$rel")
        fi
    done <"$tmp"
    rm -f "$tmp"
    tmp=""
}

# judge: the sign-off on success; otherwise one line per file, then the hint.
judge() {
    local p hint=""
    if [ "${#lost[@]}" -eq 0 ]; then
        printf 'check-modes: %s #! files checked, all executable\n' "$checked"
        exit 0
    fi
    for p in "${lost[@]}"; do
        printf 'mode-lost: %s\n' "$p" >&2
        quote_path "$p"
        hint+=" $REPLY"
    done
    printf 'chmod +x%s\n' "$hint" >&2
    printf '%s\n' 'then commit the mode change' >&2
    exit 1
}

# quote_path <path>: the path single-quoted for sh, into REPLY. Each ' in the
# path closes the quote, writes an escaped quote and reopens it.
quote_path() {
    local rest=$1 out="" pre
    while [[ $rest == *\'* ]]; do
        pre=${rest%%\'*}
        out+="$pre'\\''"
        rest=${rest#*\'}
    done
    REPLY="'$out$rest'"
}

# fail_run <reason>: the one-line failure of the whole run.
fail_run() {
    if [ -n "${tmp:-}" ]; then
        rm -f "$tmp"
    fi
    printf 'check-modes: %s\n' "$1" >&2
    exit 1
}

main "$@"
