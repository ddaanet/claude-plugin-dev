# claude-plugin-dev — toolkit dev recipes.

_default:
    @just --list

# Run all syntax + style checks on the toolkit's own scripts.
precommit: whitespace format-docs
    shellcheck toolkit/install.sh toolkit/version-guard.sh toolkit/check-version.sh toolkit/release.sh toolkit/update.sh toolkit/dogfood.sh toolkit/bin/claude scripts/self-release.sh
    bash -n tests/version-guard-test.sh tests/check-version-test.sh tests/release-test.sh tests/self-release-test.sh tests/update-plugin-dev-test.sh tests/install-test.sh tests/dist-tree-test.sh tests/docs-test.sh tests/doc-sync-test.sh tests/citation-test.sh tests/dogfood-sync-test.sh tests/dogfood-sync-refusal-test.sh tests/dogfood-pre-tool-test.sh tests/dogfood-session-start-test.sh tests/dogfood-launcher-test.sh
    just _import-check
    bash tests/version-guard-test.sh
    bash tests/check-version-test.sh
    bash tests/release-test.sh
    bash tests/self-release-test.sh
    bash tests/update-plugin-dev-test.sh
    bash tests/install-test.sh
    bash tests/dist-tree-test.sh
    bash tests/docs-test.sh
    bash tests/doc-sync-test.sh
    bash tests/citation-test.sh
    bash tests/dogfood-sync-test.sh
    bash tests/dogfood-sync-refusal-test.sh
    bash tests/dogfood-pre-tool-test.sh
    bash tests/dogfood-session-start-test.sh
    bash tests/dogfood-launcher-test.sh
    @echo ok

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

# Apply git stripspace to cached text files. Never blocks the recipe.
whitespace:
    #!/usr/bin/env bash
    set -euo pipefail
    while IFS= read -r f; do
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
            git add "$f"
            echo "whitespace: $f"
        fi
    done < <(git ls-files | grep -E '(^justfile$|\.(sh|md|just)$)')

# Hard-wrap prose in docs/ and plans/ at 80 columns, so a line count means something.
format-docs:
    #!/usr/bin/env bash
    set -euo pipefail
    # The wrap is what makes `tests/docs-test.sh`'s line cap mean anything: an
    # unwrapped file stays under a line count by cramming paragraphs onto
    # 300-character lines. rumdl comes from uv.lock via `uv sync`, on PATH
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
    "$bin" fmt --no-cache docs plans

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
    out=$(just --justfile "$tmp/plain/justfile" --dry-run dogfood 2>&1)
    if [[ "$out" != 'bash "plugin-dev/dogfood.sh" sync' ]]; then
        echo "error: dogfood ran more or less than dogfood.sh sync: $out" >&2
        exit 1
    fi

    # Missing `prerelease` must be a hard error naming the missing recipe --
    # this is the contract consumers are told about, so test it, don't assume.
    stub missing ""
    if err=$(just --justfile "$tmp/missing/justfile" --list 2>&1); then
        echo "error: justfile without 'prerelease' was accepted" >&2; exit 1
    fi
    grep -q 'unknown dependency `prerelease`' <<< "$err" \
        || { echo "error: missing 'prerelease' did not name the recipe: $err" >&2; exit 1; }

    echo "release.just import: ok (plain + widened + missing gate, resume-release, dogfood)"
