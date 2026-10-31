# claude-plugin-dev — toolkit dev recipes.

# The toolkit's own gate sentinels, imported from the source tree rather than a
# vendored copy, so `precommit` dogfoods the file it ships.
import 'toolkit/gates.just'

# The tools `precommit`'s verdict depends on that no input file pins: a new
# shellcheck can find new problems, and every suite runs under bash, git, jq and
# just. rumdl is pinned in pyproject.toml, an input, but the binary that runs is
# whatever `format-docs` finds, so its version is hashed too, resolved the same
# way.
export PLUGIN_DEV_GATE_TOOLS := "bash --version\ngit --version\njust --version\njq --version\nshellcheck --version\n{ command -v rumdl >/dev/null 2>&1 && rumdl --version; } || .venv/bin/rumdl --version"

_default:
    @just --list

# Run all syntax + style checks and every suite, skipped while no input changed.
precommit:
    #!{{ plugin_dev_gate_prolog }}
    # The inputs are every non-ignored file, since the checks read essentially
    # all of them (citation, doc-sync, check-refs, check-size), all from disk.
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

# Apply git stripspace to text files on disk, tracked or not. Never blocks the recipe.
whitespace:
    #!/usr/bin/env bash
    set -euo pipefail
    # From disk, not the index: the files the gate hashes and the checks read,
    # so a file added after a cached pass was fixed before it was hashed.
    while IFS= read -r -d '' f; do
        case "$f" in justfile | *.sh | *.md | *.just) ;; *) continue ;; esac
        # Listed but gone from the worktree: a deletion not yet staged, or one
        # staged but left out of a `git commit -- <paths>`, whose hook sees HEAD's index.
        [ -f "$f" ] || continue
        tmp=$(mktemp)
        git stripspace < "$f" > "$tmp"
        if cmp -s "$f" "$tmp"; then
            rm -f "$tmp"
        else
            # Written through the file, not mv-ed over it: mktemp creates 0600
            # and mv would carry that mode across, so a whitespace-only pass
            # would also stage a mode change on any 755 script.
            cat "$tmp" > "$f"
            rm -f "$tmp"
            # A tracked file's fix is staged with it; an untracked file is
            # fixed in place and left for the committer to add.
            if [ -n "$(git ls-files -- ":(literal)$f")" ]; then
                git add -- "$f"
                echo "whitespace: $f"
            else
                echo "whitespace: $f (untracked, not staged)"
            fi
        fi
    done < <(git ls-files -z --cached --others --exclude-standard)

# Hard-wrap prose in docs/, plans/ and the shipped manual at 80 columns, for an 80-column read.
format-docs:
    #!/usr/bin/env bash
    set -euo pipefail
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
    # `fmt` exits 0 with anything it cannot wrap left in place; `check --fix`
    # would exit 1 on the same tree and fail the gate over a long URL.
    "$bin" fmt --no-cache docs plans toolkit/README.md toolkit/manual toolkit/migrations

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
    tmp=$(mktemp -d)
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

    echo "release.just import: ok (plain + widened + missing gate, resume-release, dogfood, check-refs, check-size, gates.just beside it)"
