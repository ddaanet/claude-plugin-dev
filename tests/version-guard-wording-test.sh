#!/usr/bin/env bash
# End-to-end test of toolkit/version-guard.sh against synthetic tool-event
# payloads. Each scenario is a real invocation of the hook with a
# hand-crafted JSON input; assertions exit non-zero on failure.
#
# One script under test per file: the toolkit's other consumer-side script,
# check-version.sh, is covered by tests/check-version-test.sh, which shares
# nothing with this one but the six-line assertion harness every suite here
# carries its own copy of.
#
# Scope: the refusal wording -- initial-release against steady-state, and the
# no-bypass sentence -- over real git fixtures with and without a semver tag.
# Its siblings version-guard-decision-test.sh and version-guard-git-test.sh
# cover the decision and the tag-listing paths.
#
# Usage: bash tests/version-guard-wording-test.sh   (run from repo root)
set -euo pipefail

# When run as this repo's own pre-commit hook, the enclosing `git commit`
# leaks GIT_DIR/GIT_INDEX_FILE/etc. into this process's environment. The new
# git-repo fixture below runs real git commands of its own, and a leaked
# GIT_DIR would redirect them at this repo instead. See
# `tests/release-core-test.sh`'s own header comment, just above its own
# `unset $(git rev-parse --local-env-vars)` line, for the same explanation.
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
    # $1=haystack $2=needle $3=label. Match against a specific extracted
    # field (e.g. permissionDecisionReason alone), never the whole payload
    # blob -- an unrelated line can satisfy a needle and hide the miss.
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
assert_not_contains() {
    # $1=haystack $2=needle $3=label
    # Residual bound: the needle is a grep BRE matched line by line --
    # a metacharacter in it is live, and a needle that spans a newline
    # can never match.
    # A here-string, never a pipe: under pipefail grep -q exits on its first
    # match, the writer can take SIGPIPE, and the pipeline reports failure.
    if grep -q -- "$2" <<<"$1"; then
        fail "$3: output contained '$2'"
        printf '  --- output ---\n%s\n  --------------\n' "$1" >&2
    fi
}

# version-guard scenarios use a fake plugin root with a hand-crafted
# .claude-plugin/plugin.json fixture, so assertions are independent of
# whatever consumer plugin happens to vendor this toolkit.
proj="$(mktemp -d)"
guard_err="$(mktemp)"
# The git fixtures are allocated here, ahead of the trap, so the trap can name
# them: under `set -u` a failure between the trap and a later assignment runs
# the trap with one unbound, which aborts it before the rm and leaks every
# temp dir.
git_proj="$(mktemp -d)"
git_tagged_proj="$(mktemp -d)"
git_vnext_proj="$(mktemp -d)"
trap 'rm -rf "$proj" "$guard_err" "$git_proj" "$git_tagged_proj" "$git_vnext_proj"' EXIT
mkdir -p "$proj/.claude-plugin"
cat > "$proj/.claude-plugin/plugin.json" <<'JSON'
{
  "name": "fixture",
  "version": "1.2.3",
  "license": "MIT"
}
JSON
# Second fixture: a real git repo with no tags -- the "never been released"
# state a first-time plugin author is in, as opposed to $proj above which
# is deliberately not a repo at all (the listing-failure fallback). No
# commit, no user.name/user.email: `git tag --list` on a zero-commit repo
# still exits 0 with no output (checked directly), which is everything a
# no-tags fixture needs to produce -- a commit would assert nothing this
# suite checks. The directory itself is allocated above, beside the trap.
git init -q "$git_proj"
mkdir -p "$git_proj/.claude-plugin"
cat > "$git_proj/.claude-plugin/plugin.json" <<'JSON'
{
  "name": "fixture",
  "version": "1.2.3",
  "license": "MIT"
}
JSON

# Third fixture: a real git repo tagged v1.2.3, for slices 3, 4 and 5.
# Tagging needs a commit, so -- unlike $git_proj above -- this one needs a
# git identity; set locally with -c rather than depending on the invoking
# user's global user.name/user.email.
git init -q "$git_tagged_proj"
mkdir -p "$git_tagged_proj/.claude-plugin"
cat > "$git_tagged_proj/.claude-plugin/plugin.json" <<'JSON'
{
  "name": "fixture",
  "version": "1.2.3",
  "license": "MIT"
}
JSON
git -C "$git_tagged_proj" -c user.name="version-guard-test" -c user.email="version-guard-test@example.com" \
    commit -q --allow-empty -m "fixture commit"
git -C "$git_tagged_proj" tag v1.2.3

# Fourth fixture: tagged vnext and v1.2 only -- both real tags, neither
# matching the semver filter. Slice 4's discriminating half: an
# implementation keyed on `git tag --list 'v*'` emptiness (rather than the
# semver filter) sees two tags here and wrongly answers steady-state; the
# intended predicate still answers initial-release, since neither tag is
# semver.
git init -q "$git_vnext_proj"
mkdir -p "$git_vnext_proj/.claude-plugin"
cat > "$git_vnext_proj/.claude-plugin/plugin.json" <<'JSON'
{
  "name": "fixture",
  "version": "1.2.3",
  "license": "MIT"
}
JSON
git -C "$git_vnext_proj" -c user.name="version-guard-test" -c user.email="version-guard-test@example.com" \
    commit -q --allow-empty -m "fixture commit"
git -C "$git_vnext_proj" tag vnext
git -C "$git_vnext_proj" tag v1.2

# The hook reads CLAUDE_PROJECT_DIR, so every scenario passes it explicitly;
# the payload `cwd` a scenario sets is deliberately not what locates the
# manifest. guard_path exists so one scenario can prepend a PATH stub.
guard_path="$PATH"
run_guard() {
    # $1 = payload JSON. $2 = project dir (default $proj, the non-repo
    # fixture) -- pass $git_proj for the tagless-repo scenarios. $3... =
    # extra "NAME=value" assignments for the hook's environment; the
    # leaked-GIT_DIR scenario below is the one caller that passes any.
    # Captures stdout ONLY -- stderr is diverted to a file rather than
    # folded in with 2>&1, so an assertion below can only pass if the hook
    # JSON really is on stdout, where Claude Code parses it.
    # Both array forms below are the bash-3.2-safe ones: under `set -u`,
    # bash before 4.4 (macOS ships 3.2) errors on expanding an empty array,
    # and all but that one call site passes no $3.
    local payload="$1"
    local project="${2:-$proj}"
    local extra_env=()
    if [[ $# -gt 2 ]]; then extra_env=("${@:3}"); fi
    set +e
    guard_out="$(printf '%s' "$payload" \
        | env CLAUDE_PROJECT_DIR="$project" PATH="$guard_path" ${extra_env[@]+"${extra_env[@]}"} \
              bash toolkit/version-guard.sh 2>"$guard_err")"
    guard_rc=$?
    set -e
}
assert_deny() {
    # $1 = label. A deny is stdout JSON + exit 0: `permissionDecision: "deny"`
    # blocks the call the same as exit 2 and additionally carries systemMessage,
    # which exit 2 discards.
    assert_eq "$guard_rc" "0" "$1 exit code"
    grep -q '"permissionDecision":"deny"' <<<"$guard_out" \
        || fail "$1: no deny decision on stdout"
    grep -q '"permissionDecisionReason"' <<<"$guard_out" \
        || fail "$1: no permissionDecisionReason on stdout"
    grep -q '"systemMessage"' <<<"$guard_out" \
        || fail "$1: no systemMessage on stdout"
    if [[ -s "$guard_err" ]]; then
        fail "$1: wrote to stderr: $(cat "$guard_err")"
    fi
}
assert_allow() {
    # $1 = label. An allow is silence: no JSON at all, exit 0.
    assert_eq "$guard_rc" "0" "$1 exit code"
    if [[ -n "$guard_out" ]]; then
        fail "$1: expected no output, got '$guard_out'"
    fi
}
assert_no_escape_hatch() {
    # $1 = a permissionDecisionReason, $2 = label. Both wordings must carry
    # the no-bypass sentence and must offer the agent no route it could
    # authorise for itself. That property is prose, so only an assertion
    # holds it -- measured, with these missing the suite stays green when the
    # sentence is deleted from either branch, and when "disable the hook in
    # .claude/settings.json and retry the edit" is added to either.
    # Residual bound: a route described without naming a file still passes.
    # These pin the sentence and the two identifiers a bypass would have to
    # name, not the absence of persuasion in general.
    assert_contains "$1" \
        "Do not bypass this guard, modify the recipe, or alter version state by" \
        "$2: no-bypass sentence"
    assert_not_contains "$1" "settings.json" "$2: names no hook-config file"
    assert_not_contains "$1" "version-guard" "$2: names no hook script"
}

# version-guard still denies the edit against a plugin with no tags at all
# (the deny itself isn't new), but the opening sentence claiming the
# manifest version "is the last released version" is false when there has
# never been a release -- the wording must say so instead.
echo "=== version-guard (no tags: initial-release wording) ==="
run_guard "$(jq -nc --arg cwd "$git_proj" --arg fp "$git_proj/.claude-plugin/plugin.json" \
    '{cwd:$cwd, tool_name:"Edit", tool_input:{file_path:$fp, old_string:"1.2.3", new_string:"9.9.9"}}')" \
    "$git_proj"
assert_deny "version-guard no-tags"
reason="$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<<"$guard_out")"
assert_contains "$reason" "never been released" "version-guard no-tags reason: never-released wording"
assert_contains "$reason" "will publish" "version-guard no-tags reason: will-publish wording"
assert_not_contains "$reason" "last released version" "version-guard no-tags reason: no last-released wording"

# Slice 2, same scenario as above (reuses $reason from the no-tags run just
# above rather than re-invoking the hook): the refusal's "1.2.3 -> 9.9.9" is
# the one legitimate mention of the proposed version. Any other mention is
# the message offering a route to ship 9.9.9, which the guard must not do --
# see outline.md:118-121. Excise that one pair and assert the rest is clean,
# rather than checking the whole reason (which trips on the legitimate
# mention) or dropping the first physical line (which is positional, not
# semantic: it fires on a legitimate refusal whose opening merely wraps, and
# misses a route that lands on line 1 -- both measured).
reason_minus_refusal="${reason/1.2.3 -> 9.9.9/}"
assert_not_contains "$reason_minus_refusal" "9.9.9" \
    "version-guard no-tags reason: proposed version not offered as a route beyond the refusal"

# Also slice 2, and the regression this branch actually shipped once: the
# initial-release message must name no recipe invocation. `just release
# {patch|minor|major}` is refused outright on a plugin that has never
# released (`release.sh`'s `release_preflight`, the
# `die "'$bump_arg' bump refused: this plugin has never been released"`
# branch) and a bare `just release` publishes $current rather than $proposed
# (`release_preflight`'s first-release branch, `V="$manifest_version"` with
# no bump), so in THIS branch every mention of the invocation routes the
# agent at something nobody asked for -- which is why the fix withheld the
# identifier instead of qualifying it. Asserted
# here and again over the vnext reason below (slice 4), which takes the same
# initial-release branch -- the steady-state message is the only one that
# names the recipe legitimately, so it alone is exempt from this assertion.
# Residual bound: prose that routes at the recipe without naming it ("when
# the release recipe runs") still passes here.
assert_not_contains "$reason" "just release" \
    "version-guard no-tags reason: initial-release branch names no recipe invocation"
assert_no_escape_hatch "$reason" "version-guard no-tags reason"

# Slice 3: only the agent channel (permissionDecisionReason) may branch on
# release state. systemMessage is a factual one-liner, true in both states,
# so it must come out byte-identical for the same payload whichever fixture
# answers it. Re-invoke the hook here, deliberately fresh, rather than reuse
# $guard_out from the no-tags run forty lines above: that capture is two
# assertion blocks away, so a scenario inserted between would silently
# retarget this byte-identity comparison. That is the opposite call from
# the $reason reuse just above (slice 2) -- that reuse stays documented and
# undisturbed because its run is immediately adjacent, with nothing able to
# land between it and the read.
run_guard "$(jq -nc --arg cwd "$git_proj" --arg fp "$git_proj/.claude-plugin/plugin.json" \
    '{cwd:$cwd, tool_name:"Edit", tool_input:{file_path:$fp, old_string:"1.2.3", new_string:"9.9.9"}}')" \
    "$git_proj"
tagless_sysmsg="$(jq -r '.systemMessage' <<<"$guard_out")"

echo "=== version-guard (v1.2.3 tag: steady-state wording) ==="
run_guard "$(jq -nc --arg cwd "$git_tagged_proj" --arg fp "$git_tagged_proj/.claude-plugin/plugin.json" \
    '{cwd:$cwd, tool_name:"Edit", tool_input:{file_path:$fp, old_string:"1.2.3", new_string:"9.9.9"}}')" \
    "$git_tagged_proj"
assert_deny "version-guard tagged-steady"
reason="$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<<"$guard_out")"
assert_contains "$reason" "last released version" "version-guard tagged-steady reason: last-released wording"
assert_not_contains "$reason" "never been released" "version-guard tagged-steady reason: no never-released wording"
assert_no_escape_hatch "$reason" "version-guard tagged-steady reason"
tagged_sysmsg="$(jq -r '.systemMessage' <<<"$guard_out")"
assert_eq "$tagged_sysmsg" "$tagless_sysmsg" \
    "version-guard systemMessage byte-identical across tagless and tagged fixtures"

# Slice 4: the predicate is the semver filter, not tag-list emptiness or
# repo-ness. A fixture tagged only vnext/v1.2 (neither semver) must still
# read as never-released -- the v1.2.3 fixture above is this scenario's
# steady-state half, already exercised.
echo "=== version-guard (vnext/v1.2 tags only, no semver tag: initial-release wording) ==="
run_guard "$(jq -nc --arg cwd "$git_vnext_proj" --arg fp "$git_vnext_proj/.claude-plugin/plugin.json" \
    '{cwd:$cwd, tool_name:"Edit", tool_input:{file_path:$fp, old_string:"1.2.3", new_string:"9.9.9"}}')" \
    "$git_vnext_proj"
assert_deny "version-guard vnext-tags"
reason="$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<<"$guard_out")"
assert_contains "$reason" "never been released" "version-guard vnext-tags reason: never-released wording"
assert_not_contains "$reason" "last released version" "version-guard vnext-tags reason: no last-released wording"
# Same initial-release branch as the no-tags case above, so the same two
# properties apply: no escape hatch, and no recipe invocation -- this reason
# is not the steady-state message, which alone is exempt from the latter.
assert_no_escape_hatch "$reason" "version-guard vnext-tags reason"
assert_not_contains "$reason" "just release" \
    "version-guard vnext-tags reason: initial-release branch names no recipe invocation"

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nall version-guard wording scenarios passed\n'
