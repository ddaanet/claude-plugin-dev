# Shell audit — shipped toolkit scripts (2026-09-01)

Scope: `toolkit/install.sh`, `toolkit/update.sh`, `toolkit/release.sh`,
`toolkit/check-version.sh`, `toolkit/version-guard.sh`, read whole. Target
class is bugs ShellCheck cannot see: GNU/BSD flag divergence, `set -e` blind
spots, dishonest success reporting, hook-channel semantics, path drift.

Every finding below was reproduced. Constructs I suspected and then *disproved*
are in "Checked and clean" at the end, so silence there means covered, not
skipped.

**10 confirmed defects. 7 latent.**

---

## Confirmed defects

### 1. `install.sh:133` — a consumer's `.claude/settings.json` is silently replaced wholesale, losing every other setting

**Trigger.** Any existing `.claude/settings.json` holding a `hooks.PreToolUse`
entry with no `matcher` key. That is legal Claude Code configuration — a
matcher-less entry matches all tools — and is what most hand-written PreToolUse
blocks look like.

**Mechanism.** The jq program at `install.sh:122-132` runs
`select(.matcher | test("Write|Edit"))`. On a matcher-less entry `.matcher` is
`null`, and jq aborts:

```
jq: error: null (null) cannot be matched, as it is not a string
```

exit status 5. `2>/dev/null` on line 133 swallows the diagnosis, and the `||`
fallback on the same line writes a document containing *only* the version-guard
hook. `cmp -s` on line 138 sees a difference, line 139 `mv`s it into place.

**Observable behaviour.** Reproduced against a settings file holding
`permissions`, `env`, `statusLine` and one existing PreToolUse hook:

```
before: {"permissions":…,"env":…,"statusLine":…,"hooks":{"PreToolUse":[{"hooks":[{"command":"my-important-hook"}]}]}}
after:  {"hooks":{"PreToolUse":[{"matcher":"Write|Edit","hooks":[{"command":"bash ${CLAUDE_PROJECT_DIR}/plugin-dev/version-guard.sh"}]}]}}
```

The consumer's permissions, env, status line and their own hook are gone. The
script then prints `claude-plugin-dev: installed.` — a success message on a path
where the reported operation destroyed data. The `jq empty` pre-flight on
line 52 does not catch it: the file is perfectly valid JSON.

**Minimal fix.** Two changes, both needed. Make the select null-safe, and stop
using `||` as a file-existence test:

```sh
if [ -f "$settings" ]; then
    jq --arg cmd "$hook_cmd" '
      if ([.hooks.PreToolUse[]? | select((.matcher // "") | test("Write|Edit"))
           | .hooks[]? | select(.command == $cmd)] | length > 0)
      then . else … end
    ' "$settings" > "$tmp" \
        || { echo "error: could not rewrite $settings" >&2; exit 1; }
else
    jq --arg cmd "$hook_cmd" -n '{hooks: {PreToolUse: […]}}' > "$tmp"
fi
```

Dropping the `2>/dev/null` is part of the fix, not a nicety — it is what made
this silent.

---

### 2. `version-guard.sh:57-59` — the hook JSON goes to stderr with `exit 2`, so Claude Code never parses it and the human channel never fires

**Trigger.** Every deny.

**Mechanism.** Claude Code parses a hook's **stdout** as JSON, and **only on
exit 0**. On `exit 2` the **stderr** text is fed to the model verbatim; it is
not parsed. The script writes its JSON to stderr (`>&2` on line 58) and then
`exit 2`.

**Observable behaviour.** Reproduced with the repo's own Edit-bump payload —
stdout is empty and stderr carries:

```
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"plugin.json version edit refused: 1.2.3 -> 9.9.9.\n\nThe manifest version is…"},"systemMessage":"version-guard: blocked plugin.json version edit (1.2.3 -> 9.9.9)"}
```

So: the edit *is* blocked (exit 2 does that on its own), but
`permissionDecision`, `permissionDecisionReason` and `systemMessage` are inert
as structured fields. The human never sees the one-line notice, and the agent
receives a single-line JSON blob with literal `\n` escapes instead of the
formatted refusal. The dual-channel design at `docs/design.md:273-287` is not
delivered by the code.

`tests/hook-test.sh:45,72` cannot catch this: both capture with `2>&1`, so the
assertions pass identically whichever stream the JSON lands on.

**Minimal fix.** Emit on stdout and exit 0 — `permissionDecision: "deny"` on
stdout with exit 0 blocks the call exactly as `exit 2` does, and additionally
carries `systemMessage`:

```sh
jq -nc --arg r "$agent_reason" --arg s "$human_msg" '…'
exit 0
```

Then change the tests to assert the JSON is on **stdout** (`2>/dev/null`, not
`2>&1`) — otherwise the assertion cannot distinguish the fixed script from the
broken one.

---

### 3. `version-guard.sh:19` — `realpath -m` is GNU-only; on macOS the hook fires on files that are not the manifest

**Trigger.** Any Write or Edit in a plugin repo, on macOS.

**Mechanism.** BSD/macOS `realpath` takes `[-q] path ...` and has no `-m`
(and no `realpath` at all before macOS 12.3). Both substitutions on line 19
therefore produce empty stdout. `[[ "" == "" ]]` is **true**, so the
`|| exit 0` never fires and the hook falls through to the version comparison
for *every* file. Errexit does not save it: the substitutions sit inside a
`[[ … ]]` that is part of an `||` list, where errexit is suspended, and a
failing command substitution never triggers errexit regardless.

**Observable behaviour.** On macOS, in any repo with
`.claude-plugin/plugin.json`, writing any file whose content carries a
`"version": "x.y.z"` differing from the manifest — a `package.json`, a test
fixture, a `marketplace.json`, a JSON snippet in docs — is refused with
`plugin.json version edit refused: <manifest ver> -> <that file's ver>`. The
guard names a file the agent was not editing.

This is the highest-blast-radius portability defect here because the toolkit
ships explicitly for macOS *and* Linux consumers, and Linux CI cannot see it.

**Minimal fix.** The manifest path is constructed by the script, not
user-supplied, so symlink resolution buys nothing. Absolutise both sides in
shell and string-compare:

```sh
abspath() { case "$1" in /*) printf '%s\n' "$1" ;; *) printf '%s\n' "${PWD%/}/$1" ;; esac; }
[[ "$(abspath "$file_path")" == "$(abspath "$manifest")" ]] || exit 0
```

Pair it with a PATH-shadowing regression test that makes `realpath` reject `-m`,
so the BSD behaviour is enforced from Linux.

---

### 4. `version-guard.sh:14-17` — the manifest is located from the payload `cwd`, so the guard disables itself whenever the Bash shell's cwd has drifted

**Trigger.** A session in which the Bash tool's persistent shell has `cd`-ed
into a subdirectory, or `/add-dir` has moved focus to another repo.

**Mechanism.** `cwd` in a hook payload tracks the Bash tool's persistent shell
working directory, not the project's configured root. Line 17 builds
`manifest="$cwd/.claude-plugin/plugin.json"`; line 18 `[[ -f "$manifest" ]] ||
exit 0`. Once cwd is a subdirectory the manifest is not there, the hook exits 0,
and the version edit is allowed. `CLAUDE_PROJECT_DIR` is exported to hooks and
is stable for the session; the script never reads it, even though
`install.sh:47` wires the hook command around exactly that variable.

**Observable behaviour.** A silent, complete bypass of the guard — no message on
either channel, because exit 0 is the "not my file" path.

**Minimal fix.**

```sh
cwd="${CLAUDE_PROJECT_DIR:-$PWD}"
```

and delete the `jq -r '.cwd // ""'` read. Falling back to the payload `cwd`
reintroduces the drift.

---

### 5. `version-guard.sh:33-35` — the Edit branch only matches when `new_string` repeats the `"version"` key, so the most natural edit shape passes

**Trigger.** An `Edit` with `old_string: "1.2.3"`, `new_string: "9.9.9"` — i.e.
replacing just the version *value*, which is the shortest unique string and the
form an agent reaches for first.

**Mechanism.** Line 34 greps `new_string` for `"version"[[:space:]]*:[[:space:]]*"[^"]+"`.
A `new_string` of `9.9.9` has no `"version"` key, so `version_line` is empty,
`proposed` stays empty, and line 40's `[[ -z "$proposed" … ]] && exit 0` allows
the edit.

**Observable behaviour.** Reproduced against a fixture manifest at `1.2.3`:

```
Edit old_string="1.2.3" new_string="9.9.9"          -> exit 0   (allowed)
Edit old_string="\"version\": \"1.2.3\"" new=…9.9.9 -> exit 2   (blocked)
```

Same semantic edit, opposite verdicts.

**Minimal fix.** Stop pattern-matching the fragment. Apply the Edit to the
manifest text and re-read `.version` from the result, which also removes the
grep/sed asymmetry documented at `docs/design.md:289-292`:

```sh
Edit)
  old_string="$(jq -r '.tool_input.old_string // ""' <<<"$input")"
  patched="${manifest_text/"$old_string"/"$new_string"}"
  proposed="$(printf '%s' "$patched" | jq -r '.version // ""' 2>/dev/null || echo "")"
  ;;
```

If that is too much, the cheap partial cover is to also treat an Edit whose
`old_string` contains the current version string as a version edit.

---

### 6. `release.sh:166` — `git describe --tags --abbrev=0` returns the nearest tag of *any* name, and only tags reachable from HEAD

**Trigger.** A plugin repo carrying any non-`v*` tag (a `nightly-*`, a
`release-candidate`, a docs tag) newer than the last release tag — or a release
tag on a branch since abandoned.

**Mechanism.** `git describe --tags --abbrev=0` is unfiltered and
distance-ordered, not version-ordered. `sed 's/^v//'` leaves a non-`v` tag
untouched, and the comparison on line 167 then fails.

**Observable behaviour.** Reproduced in a scratch repo with `v1.0.0` on the
first commit and `nightly-2026` on the second:

```
git describe --tags --abbrev=0  ->  nightly-2026
git tag --list 'v*'             ->  v1.0.0
```

`release_preflight` dies with
`plugin.json version (1.0.0) does not match latest tag (vnightly-2026)` and the
hint on line 169-170 tells the user to "revert any manual version bump" — a
bump they never made. Release is blocked with an unactionable diagnosis.

Note the internal inconsistency: the comment at `release.sh:148-150` explains
why `git tag --list 'v*'` is used instead of `describe` for the first-release
check, and then line 166 uses `describe` anyway for the drift check, inheriting
both flaws it warns about.

**Minimal fix.**

```sh
latest_tag=$(git tag --list 'v*' --sort=-v:refname | sed -n '1s/^v//p')
```

`sed -n '1s…p'` rather than `head -1` keeps the reader from exiting early, so
`pipefail` does not report SIGPIPE on a repo with many tags.

---

### 7. `release.sh:336-352` — a detached-HEAD marketplace repo fails the push *after* the plugin release is already public

**Trigger.** `$MARKETPLACE_DIR` sitting on a detached HEAD — a bisect, a
`git checkout <tag>`, a submodule-style pinned checkout.

**Mechanism.** Line 336 `mp_branch=$(… symbolic-ref -q --short HEAD || echo "")`
yields the empty string. Line 337 then runs
`git ls-remote origin "refs/heads/"`, which matches no ref, so `mp_remote_head`
is empty, never equals `mp_local_head`, and line 352 runs `git push` on a
detached HEAD — `fatal: You are not currently on a branch`, errexit, exit.

**Observable behaviour.** The plugin's commit, tag, pushed tag and GitHub
release have all landed by then; only the marketplace bump has not. Recovery is
to check out a branch in the marketplace repo and run `just resume-release`,
which the failure message does not say. `common_preflight` already validates
`$MARKETPLACE_DIR` in three other ways and could have caught this before
anything was published.

**Minimal fix.** In `common_preflight`, next to the existing
`tree_is_clean "$MARKETPLACE_DIR"` check:

```sh
git -C "$MARKETPLACE_DIR" symbolic-ref -q --short HEAD >/dev/null \
    || die "$MARKETPLACE_DIR is on a detached HEAD — check out its branch first"
```

---

### 8. `install.sh:100` — rewriting an existing justfile drops its trailing newline

**Trigger.** Installing into a plugin that already has a `justfile` without the
import line — the ordinary re-wire path.

**Mechanism.** `$(cat justfile)` strips *all* trailing newlines (POSIX command
substitution), and the format string `'%s\n\n%s'` supplies none.

**Observable behaviour.** Reproduced: a 24-byte justfile ending `echo hi\n\n`
becomes a 56-byte file ending `echo hi` with no newline at all. The consumer's
`git diff` shows `\ No newline at end of file` on a file the installer claims
only to have added a line to, and the next hand edit re-adds it as a second
diff hunk. Any trailing blank lines are also collapsed.

**Minimal fix.** `printf '%s\n\n%s\n'` on line 100.

---

### 9. `install.sh:139` and `release.sh:320` — `mktemp` + `mv` leaves the destination at mode 0600

**Trigger.** Every install, and every marketplace bump.

**Mechanism.** `mktemp` creates its file 0600 by design; `mv` carries that mode
onto the destination, replacing whatever the file had.

**Observable behaviour.** Reproduced: a 0644 `settings.json` comes out
`-rw-------`. For `marketplace.json` git does not record the mode so the repo is
unaffected, but the working file changes under the user. For
`.claude/settings.json` in a shared or group-readable checkout it is a real
permission change nobody asked for.

**Minimal fix.** `chmod 644 "$tmp"` before the `mv`, or write through the
existing inode with `cat "$tmp" > "$settings" && rm -f "$tmp"` — the latter also
preserves ownership and any ACL.

---

### 10. `install.sh:52` — `2>/dev/null` on the pre-flight `jq empty` discards the only actionable part of the error

**Trigger.** An existing `.claude/settings.json` with a syntax error.

**Mechanism.** `jq empty "$settings" 2>/dev/null` throws away jq's
`parse error: … at line 14, column 3`, and the script prints only
`error: $settings exists but is not valid JSON. Fix it first.`

**Observable behaviour.** The user is told a file is broken and given no
location. Same class as #1 but non-destructive.

**Minimal fix.** Drop the redirection — jq's message on stderr *is* the useful
half of the report.

---

## Latent — real, but not reachable by a consumer today

- **`update.sh:82-98`, the whole migration-notes block, is dead code.**
  `toolkit/migrations/` does not exist in this repo, so no dist tag ships it and
  `[ -d "$TOOLKIT_PREFIX/migrations" ]` is always false. The code itself is
  sound (the unmatched-glob guard at line 89 is correct, and `printf '%s\n'`
  always terminates the last record so the `read` loop drops nothing) — it is
  simply never exercised. One asymmetry to fix before the first note ships:
  line 82's `[ -n "$new_version" ]` skips *silently* when the incoming tag has
  no `VERSION` file, whereas the missing-*old*-version case at line 83 does
  print a "review by hand" note. The two cases deserve the same treatment.

- **`release.sh:109` — a manifest with no `.name`.** `jq -r .name` prints the
  literal `null`, so `plugin_name="null"`, the marketplace lookup finds no
  entry, and `bump_marketplace`'s create path adds an entry literally named
  `null`. Requires a malformed manifest.

- **`release.sh:173-180` — a two-component manifest version.** With `.version`
  of `1.2`, `as [$maj,$min,$pat]` binds `$pat` to `null`, and jq's `null + 1`
  is `1`, so a patch bump yields `1.2.1`. Silently plausible-looking rather than
  an error. Requires a non-semver manifest.

- **`install.sh:88` — `git diff --quiet HEAD` in a repo with no commits.** An
  unborn HEAD makes git exit non-zero with `fatal: ambiguous argument 'HEAD'`,
  and the script reports `uncommitted changes`. The install is correctly
  refused; the reason given is wrong. Reachable only when someone runs
  `install.sh` in a freshly `git init`-ed plugin.

- **`release.sh:235`, `:263`, `:337` — `git ls-remote … | cut -f1` under
  `pipefail`.** A network or auth failure makes the pipeline fail, the plain
  assignment propagates it, and errexit kills the script with only git's own
  stderr and none of the toolkit's `resume-release` guidance. Not corrupting —
  the local commit and tag survive and resume works — but the user has to know
  that unaided.

- **`check-version.sh:44` — a marketplace.json with no `.plugins` key.** jq
  exits 5 on `Cannot iterate over null`, errexit propagates it, and
  `release.sh:131` then prints `fix the version drift above before releasing`
  for what was actually a malformed marketplace file.

- **`release.sh:316` — `cmp -s` against jq's re-serialisation.** jq always
  emits 2-space-indented JSON. A marketplace.json kept in any other style is
  reformatted wholesale, so every release commit carries a whole-file diff. Not
  a defect today (the marketplace repo is jq-formatted), but it makes the
  "no-op rewrite must not touch the file" guarantee on lines 312-315 conditional
  on formatting that nothing enforces.

---

## Checked and clean

Constructs I specifically suspected, tested, and found correct — so absence from
the findings above is coverage, not an oversight.

**`set -e` blind spots.** Verified on bash 5.2 that a false `A && B` list does
*not* trigger errexit, at top level with code following, and inside a `case`
arm. That clears `version-guard.sh:35` (`[[ -n "$version_line" ]] && proposed=…`),
`version-guard.sh:40` (`[[ … ]] && exit 0`), and `release.sh:108`
(`[ "$mode" = "release" ] && check_marketplace_writable`). The explanatory
comment at `release.sh:105-107` is accurate as written.

**`local v=$(cmd)`.** Not present anywhere. `release.sh:52-53` and `:200,211`
correctly split the `local` declaration from the assignment.

**Pipefail concatenation in `$(pipeline || fallback)`.** `release.sh:92` is the
risky shape, but verified safe: when `git symbolic-ref` fails it writes nothing
to stdout, so the capture is `main`, not `<partial output>\nmain`. (The
contrasting concatenating shape reproduces as expected, which is what makes this
one provably fine.) The comment at `release.sh:89-91` explaining why
`symbolic-ref` replaced `rev-parse` describes a real bug that was correctly
fixed.

**Empty-array expansion under `set -u`.** `install.sh:145` `${#changed[@]}` and
`:149` `"${changed[@]}"`. Verified 0 with no `unbound variable` on bash 5.2, and
the `"${changed[@]}"` expansion is inside the non-empty branch, which is the
form that broke on bash < 4.4. **Caveat: I could not test bash 3.2 directly** —
the bash 4.4 fix is documented for `${a[@]}`/`${a[*]}`, not `${#a[@]}`, so I
believe this is fine on macOS, but it is the one item here I could not
empirically confirm on the target platform. Cheap to make moot if wanted.

**GNU-only commands and flags.** None of `paste -sd:`, `sed -i`, `date -d`,
`stat -c`, `grep -P`, `find -printf`, `timeout`, `readlink -f`, `head -n -1`,
`mapfile`/`readarray`, `declare -A`, `${var,,}`, `wait -n`,
`shopt -s inherit_errexit`, or `getopt(1)` appears in any of the five files.
`realpath -m` (finding #3) is the sole instance of the class.

**`sort -V`** at `update.sh:79,96` — present on both GNU sort and macOS/BSD sort,
so not a portability defect.

**`sed -E`** (`release.sh:299`) and **`grep -oE`** (`version-guard.sh:34`) — both
portable; neither uses GNU-only `-r` or `-P`, and macOS grep does support `-o`.

**`mktemp` usage.** Every call is bare `mktemp` / `mktemp -d` or a full template
with six trailing `X`s (`release.sh:53`). No `-t`, whose semantics differ between
GNU and BSD.

**`unset CDPATH`.** Present in `release.sh:20` and `check-version.sh:19` — the
only two scripts that use `$(cd … && pwd)`. `install.sh`, `update.sh` and
`version-guard.sh` use no `cd` at all, so its absence there is correct.

**`read` discipline.** `update.sh:88`'s `while IFS= read -r note` is fed by
`printf '%s\n'`, which always terminates the final record — no dropped last
line, and the `|| [ -n "$line" ]` guard is genuinely unnecessary here.
`version-guard.sh:42`'s `read -r -d '' … <<EOF || true` is the correct heredoc
idiom (`read -d ''` returns 1 at EOF having set the variable).

**Quoting and word splitting.** Every parameter expansion in all five files is
quoted. The single unquoted expansion is the deliberate glob at `update.sh:96`,
whose no-match-stays-literal case is handled by `[ -f "$note" ] || continue` on
line 89. No `for f in $(...)`. Paths with spaces survive: `tree_is_clean` reads
the submodule path with `git config --get` (single key, returned whole) rather
than splitting `--get-regexp` output, which the comment at `release.sh:68-69`
calls out correctly.

**Arithmetic on untrusted input.** No `$((…))` anywhere. Version arithmetic is
done in jq, where `tonumber` rejects non-numeric components loudly rather than
evaluating them. No `$((0$n))` octal exposure.

**Git environment leakage.** None of the five scripts is a git hook, so no
repo-local `GIT_*` variables are inherited, and the `git -C "$MARKETPLACE_DIR"`
calls (`release.sh:321,328,331,336,337,338,352`) are safe as written. The
submodule-escape gotcha does not apply: `tree_is_clean` never `-C`s into the
memory submodule, it excludes the path via a `:(exclude)` pathspec from the
parent.

**Dist-tag resolution** (`install.sh:63`, `update.sh:25`). `--refs` drops peeled
`^{}` entries so `sed -n '1s|.*/||p'` sees only real tags; git's versionsort
handles the `dist-v` prefix and multi-digit components (`dist-v0.10.0` sorts
above `dist-v0.9.0`); and `sed -n '1s…p'` reads to EOF rather than exiting
early, so `pipefail` cannot report a spurious SIGPIPE. A failing `ls-remote`
propagates through the plain assignment to errexit, which is the honest
behaviour even though the tailored "could not resolve a dist tag" message is
then unreachable for that case.

**Annotated-tag comparison** (`release.sh:263-264`). `git ls-remote origin
refs/tags/X` does not also match the peeled `refs/tags/X^{}`, and
`git rev-parse X` on an annotated tag returns the tag object — so both sides of
the comparison are the tag object sha and the "refusing to move a published tag"
guard compares like with like.

**Commit-gate rollback** (`release.sh:222-227`). `git checkout HEAD -- "$manifest"`
resets both the index and the working tree for that path, so a refused
pre-commit gate really does leave the tree as the run found it, as the comment
claims.

**Honest reporting.** `release.sh`'s final `note "Release $tag complete"` is
genuinely unreachable unless every step succeeded, because errexit is live and
each step either dies with a message or returns 0. The only success-message
defect found is #1, in `install.sh`.
