#!/usr/bin/env bash
# End-to-end tests of install.sh, the initial `git subtree add` call site,
# against real git repos in a temp dir: vendoring, ref refusal, no-ref
# resolution, and the settings.json / justfile wiring. No network: the toolkit
# and its "memory" submodule are local bare repos. The update-side call site
# lives in update-plugin-dev-test.sh.
#
# Usage: bash tests/install-test.sh   (run from repo root)
set -euo pipefail

# See release-test.sh's identical comment: an enclosing `git commit` leaks
# GIT_DIR/GIT_INDEX_FILE/etc. into this process. Every git command below
# targets a synthetic fixture repo via `-C`, never this repo, so it's always
# safe to drop them here.
# shellcheck disable=SC2046  # word-splitting is the point: a var-name list
unset $(git rev-parse --local-env-vars)

unset CDPATH   # else `cd` may echo its target into the $(cd … && pwd) capture below
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

failures=0
fail() {
    printf 'FAIL: %s\n' "$1" >&2
    failures=$((failures + 1))
}
assert_eq() {
    # $1=actual $2=expected $3=label
    if [[ "$1" != "$2" ]]; then
        fail "$3: expected '$2', got '$1'"
    fi
}
assert_contains() {
    # $1=haystack $2=needle $3=label
    # Residual bound: the needle is a grep BRE matched line by line --
    # a metacharacter in it is live, and a needle that spans a newline
    # can never match.
    # A here-string, never a pipe: under pipefail grep -q exits on its first
    # match, the writer can take SIGPIPE, and the pipeline reports failure.
    if ! grep -q -- "$2" <<<"$1"; then
        fail "$3: output did not contain '$2'"
        printf '  --- output ---\n%s\n  --------------\n' "$1" >&2
    fi
}

sandboxes=()
cleanup() {
    local s
    for s in "${sandboxes[@]:-}"; do
        [ -n "$s" ] && rm -rf "$s"
    done
}
trap cleanup EXIT

# Recursive submodule transports (add/subtree's on-demand submodule fetch)
# default protocol.file.allow to "user", which local bare-repo fixtures still
# trip on. Every git call below targets local paths only, so allow it broadly
# instead of threading `-c` through each call site.
allow_file() {
    env GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=protocol.file.allow GIT_CONFIG_VALUE_0=always "$@"
}

git_id() {
    git -C "$1" config user.email test@example.com
    git -C "$1" config user.name "Toolkit Test"
    git -C "$1" config commit.gpgsign false
}

# out/rc from the last run_in call.
out=""
rc=0
run_in() {
    # $1=dir, rest=command. Captures stdout+stderr in $out, status in $rc.
    local dir="$1"
    shift
    set +e
    out="$(cd "$dir" && "$@" 2>&1)"
    rc=$?
    set -e
}

# The consumer-visible half of the leak: an unregistered gitlink under
# plugin-dev/ fatals a bare `git submodule status` for the WHOLE repo, even
# though every submodule the consumer itself registered is fine. Asserted on
# both call sites, since either can be the one that vendors.
assert_clean_vendor() {
    # $1=consumer dir, $2=label
    # Captured, then searched: piped into grep -q under pipefail, git can take
    # SIGPIPE on an early match and a present gitlink would read as absent.
    local vendor_index
    vendor_index="$(git -C "$1" ls-files -s plugin-dev/)"
    if grep -q '^160000' <<<"$vendor_index"; then
        fail "$2: vendored tree carries a gitlink"
    fi
    run_in "$1" git submodule status
    assert_eq "$rc" "0" "$2: consumer's bare git submodule status stays clean"
}

# Advances the fixture toolkit repo (shaped like this repo: a `memory`
# submodule mounted at top level, consumer-facing files under toolkit/) by one
# commit and cuts both tags a real toolkit release cuts.
make_toolkit_release() {
    local toolkit="$1" tag="$2" version="$3" dist_sha
    mkdir -p "$toolkit/toolkit"
    printf '%s\n' "$version" > "$toolkit/toolkit/VERSION"
    git -C "$toolkit" add -A
    git -C "$toolkit" commit -qm "toolkit: $version"
    git -C "$toolkit" tag "$tag"
    # The dist tag is what consumers vendor: `git subtree split --prefix=toolkit`
    # yields a ref whose ROOT is toolkit/, so it carries neither the `memory`
    # gitlink nor anything else from the toolkit's working environment.
    dist_sha="$(git -C "$toolkit" subtree split -q --prefix=toolkit | tail -1)"
    git -C "$toolkit" tag "dist-$tag" "$dist_sha"
}

new_sandbox() {
    # Sets $sandbox, $toolkit, $consumer.
    sandbox="$(mktemp -d)"
    sandboxes+=("$sandbox")
    toolkit="$sandbox/toolkit"
    consumer="$sandbox/consumer"

    # The two memory remotes are kept distinct (different seed messages, so
    # different shas) to keep the toolkit's gitlink and the consumer's
    # unrelated: assert_clean_vendor has to tell "the toolkit's memory was
    # dropped" apart from "the consumer's memory survived", which it cannot do
    # if both name the same object.

    # Toolkit-side memory remote, standing in for claude-plugin-dev-memory.git.
    git init -q --bare -b main "$sandbox/toolkit-memory-origin.git"
    local seed
    seed="$(mktemp -d)"
    git init -q -b main "$seed"
    git_id "$seed"
    git -C "$seed" commit --allow-empty -qm "seed: toolkit memory"
    git -C "$seed" remote add origin "$sandbox/toolkit-memory-origin.git"
    git -C "$seed" push -q -u origin main
    rm -rf "$seed"

    git init -q -b main "$toolkit"
    git_id "$toolkit"
    git -C "$toolkit" commit --allow-empty -qm init
    allow_file git -C "$toolkit" submodule add -q "$sandbox/toolkit-memory-origin.git" memory
    git -C "$toolkit" commit -qm "toolkit: mount memory"
    make_toolkit_release "$toolkit" v1 1.0.0

    # Consumer-side memory remote: unrelated to the toolkit's, same path.
    git init -q --bare -b main "$sandbox/consumer-memory-origin.git"
    seed="$(mktemp -d)"
    git init -q -b main "$seed"
    git_id "$seed"
    git -C "$seed" commit --allow-empty -qm "seed: consumer memory"
    git -C "$seed" remote add origin "$sandbox/consumer-memory-origin.git"
    git -C "$seed" push -q -u origin main
    rm -rf "$seed"

    git init -q -b main "$consumer"
    git_id "$consumer"
    git -C "$consumer" commit --allow-empty -qm init
}

echo "=== install.sh: vendors into a consumer that already mounts a memory submodule ==="
new_sandbox

# The reverse ordering: an existing plugin repo that mounted its gitlore
# memory submodule before adopting the toolkit. install.sh's `subtree add`
# performs the same raw, unprefixed fetch of the toolkit's history as
# `subtree pull`, so it hits the same on-demand recursion collision unless
# scoped the same way.
run_in "$consumer" allow_file git submodule add -q "$sandbox/consumer-memory-origin.git" memory
assert_eq "$rc" "0" "consumer memory submodule mount exit code"
git -C "$consumer" commit -qm "consumer: mount memory"

# install.sh's run-in-target guard needs a plugin manifest in the cwd.
mkdir -p "$consumer/.claude-plugin"
printf '{"name": "stub-plugin", "version": "0.1.0"}\n' > "$consumer/.claude-plugin/plugin.json"
git -C "$consumer" add .claude-plugin/plugin.json
git -C "$consumer" commit -qm "consumer: plugin manifest"

run_in "$consumer" allow_file env TOOLKIT_URL="$toolkit" bash "$repo_root/toolkit/install.sh" dist-v1
assert_eq "$rc" "0" "install.sh exit code"
# Only `just dogfood` creates the copy, and a launch without one starts without
# the plugin, so the next steps name it.
assert_contains "$out" "just dogfood" "install.sh's next steps create the copy"
assert_eq "$(cat "$consumer/plugin-dev/VERSION" 2>/dev/null)" "1.0.0" "install.sh vendored VERSION"
assert_eq "$(git -C "$consumer" config --get submodule.memory.url)" \
    "$sandbox/consumer-memory-origin.git" "consumer's own memory submodule registration untouched"
assert_clean_vendor "$consumer" "install.sh"

echo "=== install.sh refuses any ref outside the dist lineage ==="
new_sandbox

# install.sh's run-in-target guard needs a plugin manifest in the cwd.
mkdir -p "$consumer/.claude-plugin"
printf '{"name": "stub-plugin", "version": "0.1.0"}\n' > "$consumer/.claude-plugin/plugin.json"
git -C "$consumer" add .claude-plugin/plugin.json
git -C "$consumer" commit -qm "consumer: plugin manifest"

# A source tag resolves to the toolkit's ROOT tree -- its memory gitlink,
# .claude/, CLAUDE.md, its own justfile. Vendoring one is the leak this whole
# design exists to stop, and it is silent, so the call site must refuse it
# rather than warn. This is what makes the fetch-recursion collision
# unreachable, so it is asserted rather than assumed.
run_in "$consumer" allow_file env TOOLKIT_URL="$toolkit" bash "$repo_root/toolkit/install.sh" v1
if [ "$rc" -eq 0 ]; then fail "install.sh accepted a source tag"; fi
assert_contains "$out" "dist-v1" "install.sh refusal names the dist tag to use"
if [ -d "$consumer/plugin-dev" ]; then fail "install.sh vendored despite refusing the ref"; fi

echo "=== install.sh: no ref resolves the newest dist tag ==="
new_sandbox
make_toolkit_release "$toolkit" v2 1.0.1

mkdir -p "$consumer/.claude-plugin"
printf '{"name": "stub-plugin", "version": "0.1.0"}\n' > "$consumer/.claude-plugin/plugin.json"
git -C "$consumer" add .claude-plugin/plugin.json
git -C "$consumer" commit -qm "consumer: plugin manifest"

if [ -e "$consumer/.claude/settings.json" ]; then fail "anchor: the no-ref fixture already has a settings.json"; fi
run_in "$consumer" allow_file env TOOLKIT_URL="$toolkit" bash "$repo_root/toolkit/install.sh"
assert_eq "$rc" "0" "no-ref install exit code"

# The three commands, shared with the existing-settings scenario below.
# vg_cmd is exact and unquoted: consumers' settings already carry this
# spelling, so a respelt command would be added again beside it on their next
# install. Claude Code expands ${CLAUDE_PROJECT_DIR} at hook-fire time, so the
# commands must land in settings.json with the variable literal, the dogfood
# ones inside double quotes.
# shellcheck disable=SC2016  # the ${...} is meant literal
vg_cmd='bash ${CLAUDE_PROJECT_DIR}/plugin-dev/version-guard.sh'
# shellcheck disable=SC2016
pretool_cmd='bash "${CLAUDE_PROJECT_DIR}/plugin-dev/dogfood.sh" pre-tool'
# shellcheck disable=SC2016
session_cmd='bash "${CLAUDE_PROJECT_DIR}/plugin-dev/dogfood.sh" session-start'
# One matcher=command line per hook, sorted: the order entries land in is not
# part of the contract, a missing, extra or mis-scoped hook is.
fresh_json="$consumer/.claude/settings.json"
assert_eq "$(jq -r '[.hooks.PreToolUse[]? | .matcher as $m | .hooks[]? | "\($m)=\(.command)"] | sort | join("\n")' "$fresh_json")" \
    "Write|Edit=$vg_cmd
Write|Edit|NotebookEdit=$pretool_cmd" "a fresh settings.json carries version-guard and the pre-tool hook under PreToolUse"
assert_eq "$(jq -r '[.hooks.SessionStart[]? | (if has("matcher") then "matcher" else "none" end) + "=" + (.hooks[]? | .command)] | join("\n")' "$fresh_json")" \
    "none=$session_cmd" "a fresh settings.json carries the session-start hook with no matcher"
assert_contains "$out" "dist-v2" "no-ref install names the resolved tag"
assert_eq "$(cat "$consumer/plugin-dev/VERSION" 2>/dev/null)" "1.0.1" "no-ref install vendored the newest VERSION"

# Same failure path on the install side, from a fresh consumer (install.sh
# only resolves when plugin-dev/ is absent).
consumer2="$sandbox/consumer2"
git init -q -b main "$consumer2"
git_id "$consumer2"
git -C "$consumer2" commit --allow-empty -qm init
mkdir -p "$consumer2/.claude-plugin"
printf '{"name": "stub-plugin", "version": "0.1.0"}\n' > "$consumer2/.claude-plugin/plugin.json"
git -C "$consumer2" add .claude-plugin/plugin.json
git -C "$consumer2" commit -qm "consumer: plugin manifest"
git init -q --bare -b main "$sandbox/tagless.git"
run_in "$consumer2" allow_file env TOOLKIT_URL="$sandbox/tagless.git" bash "$repo_root/toolkit/install.sh"
if [ "$rc" -eq 0 ]; then fail "no-ref install succeeded against a tagless remote"; fi
assert_contains "$out" "dist-vX.Y.Z" "install tagless-remote refusal names the explicit-ref fallback"

echo "=== install.sh: wires into an existing settings.json without replacing it ==="
new_sandbox

mkdir -p "$consumer/.claude-plugin" "$consumer/.claude"
printf '{"name": "stub-plugin", "version": "0.1.0"}\n' > "$consumer/.claude-plugin/plugin.json"
# A PreToolUse entry with no `matcher` key is legal — it matches every tool —
# and is the ordinary shape of a hand-written block. `null | test(...)` aborts
# jq, which used to fall through to the stub-from-scratch fallback and replace
# the whole file with just the version-guard hook.
cat > "$consumer/.claude/settings.json" <<'JSON'
{
  "permissions": {"allow": ["Bash(ls:*)"]},
  "hooks": {
    "PreToolUse": [{"hooks": [{"type": "command", "command": "echo consumer-hook"}]}],
    "SessionStart": [{"hooks": [{"type": "command", "command": "echo consumer-start"}]}]
  }
}
JSON
printf 'default:\n    @echo hi\n' > "$consumer/justfile"
git -C "$consumer" add -A
git -C "$consumer" commit -qm "consumer: manifest, settings, justfile"
# `ls -l | cut` and not `stat`: the mode format flag is the GNU/BSD split this
# whole file is careful about (`stat -c` vs `stat -f`). One fixed path, and only
# the mode column is read, so SC2012's filename concerns don't arise.
# shellcheck disable=SC2012  # fixed path, reading the mode column only
settings_mode="$(ls -l "$consumer/.claude/settings.json" | cut -c1-10)"

run_in "$consumer" allow_file env TOOLKIT_URL="$toolkit" bash "$repo_root/toolkit/install.sh" dist-v1
assert_eq "$rc" "0" "install.sh exit code over an existing settings.json"
settings_json="$consumer/.claude/settings.json"
assert_eq "$(jq -r '.permissions.allow[0]' "$settings_json")" \
    "Bash(ls:*)" "install.sh kept the consumer's permissions block"
assert_eq "$(jq '[.hooks.PreToolUse[] | .hooks[]? | select(.command == "echo consumer-hook")] | length' "$settings_json")" \
    "1" "install.sh kept the consumer's own matcher-less hook"
assert_eq "$(jq --arg c "$vg_cmd" '[.hooks.PreToolUse[] | .hooks[]? | select(.command == $c)] | length' "$settings_json")" \
    "1" "install.sh added the version-guard hook"
# One word per hook carrying the command, naming its entry's matcher: a second
# copy under any entry, or the one copy under the wrong matcher, shows.
assert_eq "$(jq -r --arg c "$pretool_cmd" '[.hooks.PreToolUse[]? | (.matcher // "none") as $m | .hooks[]? | select(.command == $c) | $m] | join(" ")' "$settings_json")" \
    "Write|Edit|NotebookEdit" "install adds the pre-tool hook once"
assert_eq "$(jq -r --arg c "$session_cmd" '[.hooks.SessionStart[]? | (if has("matcher") then "matcher=\(.matcher)" else "none" end) as $m | .hooks[]? | select(.command == $c) | $m] | join(" ")' "$settings_json")" \
    "none" "install adds the session-start hook once"
# Every dogfood.sh command, any event: total and quoted. An unquoted or
# install-time-expanded spelling reds here as 2:0, not as a missing hook.
# shellcheck disable=SC2016  # the ${...} is meant literal
quoted='"${CLAUDE_PROJECT_DIR}/plugin-dev/dogfood.sh"'
assert_eq "$(jq -r --arg q "$quoted" '[.hooks[]?[]? | .hooks[]? | .command // "" | select(contains("dogfood.sh"))] | "\(length):\(map(select(contains($q))) | length)"' "$settings_json")" \
    "2:2" "the commands quote the project dir"
# What Claude Code runs: each dogfood command as written, through sh, from a
# project dir whose path holds a space, must reach dogfood.sh with a subcommand
# it takes. The fixture toolkit ships no dogfood.sh, so a copy stands in.
spaced="$sandbox/my consumer"
mkdir -p "$spaced/plugin-dev"
cp "$repo_root/toolkit/dogfood.sh" "$spaced/plugin-dev/"
spaced_p="$(cd "$spaced" && pwd -P)"   # dogfood.sh names its root physically
run_hook() {
    # $1=event $2=payload on stdin; sets $out and $rc as run_in does.
    local cmd
    cmd="$(jq -r --arg e "$1" '[.hooks[$e][]? | .hooks[]? | .command | select(contains("dogfood.sh"))] | first // "false"' "$settings_json")"
    run_in "$sandbox" env CLAUDE_PROJECT_DIR="$spaced" CLAUDE_CODE_PLUGIN_DIRS= sh -c "$cmd" <<< "$2"
}
run_hook PreToolUse "$(jq -nc --arg p "$spaced/dist/plugin/x" '{tool_input: {file_path: $p}}')"
assert_eq "$rc" "0" "the written pre-tool command runs: exit code"
assert_contains "$out" '"permissionDecision":"deny"' "the written pre-tool command runs the copy guard"
run_hook SessionStart ''
assert_eq "$rc" "0" "the written session-start command runs: exit code"
assert_contains "$out" "does not load $spaced_p/dist/plugin" "the written session-start command runs the check"
# Beside, not instead of: "install adds the session-start hook once" above
# already places the new hook in this same array.
assert_eq "$(jq '[.hooks.SessionStart[]? | .hooks[]? | select(.command == "echo consumer-start")] | length' "$settings_json")" \
    "1" "a pre-existing SessionStart entry survives"
# mktemp creates 0600, so replacing the file with `mv` silently narrows its
# permissions. Compared against the mode the file already had, not a literal,
# so the assertion holds under any umask.
# shellcheck disable=SC2012  # fixed path, reading the mode column only
assert_eq "$(ls -l "$settings_json" | cut -c1-10)" "$settings_mode" \
    "install.sh preserved the settings.json mode"
# `$(cat justfile)` strips every trailing newline, so the rewrite that prepends
# the import line has to put one back.
if [ -n "$(tail -c1 "$consumer/justfile")" ]; then
    fail "install.sh dropped the justfile's trailing newline"
fi
assert_contains "$(cat "$consumer/justfile")" "@echo hi" "install.sh kept the justfile's own content"

# plugin-dev/ is vendored now, so the second run takes no ref. The copy sits
# outside the consumer so the run under test sees the same tree as the first.
cp "$settings_json" "$sandbox/settings.before"
run_in "$consumer" allow_file env TOOLKIT_URL="$toolkit" bash "$repo_root/toolkit/install.sh"
assert_eq "$rc" "0" "a re-run is a no-op: exit code"
if ! cmp -s "$sandbox/settings.before" "$settings_json"; then
    fail "a re-run is a no-op: settings.json changed"
fi
assert_contains "$out" "already installed, nothing to do" "a re-run is a no-op: report"

# Presence is the command alone: an entry under a matcher the installer never
# writes still counts, so the next run adds nothing beside it.
jq --arg p "$pretool_cmd" --arg v "$vg_cmd" \
    '.hooks.PreToolUse |= map(if any(.hooks[]?; .command == $p or .command == $v) then .matcher = "Bash" else . end)' \
    "$settings_json" > "$sandbox/settings.rematched"
cp "$sandbox/settings.rematched" "$settings_json"
assert_eq "$(jq -r --arg p "$pretool_cmd" --arg v "$vg_cmd" '[.hooks.PreToolUse[]? | .matcher as $m | .hooks[]? | select(.command == $p or .command == $v) | $m] | join(" ")' "$settings_json")" \
    "Bash Bash" "an entry under another matcher counts as present: setup"
run_in "$consumer" allow_file env TOOLKIT_URL="$toolkit" bash "$repo_root/toolkit/install.sh"
if ! cmp -s "$sandbox/settings.rematched" "$settings_json"; then
    fail "an entry under another matcher counts as present: settings.json changed"
fi
# An install that stopped short of step 3 would leave the file untouched too.
assert_contains "$out" "already installed, nothing to do" "an entry under another matcher counts as present: report"

echo "=== install.sh: a malformed settings.json is reported with jq's diagnosis ==="
new_sandbox
mkdir -p "$consumer/.claude-plugin" "$consumer/.claude"
printf '{"name": "stub-plugin", "version": "0.1.0"}\n' > "$consumer/.claude-plugin/plugin.json"
printf '{"permissions": {\n' > "$consumer/.claude/settings.json"
git -C "$consumer" add -A
git -C "$consumer" commit -qm "consumer: manifest + broken settings"

run_in "$consumer" allow_file env TOOLKIT_URL="$toolkit" bash "$repo_root/toolkit/install.sh" dist-v1
if [ "$rc" -eq 0 ]; then fail "install.sh accepted a malformed settings.json"; fi
assert_contains "$out" "parse error" "malformed settings.json refusal carries jq's parse error"
if [ -d "$consumer/plugin-dev" ]; then fail "install.sh vendored despite the malformed settings.json"; fi

# Valid JSON, so the pre-flight passes, but PreToolUse is an object where an
# array belongs: the first jq stage fails, and the two behind it read nothing
# and exit 0. Only pipefail carries the failure to the error branch; without it
# the empty output would be written over the consumer's file.
echo "=== install.sh: a settings.json it cannot wire is left as it was ==="
new_sandbox
mkdir -p "$consumer/.claude-plugin" "$consumer/.claude" "$consumer/plugin-dev"
printf '{"name": "stub-plugin", "version": "0.1.0"}\n' > "$consumer/.claude-plugin/plugin.json"
printf '{"hooks": {"PreToolUse": {"matcher": "Bash"}}}\n' > "$consumer/.claude/settings.json"
cp "$consumer/.claude/settings.json" "$sandbox/settings.before"
run_in "$consumer" bash "$repo_root/toolkit/install.sh"
if [ "$rc" -eq 0 ]; then fail "install.sh reported success over a settings.json it could not wire"; fi
assert_contains "$out" "could not wire the hooks into .claude/settings.json — nothing written." \
    "an unwirable settings.json is reported"
if ! cmp -s "$sandbox/settings.before" "$consumer/.claude/settings.json"; then
    fail "an unwirable settings.json was rewritten"
fi

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\ninstall.sh scenarios passed\n'
