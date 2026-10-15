#!/usr/bin/env bash
# End-to-end tests of install.sh, the initial `git subtree add` call site,
# against real git repos in a temp dir: vendoring, ref refusal, no-ref
# resolution, and the settings.json / justfile wiring. No network: the toolkit
# and its "memory" submodule are local bare repos. The update-side call site
# lives in update-plugin-dev-test.sh.
#
# Scope: the version-guard entry's migration from its legacy unquoted spelling,
# and settings.json files install.sh cannot wire. Its siblings
# install-vendor-test.sh and install-settings-test.sh cover vendoring and wiring
# into an existing settings.json.
#
# Usage: bash tests/install-legacy-test.sh   (run from repo root)
set -euo pipefail

# See release-core-test.sh's identical comment: an enclosing `git commit` leaks
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

# The three commands, shared with the existing-settings scenario below.
# Claude Code expands ${CLAUDE_PROJECT_DIR} at hook-fire time, so the commands
# must land in settings.json with the variable literal, all three inside double
# quotes so a project path with a space survives the hook shell. vg_cmd's
# earlier unquoted spelling, legacy_cmd, is migrated by the installer, never
# preserved: the scenarios on it come after the existing-settings one.
# shellcheck disable=SC2016  # the ${...} is meant literal
vg_cmd='bash "${CLAUDE_PROJECT_DIR}/plugin-dev/version-guard.sh"'
# shellcheck disable=SC2016
legacy_cmd='bash ${CLAUDE_PROJECT_DIR}/plugin-dev/version-guard.sh'
# shellcheck disable=SC2016
pretool_cmd='bash "${CLAUDE_PROJECT_DIR}/plugin-dev/dogfood.sh" pre-tool'
# shellcheck disable=SC2016
session_cmd='bash "${CLAUDE_PROJECT_DIR}/plugin-dev/dogfood.sh" session-start'

# The version-guard command used to be written unquoted, and add_hook counts a
# hook present only on an exact command match, so quoting it alone would append
# a second guard beside every existing consumer's legacy one. These scenarios
# pin the migration: the legacy entry is rewritten in place, never duplicated.
legacy_fixture() {
    # $1=settings.json content. A consumer with plugin-dev/ already in place, so
    # the run vendors nothing. Sets $sandbox, $consumer and $settings_json.
    new_sandbox
    mkdir -p "$consumer/.claude-plugin" "$consumer/.claude" "$consumer/plugin-dev"
    printf '{"name": "stub-plugin", "version": "0.1.0"}\n' > "$consumer/.claude-plugin/plugin.json"
    printf '%s\n' "$1" > "$consumer/.claude/settings.json"
    settings_json="$consumer/.claude/settings.json"
}
legacy_entry() {
    # $1=matcher, rest=commands: one PreToolUse entry as JSON.
    local matcher="$1"
    shift
    printf '%s\n' "$@" | jq -R '{type: "command", command: .}' \
        | jq -s --arg m "$matcher" '{matcher: $m, hooks: .}'
}
vg_entries() {
    # $1=settings file: one matcher=command line per version-guard command in
    # either spelling, sorted. A second copy, a surviving legacy one or the
    # wrong matcher each show.
    jq -r '[.hooks.PreToolUse[]? | (.matcher // "none") as $m | .hooks[]? | select(.command | contains("version-guard.sh")) | "\($m)=\(.command)"] | sort | join("\n")' "$1"
}
empty_entries() {
    jq '[.hooks.PreToolUse[]? | select((.hooks // []) | length == 0)] | length' "$1"
}

echo "=== install.sh: a legacy unquoted version-guard entry is requoted in place ==="
legacy_fixture "$(jq -n --argjson e "$(legacy_entry 'Write|Edit' "$legacy_cmd")" \
    '{permissions: {allow: ["Bash(ls:*)"]}, hooks: {PreToolUse: [{hooks: [{type: "command", command: "echo consumer-hook"}]}, $e]}}')"
run_in "$consumer" bash "$repo_root/toolkit/install.sh"
assert_eq "$rc" "0" "legacy only: exit code"
assert_eq "$(vg_entries "$settings_json")" "Write|Edit=$vg_cmd" \
    "legacy only: one version-guard entry, quoted, under the same matcher"
assert_contains "$out" "version-guard hook requoted" "legacy only: the rewrite is reported"
assert_eq "$(jq '[.hooks.PreToolUse[] | .hooks[]? | select(.command == "echo consumer-hook")] | length' "$settings_json")" \
    "1" "legacy only: the consumer's own hook survives"
assert_eq "$(jq -r '.permissions.allow[0]' "$settings_json")" "Bash(ls:*)" \
    "legacy only: the consumer's permissions survive"
cp "$settings_json" "$sandbox/settings.migrated"
run_in "$consumer" bash "$repo_root/toolkit/install.sh"
assert_eq "$rc" "0" "second run after migration: exit code"
if ! cmp -s "$sandbox/settings.migrated" "$settings_json"; then
    fail "second run after migration: settings.json changed"
fi
assert_contains "$out" "already installed, nothing to do" "second run after migration: report"

echo "=== install.sh: a legacy entry the consumer rescoped keeps its matcher ==="
legacy_fixture "$(jq -n --argjson e "$(legacy_entry 'Bash' "$legacy_cmd")" '{hooks: {PreToolUse: [$e]}}')"
run_in "$consumer" bash "$repo_root/toolkit/install.sh"
assert_eq "$rc" "0" "rescoped legacy: exit code"
assert_eq "$(vg_entries "$settings_json")" "Bash=$vg_cmd" \
    "rescoped legacy: rewritten under the consumer's matcher, no entry added under Write|Edit"
assert_contains "$out" "version-guard hook requoted" "rescoped legacy: the rewrite is reported"

echo "=== install.sh: a requote alone is reported as only that ==="
legacy_fixture "$(jq -n \
    --argjson vg "$(legacy_entry 'Write|Edit' "$legacy_cmd")" \
    --argjson pt "$(legacy_entry 'Write|Edit|NotebookEdit' "$pretool_cmd")" \
    --argjson ss "$(jq -n --arg c "$session_cmd" '{hooks: [{type: "command", command: $c}]}')" \
    '{hooks: {PreToolUse: [$vg, $pt], SessionStart: [$ss]}}')"
run_in "$consumer" bash "$repo_root/toolkit/install.sh"
assert_eq "$rc" "0" "requote alone: exit code"
assert_eq "$(vg_entries "$settings_json")" "Write|Edit=$vg_cmd" "requote alone: the entry is quoted"
assert_contains "$out" "version-guard hook requoted" "requote alone: the rewrite is reported"
if grep -q "wired the version-guard" <<<"$out"; then
    fail "requote alone: reported hooks as wired when none was added"
fi

echo "=== install.sh: legacy and quoted entries both present leave the quoted one ==="
# The legacy command shares its entry with a consumer hook in one fixture and
# stands alone in the other: the first entry keeps the consumer's hook, the
# second is dropped rather than left with an empty hooks array.
legacy_fixture "$(jq -n \
    --argjson shared "$(legacy_entry 'Write|Edit' 'echo consumer-hook' "$legacy_cmd")" \
    --argjson quoted "$(legacy_entry 'Edit' "$vg_cmd")" \
    '{hooks: {PreToolUse: [$shared, $quoted]}}')"
run_in "$consumer" bash "$repo_root/toolkit/install.sh"
assert_eq "$rc" "0" "legacy beside quoted, shared entry: exit code"
assert_eq "$(vg_entries "$settings_json")" "Edit=$vg_cmd" \
    "legacy beside quoted, shared entry: one entry left, the quoted one, under its own matcher"
assert_eq "$(jq '[.hooks.PreToolUse[] | .hooks[]? | select(.command == "echo consumer-hook")] | length' "$settings_json")" \
    "1" "legacy beside quoted, shared entry: the consumer's hook in the entry survives"
assert_contains "$out" "version-guard hook requoted" "legacy beside quoted, shared entry: the removal is reported"
legacy_fixture "$(jq -n \
    --argjson alone "$(legacy_entry 'Write|Edit' "$legacy_cmd")" \
    --argjson quoted "$(legacy_entry 'Write|Edit' "$vg_cmd")" \
    '{hooks: {PreToolUse: [$alone, $quoted]}}')"
run_in "$consumer" bash "$repo_root/toolkit/install.sh"
assert_eq "$rc" "0" "legacy beside quoted, lone entry: exit code"
assert_eq "$(vg_entries "$settings_json")" "Write|Edit=$vg_cmd" \
    "legacy beside quoted, lone entry: one entry left, the quoted one"
assert_eq "$(empty_entries "$settings_json")" "0" \
    "legacy beside quoted, lone entry: no entry is left with an empty hooks array"
cp "$settings_json" "$sandbox/settings.migrated"
run_in "$consumer" bash "$repo_root/toolkit/install.sh"
if ! cmp -s "$sandbox/settings.migrated" "$settings_json"; then
    fail "legacy beside quoted, lone entry: a second run changed settings.json"
fi

echo "=== install.sh: the written version-guard command runs from a path with a space ==="
# What Claude Code runs: the command as written, through sh, with the project
# dir in the environment. The stub records that it ran; the legacy spelling is
# run in the same fixture, so the fixture is shown to be one the bare string
# cannot survive.
legacy_fixture "$(jq -n --argjson e "$(legacy_entry 'Write|Edit' "$legacy_cmd")" '{hooks: {PreToolUse: [$e]}}')"
spaced="$sandbox/my consumer"
mv "$consumer" "$spaced"
settings_json="$spaced/.claude/settings.json"
# shellcheck disable=SC2016  # the stub expands CLAUDE_PROJECT_DIR when it runs
printf '#!/usr/bin/env bash\nprintf ran > "$CLAUDE_PROJECT_DIR/vg.ran"\n' > "$spaced/plugin-dev/version-guard.sh"
run_in "$spaced" bash "$repo_root/toolkit/install.sh"
assert_eq "$rc" "0" "spaced path: install exit code"
written="$(jq -r '[.hooks.PreToolUse[]? | .hooks[]? | .command | select(contains("version-guard.sh"))] | first // "false"' "$settings_json")"
run_in "$sandbox" env CLAUDE_PROJECT_DIR="$spaced" sh -c "$legacy_cmd"
if [ "$rc" -eq 0 ] || [ -e "$spaced/vg.ran" ]; then
    fail "spaced path: anchor: the legacy command ran from a path with a space (rc=$rc)"
fi
run_in "$sandbox" env CLAUDE_PROJECT_DIR="$spaced" sh -c "$written"
assert_eq "$rc" "0" "spaced path: the written version-guard command runs: exit code"
assert_eq "$(cat "$spaced/vg.ran" 2>/dev/null)" "ran" "spaced path: the written command reached version-guard.sh"

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
printf '\ninstall.sh legacy-entry scenarios passed\n'
