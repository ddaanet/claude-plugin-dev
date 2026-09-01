# claude-plugin-dev — toolkit dev recipes.

_default:
    @just --list

# Run all syntax + style checks on the toolkit's own scripts.
precommit: whitespace
    shellcheck toolkit/install.sh toolkit/version-guard.sh toolkit/check-version.sh toolkit/release.sh toolkit/update.sh
    bash -n tests/hook-test.sh tests/release-test.sh tests/update-plugin-dev-test.sh tests/dist-tree-test.sh
    just _import-check
    bash tests/hook-test.sh
    bash tests/release-test.sh
    bash tests/update-plugin-dev-test.sh
    bash tests/dist-tree-test.sh
    @echo ok

# Checks that run before a release. Add slow or paid checks here.
prerelease: precommit

# Cut a toolkit release: bump VERSION, commit, tag, push, GitHub release.
release bump='patch': prerelease
    #!/usr/bin/env bash
    set -euo pipefail
    git diff --quiet HEAD || { echo "error: uncommitted changes" >&2; exit 1; }
    branch=$(git symbolic-ref -q --short HEAD || echo "")
    main_branch=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' || echo "main")
    [ "$branch" = "$main_branch" ] || { echo "error: must be on $main_branch (currently $branch)" >&2; exit 1; }
    [ -f toolkit/VERSION ] || { echo "error: toolkit/VERSION file missing" >&2; exit 1; }
    file_version=$(tr -d '[:space:]' < toolkit/VERSION)
    # --match 'v*' so the dist-v* tags cut below can never be read as the
    # latest release: they name a separate lineage, not a version history.
    latest_tag=$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null | sed 's/^v//' || true)
    if [ -n "$latest_tag" ] && [ "$file_version" != "$latest_tag" ]; then
      echo "error: toolkit/VERSION ($file_version) does not match latest tag (v$latest_tag)" >&2
      echo "hint: toolkit/VERSION holds the LAST released version. \`just release\` bumps from there." >&2
      echo "      revert any manual VERSION bump and re-run." >&2
      exit 1
    fi
    IFS=. read -r maj min pat <<< "$file_version"
    # quote() and not "{{bump}}": just interpolates textually before bash parses
    # this line, so double quotes do not stop a caller's $(...) from running.
    case {{quote(bump)}} in
      major) new_version="$((maj+1)).0.0" ;;
      minor) new_version="$maj.$((min+1)).0" ;;
      patch) new_version="$maj.$min.$((pat+1))" ;;
      *) echo "error: unknown bump type: {{bump}}" >&2; exit 1 ;;
    esac
    tag="v$new_version"
    dist_tag="dist-$tag"
    for t in "$tag" "$dist_tag"; do
      git rev-parse "$t" >/dev/null 2>&1 && { echo "error: tag $t already exists" >&2; exit 1; }
    done
    printf '%s\n' "$new_version" > toolkit/VERSION
    git add toolkit/VERSION
    git commit -m "release: $new_version"
    git tag -a "$tag" -m "Release $new_version"
    # Consumers vendor `dist_tag`, never `tag`. `git subtree pull` copies a
    # ref's ROOT tree, and this repo's root is its own working environment --
    # the memory gitlink, .claude/, CLAUDE.md, this justfile, docs, tests.
    # Splitting toolkit/ yields a ref whose root is exactly what ships.
    # Cut after the VERSION commit so the dist tree carries the new VERSION.
    dist_sha=$(git subtree split -q --prefix=toolkit)
    git tag -a "$dist_tag" -m "Dist $new_version" "$dist_sha"
    git push
    git push origin "$tag" "$dist_tag"
    gh release create "$tag" --title "Release $new_version" --generate-notes
    echo "Release $tag complete (consumers pull $dist_tag)"

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

    # Missing `prerelease` must be a hard error naming the missing recipe --
    # this is the contract consumers are told about, so test it, don't assume.
    stub missing ""
    if err=$(just --justfile "$tmp/missing/justfile" --list 2>&1); then
        echo "error: justfile without 'prerelease' was accepted" >&2; exit 1
    fi
    grep -q 'unknown dependency `prerelease`' <<< "$err" \
        || { echo "error: missing 'prerelease' did not name the recipe: $err" >&2; exit 1; }

    echo "release.just import: ok (plain + widened + missing gate, resume-release)"
