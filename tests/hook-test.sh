#!/usr/bin/env bash
# End-to-end test of the toolkit's hook scripts against synthetic
# tool-event payloads. Each scenario is a real invocation of the hook
# with a hand-crafted JSON input; assertions exit non-zero on failure.
#
# Usage: bash tests/hook-test.sh   (run from repo root)
set -euo pipefail

# When run as this repo's own pre-commit hook, the enclosing `git commit`
# leaks GIT_DIR/GIT_INDEX_FILE/etc. into this process's environment. The new
# git-repo fixture below runs real git commands of its own, and a leaked
# GIT_DIR would redirect them at this repo instead. See release-test.sh:8-13.
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
    if [[ "$1" != *"$2"* ]]; then
        fail "$3: expected to contain '$2', got '$1'"
    fi
}
assert_not_contains() {
    # $1=haystack $2=needle $3=label
    if [[ "$1" == *"$2"* ]]; then
        fail "$3: expected NOT to contain '$2', got '$1'"
    fi
}

# version-guard scenarios use a fake plugin root with a hand-crafted
# .claude-plugin/plugin.json fixture, so assertions are independent of
# whatever consumer plugin happens to vendor this toolkit.
proj="$(mktemp -d)"
guard_err="$(mktemp)"
# $git_proj is allocated here, not beside the fixture it belongs to below,
# so the trap can name it: under `set -u` a failure between the trap and a
# later assignment runs the trap with it unbound, which aborts the trap
# before the rm and leaks every temp dir. Same reason release-test.sh
# declares `sandboxes=()` ahead of its own trap.
git_proj="$(mktemp -d)"
# Fixtures for slices 3-5: a repo tagged v1.2.3 (the steady-state half of
# slices 3 and 4, and reused as the "second fixture carrying v1.2.3" slice 5
# points a leaked GIT_DIR at -- one repo honestly serves both roles, since
# slice 5 only needs a real repository whose tag listing would answer STEADY
# if discovered), a repo tagged vnext/v1.2 only (slice 4's discriminating
# half: two real tags, neither semver), and a PATH stub directory for a
# `git` that exits 127 (slice 6), and a second stub directory for a `grep`
# that exits 2 (the failing-filter scenario). All allocated here, ahead of
# the trap, for the same reason $git_proj is: an unbound name in the trap
# body skips cleanup of every temp dir, not just its own.
git_tagged_proj="$(mktemp -d)"
git_vnext_proj="$(mktemp -d)"
guard_stub127_dir="$(mktemp -d)"
guard_stubgrep_dir="$(mktemp -d)"
trap 'rm -rf "$proj" "$guard_err" "$git_proj" "$git_tagged_proj" "$git_vnext_proj" "$guard_stub127_dir" "$guard_stubgrep_dir"' EXIT
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
git -C "$git_tagged_proj" -c user.name="hook-test" -c user.email="hook-test@example.com" \
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
git -C "$git_vnext_proj" -c user.name="hook-test" -c user.email="hook-test@example.com" \
    commit -q --allow-empty -m "fixture commit"
git -C "$git_vnext_proj" tag vnext
git -C "$git_vnext_proj" tag v1.2

# PATH stub for slice 6: a `git` that always exits 127, simulating the
# listing failing outright (as a genuinely absent `git` would) rather than
# succeeding with no output. It writes a line to stderr before failing, which
# is what makes that scenario's stderr-empty assertion load-bearing: a silent
# stub leaves nothing for the guard's `2>/dev/null` to swallow, so the
# assertion would pass without proving the redirect is there. Only prepended
# to guard_path for that one scenario, following the BSD-realpath scenario's
# existing pattern below.
cat > "$guard_stub127_dir/git" <<'SH'
#!/bin/sh
echo 'git: fatal: stub git standing in for an absent binary' >&2
exit 127
SH
chmod 755 "$guard_stub127_dir/git"

# PATH stub for the failing-filter scenario: a `grep` that exits 2 (grep's
# own "an error occurred" status, as opposed to 1, "no match"). `grep` is
# invoked exactly once in the guard, in the post-deny semver filter, so
# stubbing it cannot disturb the deny decision itself.
#
# Silent, unlike the 127 `git` stub above, which writes to stderr on
# purpose. The guard redirects the tag listing's stderr (git failing to
# find a repo is an expected outcome there) but deliberately does NOT
# redirect the filter's: a broken `grep` means a broken environment and
# should show in a --debug run. A noisy stub would therefore trip
# assert_deny's stderr check on behaviour that is reviewed and intended,
# so the noise is left out rather than the assertion weakened.
cat > "$guard_stubgrep_dir/grep" <<'SH'
#!/bin/sh
exit 2
SH
chmod 755 "$guard_stubgrep_dir/grep"

# The hook reads CLAUDE_PROJECT_DIR, so every scenario passes it explicitly;
# the payload `cwd` a scenario sets is deliberately not what locates the
# manifest. guard_path exists so one scenario can prepend a PATH stub.
guard_path="$PATH"
run_guard() {
    # $1 = payload JSON. $2 = project dir (default $proj, the non-repo
    # fixture) -- pass $git_proj for the tagless-repo scenarios. $3... =
    # extra "NAME=value" assignments for the hook's environment (e.g. a
    # future GIT_DIR override); none of today's scenarios need one, but the
    # mechanism is here so a later slice doesn't have to touch every
    # existing call site again. Captures stdout ONLY -- stderr is diverted
    # to a file rather than folded in with 2>&1, so an assertion below can
    # only pass if the hook JSON really is on stdout, where Claude Code
    # parses it.
    # Both array forms below are the bash-3.2-safe ones: under `set -u`,
    # bash before 4.4 (macOS ships 3.2) errors on expanding an empty array,
    # and every current call site passes no $3.
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

# version-guard denies an Edit that changes .version.
echo "=== version-guard (Edit version change: deny) ==="
run_guard "$(jq -nc --arg cwd "$proj" --arg fp "$proj/.claude-plugin/plugin.json" \
    '{cwd:$cwd, tool_name:"Edit", tool_input:{file_path:$fp, old_string:"\"version\": \"1.2.3\"", new_string:"\"version\": \"1.3.0\""}}')"
assert_deny "version-guard Edit-bump"

# The shortest edit that bumps the version replaces the value alone and
# repeats no "version" key, so a guard that pattern-matches new_string for
# one lets it straight through.
echo "=== version-guard (Edit bare version value: deny) ==="
run_guard "$(jq -nc --arg cwd "$proj" --arg fp "$proj/.claude-plugin/plugin.json" \
    '{cwd:$cwd, tool_name:"Edit", tool_input:{file_path:$fp, old_string:"1.2.3", new_string:"9.9.9"}}')"
assert_deny "version-guard Edit-bare-value"

# version-guard allows an Edit that touches plugin.json without changing version.
echo "=== version-guard (Edit unrelated field: allow) ==="
run_guard "$(jq -nc --arg cwd "$proj" --arg fp "$proj/.claude-plugin/plugin.json" \
    '{cwd:$cwd, tool_name:"Edit", tool_input:{file_path:$fp, old_string:"\"license\": \"MIT\"", new_string:"\"license\": \"Apache-2.0\""}}')"
assert_allow "version-guard Edit-unrelated"

# version-guard denies a Write whose content changes .version.
echo "=== version-guard (Write version change: deny) ==="
new_content="$(jq -c '.version="9.9.9"' "$proj/.claude-plugin/plugin.json")"
run_guard "$(jq -nc --arg cwd "$proj" --arg fp "$proj/.claude-plugin/plugin.json" --arg c "$new_content" \
    '{cwd:$cwd, tool_name:"Write", tool_input:{file_path:$fp, content:$c}}')"
assert_deny "version-guard Write-bump"

# version-guard ignores Edits to unrelated files.
echo "=== version-guard (unrelated file: allow) ==="
run_guard "$(jq -nc --arg cwd "$proj" --arg fp "$proj/README.md" \
    '{cwd:$cwd, tool_name:"Edit", tool_input:{file_path:$fp, old_string:"a", new_string:"b"}}')"
assert_allow "version-guard unrelated-file"

# The payload `cwd` tracks the Bash tool's shell and drifts with `cd` or
# /add-dir. Locating the manifest from it disables the guard silently, so
# the drifted value must not change the verdict.
echo "=== version-guard (drifted payload cwd: deny) ==="
mkdir -p "$proj/sub/dir"
run_guard "$(jq -nc --arg cwd "$proj/sub/dir" --arg fp "$proj/.claude-plugin/plugin.json" \
    '{cwd:$cwd, tool_name:"Edit", tool_input:{file_path:$fp, old_string:"1.2.3", new_string:"9.9.9"}}')"
assert_deny "version-guard drifted-cwd"

# tool_input.file_path is whatever the model emitted, and it is not always
# absolute -- a repo-root-relative form must still be recognised.
echo "=== version-guard (relative file_path: deny) ==="
run_guard "$(jq -nc --arg cwd "$proj" \
    '{cwd:$cwd, tool_name:"Edit", tool_input:{file_path:".claude-plugin/plugin.json", old_string:"1.2.3", new_string:"9.9.9"}}')"
assert_deny "version-guard relative-path"

# BSD/macOS realpath has no -m. A guard built on it gets two empty strings,
# compares them equal, and fires on files that are not the manifest. The
# stub makes Linux CI reproduce that, so the fix stays fixed.
echo "=== version-guard (BSD realpath, unrelated file: allow) ==="
stubdir="$proj/stubbin"
mkdir -p "$stubdir"
real_realpath="$(command -v realpath || true)"
# Unquoted heredoc: $real_realpath is baked in now, \$@ is left for run time.
cat > "$stubdir/realpath" <<EOF
#!/bin/sh
for a in "\$@"; do
    case "\$a" in -m) echo 'realpath: illegal option -- m' >&2; exit 1 ;; esac
done
exec ${real_realpath:-/bin/false} "\$@"
EOF
chmod 755 "$stubdir/realpath"
other_content="$(jq -nc '{name:"other", version:"9.9.9"}')"
guard_path="$stubdir:$PATH"
run_guard "$(jq -nc --arg cwd "$proj" --arg fp "$proj/other.json" --arg c "$other_content" \
    '{cwd:$cwd, tool_name:"Write", tool_input:{file_path:$fp, content:$c}}')"
guard_path="$PATH"
assert_allow "version-guard bsd-realpath-unrelated"

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
# released (release.sh:446-455) and a bare `just release` publishes $current
# rather than $proposed (release.sh:456-460), so in THIS branch every mention
# of the invocation routes the agent at something nobody asked for -- which
# is why the fix withheld the identifier instead of qualifying it. Asserted
# over the no-tags reason alone: the steady-state message names the recipe
# legitimately. Residual bound: prose that routes at the recipe without
# naming it ("when the release recipe runs") still passes here.
assert_not_contains "$reason" "just release" \
    "version-guard no-tags reason: initial-release branch names no recipe invocation"

# Slice 3: only the agent channel (permissionDecisionReason) may branch on
# release state. systemMessage is a factual one-liner, true in both states,
# so it must come out byte-identical for the same payload whichever fixture
# answers it.
tagless_sysmsg="$(jq -r '.systemMessage' <<<"$guard_out")"

echo "=== version-guard (v1.2.3 tag: steady-state wording) ==="
run_guard "$(jq -nc --arg cwd "$git_tagged_proj" --arg fp "$git_tagged_proj/.claude-plugin/plugin.json" \
    '{cwd:$cwd, tool_name:"Edit", tool_input:{file_path:$fp, old_string:"1.2.3", new_string:"9.9.9"}}')" \
    "$git_tagged_proj"
assert_deny "version-guard tagged-steady"
reason="$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<<"$guard_out")"
assert_contains "$reason" "last released version" "version-guard tagged-steady reason: last-released wording"
assert_not_contains "$reason" "never been released" "version-guard tagged-steady reason: no never-released wording"
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

# Slice 5: the guard clears repo-local GIT_* variables before listing tags,
# so a leaked GIT_DIR (e.g. a `claude` process started from inside a git
# hook) cannot redirect the listing at a different, tagged repository.
# $git_tagged_proj is reused as "a second fixture carrying v1.2.3" -- it
# already is exactly that, honestly, for the fixture built for slice 3/4.
echo "=== version-guard (leaked GIT_DIR cleared: initial-release wording) ==="
run_guard "$(jq -nc --arg cwd "$git_proj" --arg fp "$git_proj/.claude-plugin/plugin.json" \
    '{cwd:$cwd, tool_name:"Edit", tool_input:{file_path:$fp, old_string:"1.2.3", new_string:"9.9.9"}}')" \
    "$git_proj" "GIT_DIR=$git_tagged_proj/.git"
assert_deny "version-guard git-dir-leak"
reason="$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<<"$guard_out")"
assert_contains "$reason" "never been released" \
    "version-guard git-dir-leak reason: never-released wording despite leaked GIT_DIR"
assert_not_contains "$reason" "last released version" \
    "version-guard git-dir-leak reason: no last-released wording despite leaked GIT_DIR"

# Slice 6: a failed listing is not an empty one. With `git` stubbed to exit
# 127 (simulating it being absent), the tagless fixture must still deny with
# the steady-state wording -- the restrictive answer to "don't know" per
# decision 2 -- and empty stderr, proving the 2>/dev/null on the listing
# does not leak the stub's own noise. It is the tagless fixture that
# discriminates here: an implementation folding listing failure into
# emptiness would answer initial-release, same as the no-tags scenario
# above.
echo "=== version-guard (git listing fails: steady-state wording, empty stderr) ==="
guard_path="$guard_stub127_dir:$PATH"
run_guard "$(jq -nc --arg cwd "$git_proj" --arg fp "$git_proj/.claude-plugin/plugin.json" \
    '{cwd:$cwd, tool_name:"Edit", tool_input:{file_path:$fp, old_string:"1.2.3", new_string:"9.9.9"}}')" \
    "$git_proj"
guard_path="$PATH"
assert_deny "version-guard git-listing-failure"
reason="$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<<"$guard_out")"
assert_contains "$reason" "last released version" \
    "version-guard git-listing-failure reason: steady-state wording despite failed listing"
assert_not_contains "$reason" "never been released" \
    "version-guard git-listing-failure reason: no never-released wording despite failed listing"

# A failing *filter* is not an empty one either. The scenario above covers a
# failing listing; this one covers `grep` itself failing (exit 2), which the
# guard folds into the same restrictive answer -- only status 1, "no match",
# counts as a real empty result. The discriminating fixture here is the
# TAGGED one: with the fold dropped, a filter failure reads as "no match",
# and a plugin that has released is told "this plugin has never been
# released, $current is what the initial release will publish" -- the exact
# failure this branch exists to prevent. Measured under that mutation: the
# tagged fixture answers initial-release and every other scenario in this
# file stays green, which is why this one has to exist.
echo "=== version-guard (semver filter fails: steady-state wording) ==="
guard_path="$guard_stubgrep_dir:$PATH"
run_guard "$(jq -nc --arg cwd "$git_tagged_proj" --arg fp "$git_tagged_proj/.claude-plugin/plugin.json" \
    '{cwd:$cwd, tool_name:"Edit", tool_input:{file_path:$fp, old_string:"1.2.3", new_string:"9.9.9"}}')" \
    "$git_tagged_proj"
guard_path="$PATH"
assert_deny "version-guard filter-failure"
reason="$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<<"$guard_out")"
assert_contains "$reason" "last released version" \
    "version-guard filter-failure reason: steady-state wording despite failed filter"
assert_not_contains "$reason" "never been released" \
    "version-guard filter-failure reason: no never-released wording despite failed filter"

market="$proj/marketplace.json"

# check-version skips non-fatally when MARKETPLACE_DIR is unset and no
# explicit marketplace path is given.
echo "=== check-version (MARKETPLACE_DIR unset: skip) ==="
set +e
out="$(env -u MARKETPLACE_DIR bash toolkit/check-version.sh "$proj/.claude-plugin/plugin.json" 2>&1)"
rc=$?
set -e
assert_eq "$rc" "0" "check-version MARKETPLACE_DIR-unset exit code"
echo "$out" | grep -q "MARKETPLACE_DIR not set" \
    || fail "check-version did not report MARKETPLACE_DIR unset"

# check-version skips non-fatally when the marketplace file doesn't exist.
echo "=== check-version (marketplace.json missing: skip) ==="
set +e
out="$(bash toolkit/check-version.sh "$proj/.claude-plugin/plugin.json" "$proj/no-such-marketplace.json" 2>&1)"
rc=$?
set -e
assert_eq "$rc" "0" "check-version missing-marketplace exit code"

# check-version skips non-fatally when the plugin has no marketplace entry
# yet (pre-first-publication), rather than failing.
echo "=== check-version (no entry: skip) ==="
jq -n '{plugins: []}' > "$market"
set +e
out="$(bash toolkit/check-version.sh "$proj/.claude-plugin/plugin.json" "$market" 2>&1)"
rc=$?
set -e
assert_eq "$rc" "0" "check-version no-entry exit code"
echo "$out" | grep -q "no fixture entry" \
    || fail "check-version did not report the missing entry"

# check-version passes when plugin.json and the marketplace entry agree,
# reading the plugin name from plugin.json rather than a hardcoded name.
echo "=== check-version (in sync: pass) ==="
jq -n '{plugins: [{name: "fixture", version: "1.2.3"}]}' > "$market"
set +e
out="$(bash toolkit/check-version.sh "$proj/.claude-plugin/plugin.json" "$market" 2>&1)"
rc=$?
set -e
assert_eq "$rc" "0" "check-version in-sync exit code"
echo "$out" | grep -q "in sync (1.2.3)" \
    || fail "check-version did not report in sync"

# check-version fails when plugin.json and the marketplace entry disagree.
echo "=== check-version (drift: fail) ==="
jq -n '{plugins: [{name: "fixture", version: "1.2.2"}]}' > "$market"
set +e
out="$(bash toolkit/check-version.sh "$proj/.claude-plugin/plugin.json" "$market" 2>&1)"
rc=$?
set -e
assert_eq "$rc" "1" "check-version drift exit code"
echo "$out" | grep -q "version drift" \
    || fail "check-version did not report drift"

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nall hook scenarios passed\n'
