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
# Scope: how the guard lists tags -- the order of work, a leaked GIT_DIR, and a
# git or grep that fails. Its siblings version-guard-decision-test.sh and
# version-guard-wording-test.sh cover the decision and the wording.
#
# Usage: bash tests/version-guard-git-test.sh   (run from repo root)
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
proj="$(mktemp -d "${TMPDIR:-/tmp}/version-guard-git.XXXXXX")"
guard_err="$(mktemp "${TMPDIR:-/tmp}/version-guard-git.XXXXXX")"
# The fixtures are allocated here, ahead of the trap, so the trap can name
# them: under `set -u` a failure between the trap and a later assignment runs
# the trap with one unbound, which aborts it before the rm and leaks every
# temp dir. They are a repo with no tags, a repo tagged v1.2.3 (which the
# leaked-GIT_DIR scenario also points GIT_DIR at), a PATH stub directory for a
# `git` that exits 127, one for a `grep` that exits 2, and one for a recording
# `git`.
git_proj="$(mktemp -d "${TMPDIR:-/tmp}/version-guard-git.XXXXXX")"
git_tagged_proj="$(mktemp -d "${TMPDIR:-/tmp}/version-guard-git.XXXXXX")"
guard_stub127_dir="$(mktemp -d "${TMPDIR:-/tmp}/version-guard-git.XXXXXX")"
guard_stubgrep_dir="$(mktemp -d "${TMPDIR:-/tmp}/version-guard-git.XXXXXX")"
guard_recordgit_dir="$(mktemp -d "${TMPDIR:-/tmp}/version-guard-git.XXXXXX")"
guard_recordgit_log="$(mktemp "${TMPDIR:-/tmp}/version-guard-git.XXXXXX")"
trap 'rm -rf "$proj" "$guard_err" "$git_proj" "$git_tagged_proj" "$guard_stub127_dir" "$guard_stubgrep_dir" "$guard_recordgit_dir" "$guard_recordgit_log"' EXIT
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

# PATH stub for the git-tagged allow scenario (N5): a recording `git` that
# appends one line per invocation to $guard_recordgit_log before delegating
# to the real binary, so a scenario can assert on *whether* git ran, not
# only on the allow/deny decision -- the property under test is work
# ordering (the tag listing runs only after the early return at
# proposed==current), which the decision channel cannot observe: hoisting
# the listing above that return still allows correctly, byte-identical.
# Arguments are joined with an ASCII Unit Separator (octal 037), not a
# space, so an argument containing a literal space cannot be misread as an
# argument boundary by the substring assertion that reads this log.
# Residual bound: an argument containing a literal \037 byte -- none does,
# anywhere in this suite -- would still be ambiguous.
real_git="$(command -v git)"
cat > "$guard_recordgit_dir/git" <<EOF
#!/bin/sh
printf '%s\037' "\$@" >> "$guard_recordgit_log"
printf '\n' >> "$guard_recordgit_log"
exec "$real_git" "\$@"
EOF
chmod 755 "$guard_recordgit_dir/git"

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
# N5: no scenario above touches a real git repository (they all run against
# $proj, deliberately not a repo), so the property "the tag listing runs
# only after the early return at proposed==current" is unpinned -- a bare
# assert_allow cannot pin it, since the listing block absorbs every outcome
# into a variable, never exits non-zero, writes nothing to stdout and
# suppresses stderr. Run an allow scenario against $git_tagged_proj (a real
# repo) with the recording git stub first on PATH, and assert the log holds
# no `tag --list` invocation.
#
# Paired with a positive control over the SAME fixture, differing only in
# whether the edit changes .version -- and run first, so the negative reads a
# log the control has just proved is written. On its own the negative passes
# whenever the log is empty, which is also what an unwired stub looks like:
# nothing in the allow path invokes git, so a `guard_path` that stopped
# reaching the hook (or a stub that stopped being executable) would leave the
# assertion green while testing nothing. The control fails in exactly that
# state.
US="$(printf '\037')"
echo "=== version-guard (git-tagged repo, recording stub reaches the hook) ==="
guard_path="$guard_recordgit_dir:$PATH"
run_guard "$(jq -nc --arg cwd "$git_tagged_proj" --arg fp "$git_tagged_proj/.claude-plugin/plugin.json" \
    '{cwd:$cwd, tool_name:"Edit", tool_input:{file_path:$fp, old_string:"1.2.3", new_string:"9.9.9"}}')" \
    "$git_tagged_proj"
assert_deny "version-guard git-tagged-control"
assert_contains "$(cat "$guard_recordgit_log")" "tag${US}--list" \
    "version-guard git-tagged-control: the recording stub logged the deny path's tag listing"

echo "=== version-guard (git-tagged repo, unrelated field: allow, no tag listing) ==="
: >"$guard_recordgit_log"
run_guard "$(jq -nc --arg cwd "$git_tagged_proj" --arg fp "$git_tagged_proj/.claude-plugin/plugin.json" \
    '{cwd:$cwd, tool_name:"Edit", tool_input:{file_path:$fp, old_string:"\"license\": \"MIT\"", new_string:"\"license\": \"Apache-2.0\""}}')" \
    "$git_tagged_proj"
guard_path="$PATH"
assert_allow "version-guard git-tagged-unrelated"
assert_not_contains "$(cat "$guard_recordgit_log")" "tag${US}--list" \
    "version-guard git-tagged-unrelated: no git tag listing runs before the early return"

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

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nall version-guard git scenarios passed\n'
