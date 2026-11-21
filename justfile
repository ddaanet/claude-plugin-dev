# claude-plugin-dev — toolkit dev recipes.

# The toolkit's own gate sentinels, imported from the source tree rather than a
# vendored copy, so `precommit` dogfoods the file it ships.
import 'toolkit/gates.just'

# The tools `precommit`'s verdict depends on that no input file pins: a new
# shellcheck can find new problems, and every suite runs under bash, git, jq and
# just. rumdl is pinned in pyproject.toml, an input, but the binary that runs is
# whatever `format-docs` finds, so its version is hashed too, resolved the same
# way. The venv's PyYAML is hashed likewise: the frontmatter suites parse with it.
export PLUGIN_DEV_GATE_TOOLS := "bash --version\ngit --version\njust --version\njq --version\nshellcheck --version\n{ command -v rumdl >/dev/null 2>&1 && rumdl --version; } || .venv/bin/rumdl --version\n.venv/bin/python3 -I -c 'import yaml; print(yaml.__version__)'"

_default:
    @just --list

# Run all syntax + style checks and every suite, skipped while no input changed.
precommit:
    #!{{ plugin_dev_gate_prolog }}
    # The inputs are every non-ignored file, since the checks read essentially
    # all of them (citation, doc-sync, check-refs, check-size, check-modes), all from disk.
    # `memory` is excluded because it is a submodule gitlink, which hashes by
    # name only: no edit inside it would move the hash. No check here reads it.
    sentinel-guard precommit :/ ':(top,exclude)memory'
    # The formatters run after the guard, so a cached run skips them, and
    # before the re-hash, so the pass records the tree they leave.
    just whitespace
    just format-docs
    hash-sentinel
    shellcheck -x toolkit/*.sh toolkit/bin/claude scripts/*.sh
    bash toolkit/check-refs.sh --shipped toolkit
    bash toolkit/check-size.sh
    bash toolkit/check-modes.sh
    # Every suite under tests/ is syntax-checked and run by glob, so a suite
    # added there is gated without a second list to edit. `bash -n` takes one
    # script, hence the loop.
    for t in tests/*-test.sh; do
        bash -n "$t"
    done
    just _import-check
    for t in tests/*-test.sh; do
        bash "$t"
    done
    echo ok
    record-sentinel

# Checks that run before a release. Add slow or paid checks here.
prerelease: precommit

# quote() and not a double-quoted interpolation: just substitutes the argument
# as raw text before bash parses the line, so shell quotes around it do not stop
# a caller's $(...) from running.
# Cut a toolkit release: bump VERSION, commit, tag, push, GitHub release.
release bump='patch': prerelease
    bash scripts/self-release.sh {{ quote(bump) }}

# Deliberately depends on no gate: a release that half-landed must be
# completable without re-running a prerelease that already passed. Same
# contract release.just gives consumers, and _import-check pins it there.
# Finish a toolkit release that landed partially. Idempotent; runs no gate.
resume-release:
    bash scripts/self-release.sh --resume

# List sibling repos whose vendored plugin-dev is older than toolkit/VERSION.
outdated-consumers:
    #!/usr/bin/env bash
    set -euo pipefail
    current=$(cat toolkit/VERSION)
    found=0
    for version_file in ../*/plugin-dev/VERSION; do
        [ -f "$version_file" ] || continue
        repo=${version_file%/plugin-dev/VERSION}
        vendored=$(cat "$version_file")
        [ "$vendored" = "$current" ] && continue
        newest=$(printf '%s\n%s\n' "$vendored" "$current" | sort -V | tail -n 1)
        [ "$newest" = "$current" ] || continue
        printf '%-20s %s\n' "${repo#../}" "$vendored"
        found=1
    done
    [ "$found" = 1 ] || echo "every sibling consumer is on $current"

# The index classification `whitespace` and `format-docs` share, interpolated
# at the top of each shebang recipe as gates.just does its prolog. A recipe
# sets `tmp` to a scratch directory, calls `index_open [pathspec...]`, then
# loops `while index_next; do ... done`. Each pass sets f, mode, oid, label and
# kind: unmerged, skip (gone, symlink, or not a regular file in the index),
# untracked, intent-to-add, unstaged (worktree differs from its index blob,
# mode included) or clean. The listing is read from three snapshots taken up
# front, so the loop's own `git add` cannot move what a later file reads, and
# an unchanged file costs no git process. Tracked entries come in index order
# and the `diff-files` records in the same order, so one pass joins them with
# no lookup table (bash 3.2 has no associative arrays). Every read is
# NUL-delimited.
[private]
index_prolog := "/usr/bin/env bash\nset -euo pipefail\n" + '''
empty=$(git hash-object --stdin < /dev/null)
index_open() {
    git ls-files -s -z -- "$@" > "$tmp/index"
    # diff-files reads the index unrefreshed, so it also lists a file whose
    # stat alone moved; with the mode unchanged, content settles it.
    git diff-files -z -- "$@" > "$tmp/diff"
    git ls-files -z --others --exclude-standard -- "$@" > "$tmp/others"
    exec 3< "$tmp/index" 4< "$tmp/diff" 5< "$tmp/others"
    index_prev=
    index_diff_next
}
# The next diff-files record: dmeta, then dpath, empty at the end.
index_diff_next() {
    dpath=
    IFS= read -r -d '' dmeta <&4 || return 0
    IFS= read -r -d '' dpath <&4 || dpath=
}
index_next() {
    local rec meta st dimode dwmode hit
    while :; do
        if IFS= read -r -d '' rec <&3; then
            meta=${rec%%$'\t'*}
            f=${rec#*$'\t'}
            read -r mode oid st <<<"$meta"
            # An unmerged path is listed once per stage, adjacently.
            [ "$f" != "$index_prev" ] || continue
            index_prev=$f
            hit=0
            if [ "$dpath" = "$f" ]; then
                hit=1
                read -r dimode dwmode _ <<<"$dmeta"
                while [ "$dpath" = "$f" ]; do index_diff_next; done
            fi
            label=
            # Read before the worktree, so an unmerged file that is gone
            # still fails the recipe. Writing a stage-0 entry would mark the
            # conflict resolved.
            if [ "$st" != 0 ]; then kind=unmerged; return 0; fi
            # Only a regular file, in the worktree and the index: a symlink's
            # blob is its target path, which a fix would rewrite, and a write
            # through it would land on another file.
            if [ ! -f "$f" ] || [ -L "$f" ]; then kind=skip; return 0; fi
            case "$mode" in 100644 | 100755) ;; *) kind=skip; return 0 ;; esac
            if [ "$oid" = "$empty" ]; then
                # Intent-to-add (`git add -N`): staging would add it whole.
                kind=intent-to-add label="intent-to-add, not staged"
            elif [ "$hit" = 1 ] && { [ "${dimode#:}" != "$dwmode" ] \
                || [ "$oid" != "$(git hash-object -- "$f")" ]; }; then
                # Unstaged edits: staging the file would put them in the commit.
                kind=unstaged label="unstaged edits, not staged"
            else
                # Worktree equal to index, so staging stages nothing but the fix.
                kind=clean
            fi
            return 0
        elif IFS= read -r -d '' f <&5; then
            mode= oid= label=
            if [ ! -f "$f" ] || [ -L "$f" ]; then
                kind=skip
            else
                kind=untracked label="untracked, not staged"
            fi
            return 0
        else
            return 1
        fi
    done
}
# restage_blob <recipe> <mode> <oid> <path> <command>...: run the command over
# the staged blob and, when it changed it, write the result to the index with
# the mode kept. The worktree file is the caller's.
restage_blob() {
    local recipe=$1 smode=$2 soid=$3 spath=$4 new
    shift 4
    git cat-file blob "$soid" > "$tmp/base"
    "$@" < "$tmp/base" > "$tmp/formatted"
    cmp -s "$tmp/base" "$tmp/formatted" && return 0
    new=$(git hash-object -w --stdin < "$tmp/formatted")
    git update-index --cacheinfo "$smode" "$new" "$spath"
    echo "$recipe: $spath (staged content)"
}
'''

# Apply git stripspace to text files on disk, tracked or not, and to their staged blobs.
whitespace:
    #!{{ index_prolog }}
    # From disk, not the index: the files the gate hashes and the checks read,
    # so a file added after a cached pass was fixed before it was hashed. A
    # file listed but gone from the worktree (a deletion not yet staged, or one
    # staged but left out of a `git commit -- <paths>`, whose hook sees HEAD's
    # index) is skipped, and so is an unmerged one, which then fails the recipe
    # once the rest is fixed: `sentinel-guard` refuses an unmerged tree before
    # this runs, so this is the net for a run outside the gate. Which fixes are
    # then staged, and how, depends on the file's index entry, as in
    # `format-docs`.
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/whitespace.XXXXXX")
    trap 'rm -rf "$tmp"' EXIT
    index_open
    unmerged=0
    while index_next; do
        case "$f" in justfile | *.sh | *.md | *.just) ;; *) continue ;; esac
        case "$kind" in
            unmerged)
                echo "whitespace: $f skipped (unmerged)"
                unmerged=1
                continue ;;
            skip) continue ;;
            unstaged)
                # The index takes the staged blob fixed on its own, mode kept.
                restage_blob whitespace "$mode" "$oid" "$f" git stripspace ;;
        esac
        git stripspace < "$f" > "$tmp/fixed"
        cmp -s "$f" "$tmp/fixed" && continue
        # Written through the file, not mv-ed over it: mktemp creates 0600
        # and mv would carry that mode across, so a whitespace-only pass
        # would also stage a mode change on any 755 script.
        cat "$tmp/fixed" > "$f"
        if [ -z "$label" ]; then
            git add -- "$f"
            echo "whitespace: $f"
        else
            echo "whitespace: $f ($label)"
        fi
    done
    if [ "$unmerged" = 1 ]; then
        echo "whitespace: unmerged paths left unfixed; resolve them and rerun" >&2
        exit 1
    fi

# Hard-wrap prose in every Markdown file at 80 columns, for an 80-column read.
format-docs:
    #!{{ index_prolog }}
    # The wrap is for an 80-column read, not for any count. rumdl comes from
    # uv.lock via `uv sync`, on PATH
    # through `.envrc`; the pin check turns a stale `.venv` into a message
    # rather than a differently wrapped tree.
    # PATH first, so an override or a system install wins; then the venv by
    # path, because a git hook runs `just precommit` without direnv having
    # exported anything. Not `uv run`, which would reach for ~/.cache/uv and
    # is blocked under a sandbox.
    bin={{ rumdl }}
    command -v "$bin" >/dev/null 2>&1 || bin="$PWD/.venv/bin/{{ rumdl }}"
    have=$("$bin" --version 2>/dev/null) || {
        echo "format-docs: rumdl not on PATH and no .venv — run 'uv sync'" >&2
        exit 1
    }
    want=$(sed -n 's/.*"rumdl==\([0-9.]*\)".*/\1/p' pyproject.toml)
    [ "$have" = "rumdl $want" ] || {
        echo "format-docs: $have at $bin, pyproject.toml pins $want — run 'uv sync'" >&2
        exit 1
    }
    # Every `.md` file on disk that git does not ignore, tracked or not: the
    # set the gate hashes. A file listed but gone from the worktree is skipped,
    # and so is an unmerged one, which then fails the recipe once the rest is
    # formatted: `sentinel-guard` refuses an unmerged tree before this runs, so
    # this is the net for a run outside the gate. Every
    # other file is formatted in place; which ones are then staged, and how,
    # depends on its index entry (`index_next`).
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/format-docs.XXXXXX")
    trap 'rm -rf "$tmp"' EXIT
    files=()
    stage=()
    split=()
    index_open '*.md'
    unmerged=0
    while index_next; do
        case "$kind" in
            unmerged)
                echo "format-docs: $f skipped (unmerged)"
                unmerged=1
                continue ;;
            skip) continue ;;
            unstaged)
                # The worktree is formatted in place, edits and all, unstaged;
                # the index takes the staged blob formatted on its own (below).
                split+=("$f:$mode:$oid") ;;
        esac
        files+=("$f")
        stage+=("$label")
    done
    before=()
    after=()
    # One hash-object call for the whole list, before and after the format.
    # `fmt` exits 0 with anything it cannot wrap left in place; `check --fix`
    # would exit 1 on the same tree and fail the gate over a long URL.
    if [ "${#files[@]}" -gt 0 ]; then
        while IFS= read -r h; do before+=("$h"); done < <(git hash-object -- "${files[@]}")
        "$bin" fmt --no-cache -- "${files[@]}"
        while IFS= read -r h; do after+=("$h"); done < <(git hash-object -- "${files[@]}")
    fi
    # Only a file whose content moved is reported and, when its worktree
    # matched its index (an empty label), staged, as `whitespace` does: from a
    # pre-commit hook the reflow would otherwise land unstaged beside a commit
    # of the unformatted text. Worktree equal to index there, so staging the
    # file stages nothing but the reflow.
    for i in "${!files[@]}"; do
        f=${files[$i]}
        [ "${after[$i]}" != "${before[$i]}" ] || continue
        if [ -z "${stage[$i]}" ]; then
            git add -- "$f"
            echo "format-docs: $f"
        else
            echo "format-docs: $f (${stage[$i]})"
        fi
    done
    # The staged blob of a file with unstaged edits is formatted through stdin
    # (rumdl reads the repo's config and path rules for --stdin-filename, so
    # no copy at a fake path is needed) and written to the index, mode kept.
    # Entries are path:mode:oid; mode and oid hold no colon, the path may.
    for e in "${split[@]+"${split[@]}"}"; do
        oid=${e##*:}; e=${e%:*}
        mode=${e##*:}; f=${e%:*}
        restage_blob format-docs "$mode" "$oid" "$f" \
            "$bin" fmt --no-cache --stdin --stdin-filename "$f" --silent
    done
    if [ "$unmerged" = 1 ]; then
        echo "format-docs: unmerged paths left unformatted; resolve them and rerun" >&2
        exit 1
    fi

# Overridable so a test can stand in a stub: `just rumdl=/path/to/stub format-docs`.
rumdl := "rumdl"

# Install .git/hooks/pre-commit to run just precommit. Idempotent.
install-hooks:
    #!/usr/bin/env bash
    set -euo pipefail
    hook=".git/hooks/pre-commit"
    cat > "$hook" <<'EOF'
    #!/bin/sh
    exec just precommit
    EOF
    chmod +x "$hook"
    echo "installed $hook"

# Import release.just into stub consumers to catch justfile syntax errors,
# and check that `release` reaches the consumer's gate through `prerelease`
# in both shapes: the plain `prerelease: precommit` and a widened one.
# --dry-run prints the resolved dependency chain without executing anything,
# so the destructive release body never runs. A third stub pins the contract
# from the other side: omitting `prerelease` must fail, and say so.
[private]
_import-check:
    #!/usr/bin/env bash
    set -euo pipefail
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/import-check.XXXXXX")
    trap 'rm -rf "$tmp"' EXIT

    stub() {
        mkdir "$tmp/$1"
        printf "import '%s/toolkit/release.just'\n\nprecommit:\n    @echo stub-precommit\n\nevals:\n    @echo stub-evals\n\n%b" \
            "$PWD" "$2" > "$tmp/$1/justfile"
    }

    check() {
        local name="$1" out
        just --justfile "$tmp/$name/justfile" --list >/dev/null
        out=$(just --justfile "$tmp/$name/justfile" --dry-run release 2>&1)
        shift
        for marker in "$@"; do
            grep -q "$marker" <<< "$out" \
                || { echo "error: $name gate did not run $marker" >&2; exit 1; }
        done
    }

    # dry_is <recipe> <expected>: the recipe's dry run is exactly that one line.
    dry_is() {
        local out
        out=$(just --justfile "$tmp/plain/justfile" --dry-run "$1" 2>&1)
        if [[ "$out" != "$2" ]]; then
            echo "error: $1 ran more or less than: $out" >&2
            exit 1
        fi
    }

    # Plain shape: release gate and commit gate are the same.
    stub plain "prerelease: precommit\n"
    check plain stub-precommit

    # Widened shape: release gate runs more than the commit gate.
    stub widened "prerelease: precommit evals\n"
    check widened stub-precommit stub-evals

    # `resume-release` must resolve with no gate dependency: a consumer must be
    # able to finish an interrupted release without re-running a paid prerelease.
    out=$(just --justfile "$tmp/plain/justfile" --dry-run resume-release 2>&1)
    grep -q 'release.sh" --resume' <<< "$out" \
        || { echo "error: resume-release did not reach release.sh: $out" >&2; exit 1; }
    if grep -q 'stub-precommit' <<< "$out"; then
        echo "error: resume-release ran the commit gate" >&2
        exit 1
    fi

    # `dogfood` likewise depends on no gate: it only syncs the copy, and must
    # never run a consumer's commit gate or start a `claude`. The dry run is
    # compared whole, since the stub's own path holds "claude".
    dry_is dogfood 'bash "plugin-dev/dogfood.sh" sync'

    # `check-refs` runs the script alone, with no gate: the consumer's
    # `precommit` depends on it, so a gate dependency here would be a cycle.
    dry_is check-refs 'bash "plugin-dev/check-refs.sh"'

    # `check-size` likewise runs the script alone, with no gate.
    dry_is check-size 'bash "plugin-dev/check-size.sh"'

    # `check-frontmatter` likewise runs the script alone, with no gate.
    dry_is check-frontmatter 'bash "plugin-dev/check-frontmatter.sh"'

    # `check-modes` likewise runs the script alone, with no gate.
    dry_is check-modes 'bash "plugin-dev/check-modes.sh"'

    # Missing `prerelease` must be a hard error naming the missing recipe --
    # this is the contract consumers are told about, so test it, don't assume.
    stub missing ""
    if err=$(just --justfile "$tmp/missing/justfile" --list 2>&1); then
        echo "error: justfile without 'prerelease' was accepted" >&2; exit 1
    fi
    grep -q 'unknown dependency `prerelease`' <<< "$err" \
        || { echo "error: missing 'prerelease' did not name the recipe: $err" >&2; exit 1; }

    # `gates.just` is an opt-in second import: it must compile beside
    # `release.just` (no name defined by both), leave the release chain as it
    # was, and expose the prolog a shebang recipe interpolates.
    stub both "prerelease: precommit\n"
    printf "import '%s/toolkit/gates.just'\n" "$PWD" >> "$tmp/both/justfile"
    check both stub-precommit
    out=$(just --justfile "$tmp/both/justfile" --evaluate plugin_dev_gate_prolog)
    grep -q '^sentinel-guard () {' <<< "$out" \
        || { echo "error: gates.just did not expose the prolog beside release.just" >&2; exit 1; }

    echo "release.just import: ok (plain + widened + missing gate, resume-release, dogfood, check-refs, check-size, check-frontmatter, check-modes, gates.just beside it)"
