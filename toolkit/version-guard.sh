#!/usr/bin/env bash
# PreToolUse hook (Write|Edit) for the plugin manifest.
# Refuses any edit that changes plugin.json's .version. The release
# recipe owns version bumps: once a plugin has released, manual edits
# desync the manifest from the latest tag and only get caught at release
# time; before a first release there is no tag to desync from, but the
# recipe is still the only place a version is meant to change.
#
# Mechanical: agent is not involved.
set -euo pipefail

input="$(cat)"
file_path="$(jq -r '.tool_input.file_path // ""' <<<"$input")"
[[ -n "$file_path" ]] || exit 0

# CLAUDE_PROJECT_DIR, not the payload `cwd`: `cwd` tracks the Bash tool's
# persistent shell and drifts with a `cd` or an /add-dir. Locating the
# manifest from a drifted cwd finds nothing and exits 0 -- a silent, total
# bypass. install.sh wires the hook command around CLAUDE_PROJECT_DIR for
# the same reason. No fallback to the payload cwd: that reintroduces it.
project="${CLAUDE_PROJECT_DIR:-$PWD}"
manifest="${project%/}/.claude-plugin/plugin.json"
[[ -f "$manifest" ]] || exit 0

# Absolutise in shell rather than with `realpath -m`: BSD/macOS realpath
# has no -m, so both substitutions come back empty, `[[ "" == "" ]]` is
# true, and the guard fires on every file instead of just the manifest.
# The manifest path is built here rather than supplied, so symlink
# resolution buys nothing. tool_input.file_path is whatever the model
# emitted and is not always absolute, and a relative one may be meant
# against either root, so a match on either counts.
abspath() {
    local root="$1" p="${2#./}"
    case "$p" in
      /*) printf '%s\n' "$p" ;;
      *)  printf '%s\n' "${root%/}/$p" ;;
    esac
}
[[ "$(abspath "$project" "$file_path")" == "$manifest" \
   || "$(abspath "$PWD" "$file_path")" == "$manifest" ]] || exit 0

current="$(jq -r '.version // ""' "$manifest" 2>/dev/null || echo "")"
[[ -n "$current" ]] || exit 0  # manifest unparseable; let the edit through.

tool_name="$(jq -r '.tool_name // ""' <<<"$input")"

proposed=""
case "$tool_name" in
  Write)
    proposed="$(jq -r '.tool_input.content // ""' <<<"$input" \
      | jq -r '.version // ""' 2>/dev/null || echo "")"
    ;;
  Edit)
    # Apply the edit to the manifest and re-read .version from the result,
    # instead of pattern-matching new_string for a "version" key. The
    # shortest edit that bumps the version is old_string "1.2.3" ->
    # new_string "9.9.9", which repeats no key to match, and it is the
    # form an agent reaches for first.
    old_string="$(jq -r '.tool_input.old_string // ""' <<<"$input")"
    new_string="$(jq -r '.tool_input.new_string // ""' <<<"$input")"
    if [[ -n "$old_string" ]]; then
      replace_all="$(jq -r 'if .tool_input.replace_all then "true" else "false" end' <<<"$input")"
      # jq's split/1 splits on a literal string, not a regex, so JSON
      # punctuation in old_string matches as written -- which a bash
      # ${text/pat/rep} would not, its pattern being a glob. `empty` when
      # old_string is absent from the manifest: that edit fails anyway.
      patched="$(jq -rn --arg t "$(cat "$manifest")" --arg o "$old_string" \
                        --arg n "$new_string" --argjson all "$replace_all" '
        ($t | split($o)) as $parts
        | if ($parts | length) < 2 then empty
          elif $all then ($parts | join($n))
          else $parts[0] + $n + ($parts[1:] | join($o))
          end')"
      proposed="$(jq -r '.version // ""' <<<"$patched" 2>/dev/null || echo "")"
    fi
    ;;
  *) exit 0 ;;
esac

[[ -z "$proposed" || "$proposed" == "$current" ]] && exit 0

# Whether this plugin has ever released, to pick the deny wording below.
# 2>/dev/null on the listing: on a CLAUDE_PROJECT_DIR that is not a git
# repository at all (the common case pre-release), git's "not a git
# repository" is an expected outcome here, not a diagnostic --
# tests/hook-test.sh's non-repo fixture asserts this hook's stderr stays
# empty. A CLAUDE_PROJECT_DIR that is not itself a repo but sits inside one
# lists the enclosing repo's tags instead; that only changes the wording
# below, never the deny decision already established above. Same semver
# filter release.sh's semver_tags uses, duplicated rather than sourced:
# release.sh runs its flow at top level and isn't written to be sourced.
# The trailing `|| true` absorbs a failed `git -C` (not a repository at
# all): pipefail propagates that failure through the grep stage even
# though the grep stage itself already turned "no match" into success, so
# without it `set -e` would abort the script here instead of falling
# through to the empty-listing branch below.
release_tags="$(git -C "$project" tag --list 'v*' --sort=-v:refname 2>/dev/null \
  | { grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' || [ "$?" -eq 1 ]; })" || true

if [[ -z "$release_tags" ]]; then
read -r -d '' agent_reason <<EOF || true
plugin.json version edit refused: $current -> $proposed.

This plugin has never been released -- no vX.Y.Z tag exists yet. The first
release will publish whatever plugin.json holds when
'just release {patch|minor|major}' runs; that recipe validates state,
bumps, commits, tags, and pushes in one step.

Do not bypass this guard, modify the recipe, or alter version state by
other means.
EOF
else
read -r -d '' agent_reason <<EOF || true
plugin.json version edit refused: $current -> $proposed.

The manifest version is the last released version. It is changed only by
'just release {patch|minor|major}', which validates state, bumps, commits,
tags, and pushes in one step. The release recipe also refuses if plugin.json
and the latest git tag disagree.

If the goal is to ship a release, invoke the recipe instead of editing this
file. Do not bypass this guard, modify the recipe, or alter version state by
other means.
EOF
fi

human_msg="version-guard: blocked plugin.json version edit ($current -> $proposed)"

# stdout and exit 0, not stderr and exit 2. Claude Code parses a hook's
# stdout as JSON, and only on exit 0. `permissionDecision: "deny"` there
# blocks the call exactly as exit 2 does, and additionally delivers
# systemMessage; on exit 2 the JSON is handed to the model as raw stderr
# text and the human channel never fires at all.
jq -nc --arg r "$agent_reason" --arg s "$human_msg" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}, systemMessage: $s}'
exit 0
