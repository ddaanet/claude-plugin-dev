# Item 3.3 — execution report

`tests/version-guard-test.sh`: one allow scenario against `$git_tagged_proj`,
driven by a recording `git` stub, pinning the property that the tag listing runs
only after the `proposed == current` early return (N5).

## What changed

Three additions, all in the file's current glob-form idiom (Item 3.4 converts
these later, not this item):

1. **Fixture allocation** (near the other `mktemp -d` calls, ahead of the trap):

   ```sh
   guard_recordgit_dir="$(mktemp -d)"
   guard_recordgit_log="$(mktemp)"
   ```

   and added to the trap's `rm -rf` list alongside the existing temp paths.

2. **The recording stub**, built right after the `guard_stubgrep_dir/grep` stub:

   ```sh
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
   ```

3. **The scenario**, placed after the existing "v1.2.3 tag: steady-state
   wording" block (the only prior scenario against `$git_tagged_proj`), before
   the Slice 4 comment:

   ```sh
   # N5: no scenario above touches a real git repository (they all run against
   # $proj, deliberately not a repo), so the property "the tag listing runs
   # only after the early return at proposed==current" is unpinned -- a bare
   # assert_allow cannot pin it, since the listing block absorbs every outcome
   # into a variable, never exits non-zero, writes nothing to stdout and
   # suppresses stderr. Run an allow scenario against $git_tagged_proj (a real
   # repo) with the recording git stub first on PATH, and assert the log holds
   # no `tag --list` invocation.
   echo "=== version-guard (git-tagged repo, unrelated field: allow, no tag listing) ==="
   guard_path="$guard_recordgit_dir:$PATH"
   run_guard "$(jq -nc --arg cwd "$git_tagged_proj" --arg fp "$git_tagged_proj/.claude-plugin/plugin.json" \
       '{cwd:$cwd, tool_name:"Edit", tool_input:{file_path:$fp, old_string:"\"license\": \"MIT\"", new_string:"\"license\": \"Apache-2.0\""}}')" \
       "$git_tagged_proj"
   guard_path="$PATH"
   assert_allow "version-guard git-tagged-unrelated"
   US="$(printf '\037')"
   assert_not_contains "$(cat "$guard_recordgit_log")" "tag${US}--list" \
       "version-guard git-tagged-unrelated: no git tag listing runs before the early return"
   ```

**Whitespace bound**, stated in the stub's own comment (quoted above): args are
joined with the ASCII Unit Separator (octal 037), not a space, so an argument
containing a literal space cannot be misread as an argument boundary by the
substring assertion that reads the log; the residual gap (an argument literally
containing `\037`) is stated and does not occur anywhere in this suite's git
invocations.

Post-change, unmutated run:

```
$ bash tests/version-guard-test.sh 2>&1 | tail -8
=== version-guard (v1.2.3 tag: steady-state wording) ===
=== version-guard (git-tagged repo, unrelated field: allow, no tag listing) ===
=== version-guard (vnext/v1.2 tags only, no semver tag: initial-release wording) ===
=== version-guard (leaked GIT_DIR cleared: initial-release wording) ===
=== version-guard (git listing fails: steady-state wording, empty stderr) ===
=== version-guard (semver filter fails: steady-state wording) ===

all version-guard scenarios passed
```

## Gate 1 — the runbook's own gate

**Mutation:** hoisted the tag-listing block (the `GIT_DIR` unset through the
`grep_status` filter, `toolkit/version-guard.sh` lines 82-145) above the
`[[ -z "$proposed" || "$proposed" == "$current" ]] && exit 0` early return, by
moving that one-line early return to immediately after the filter block instead
(same effect: the listing now runs unconditionally, before the decision).

```
$ bash tests/version-guard-test.sh 2>&1 | tail -6
=== version-guard (v1.2.3 tag: steady-state wording) ===
=== version-guard (git-tagged repo, unrelated field: allow, no tag listing) ===
FAIL: version-guard git-tagged-unrelated: no git tag listing runs before the early return: expected NOT to contain 'tag--list', got '-C/tmp/claude-1000/tmp.iHADKqO8sjtag--listv*--sort=-v:refname'
=== version-guard (vnext/v1.2 tags only, no semver tag: initial-release wording) ===
=== version-guard (leaked GIT_DIR cleared: initial-release wording) ===
=== version-guard (git listing fails: steady-state wording, empty stderr) ===
=== version-guard (semver filter fails: steady-state wording) ===

1 failure(s)
```

Red, exactly as predicted — the terminal renders the `\037` separators as
nothing (non-printing), so the recorded line displays as
`-C/tmp/.../tag--listv*--sort=-v:refname`, which is
`-C <project> tag --list v* --sort=-v:refname` with separators stripped for
display; the recorded invocation is genuinely the tag listing.

**The decision-only prediction, verified separately.** The failure list above
shows exactly one `FAIL` line — for the new log assertion — and none for
`version-guard git-tagged-unrelated exit code` or the "expected no output" check
inside `assert_allow`. Both of those (the decision-only assertions) stayed green
under this same mutation, confirming the runbook's claim that a bare
`assert_allow` cannot observe the hoist: the hook still allows, byte-identical,
whether the listing runs before or after the decision.

**Revert and verification:**

```
$ git diff --quiet -- toolkit/version-guard.sh && echo clean
clean
$ bash tests/version-guard-test.sh 2>&1 | tail -3
=== version-guard (semver filter fails: steady-state wording) ===

all version-guard scenarios passed
```

## Gate 2 — additive falsifiability sweep

**Mechanism identified.** This item's new assertion reads a command log, not a
decision field and not message text, so the deny-emitting `jq -nc` site (the
mechanism Item 3.2 targeted for its own sweep) is irrelevant to it. The
mechanism the log assertion actually depends on is: **the recording `git` stub
correctly intercepts the binary the hook invokes and appends a line for each
invocation, while the hook's own code decides whether to invoke `git` tag
listing at all before or after the early return.** Two things have to both hold
for the assertion to mean anything: (a) the stub genuinely intercepts and logs
when git is invoked (not silently bypassed), and (b) the listing genuinely runs
— or doesn't — depending on the early return's position.

**The runbook's own Gate 1 above already exercises and defeats exactly this
mechanism.** Under the hoist mutation, the stub recorded a real
`-C <project> tag --list v* --sort=-v:refname` invocation — visible verbatim in
the quoted `FAIL` line above — proving the stub does intercept and log correctly
when the code path reaches the listing, and that the resulting log content is
what the assertion is built to catch. There is no separate "stub silently never
invoked" failure mode to probe independently: in the unmutated scenario the
early return fires before any git call at all (the license edit leaves
`proposed == current`, both `"1.2.3"`), so the log stays empty in that case
either because the code correctly short-circuits or because the stub is broken —
the two are indistinguishable from this scenario alone. Gate 1's mutation is
precisely what forces the listing to run and shows the stub records it
faithfully rather than swallowing it, which is what closes that gap. No
production defect surfaced; running a duplicate mutation against the same
mechanism would add nothing. Per the item's instruction ("If the runbook gate
above already defeats it, say so and run no duplicate"), no second mutation was
applied.

## `just precommit`

Green (all nine suites, `_import-check`, 400-line cap, doc-sync, `whitespace`,
`format-docs`). `format-docs`/rumdl reported 22 pre-existing MD013 line-length
issues, all in `plans/2026-09-15-first-release-version/reports/*` and other
`plans/2026-09-18-deliverable-review-fixes/reports/*` files unrelated to this
item's change and untouched by it — not a failure, `just precommit` still exited
`ok`. No `release-test.sh` flake was observed in either the standalone run or
the two full `precommit` runs (once before commit, once as the pre-commit hook).

## Commit

`15f54f9bc9bce4acf318e63d59d5fdd22826cedb` — "✅ Item 3.3 — an allow scenario
pins the tag listing's ordering" (the pre-commit gitmoji hook prepended the
emoji).

```
$ git show --stat HEAD
commit 15f54f9bc9bce4acf318e63d59d5fdd22826cedb
Author: David Allouche <david@ddaa.net>
Date:   Sun Sep 20 20:52:45 2026 +0200

    ✅ Item 3.3 — an allow scenario pins the tag listing's ordering

 tests/version-guard-test.sh | 44 +++++++++++++++++++++++++++++++++++++++++++-
 1 file changed, 43 insertions(+), 1 deletion(-)
```

`git show --stat HEAD | grep -i claude` matched nothing (exit 1) — `.claude/`
appears nowhere in the commit. `git status --short` after the commit still shows
`.claude/handoff-task.md` and `.claude/handoff-todo.md` staged (pre-existing,
untouched by this commit), plus this sandbox's usual untracked dotfile masks
(`.bashrc`, `.zshrc`, `.claude/agents`, `.idea`, `.vscode`, …). `memory` needed
no `git add`: `git status --short` shows no `memory` line,
`git -C memory status --short` is clean, and `git ls-tree HEAD memory`
(`332096d346009349b3ac690ecf5edfc34b17e1dc`) already equals
`git -C memory rev-parse HEAD`.

## For Item 3.4

The new call site, verbatim, in the file's current glob-form idiom (not yet
converted to `grep -q --`):

```sh
US="$(printf '\037')"
assert_not_contains "$(cat "$guard_recordgit_log")" "tag${US}--list" \
    "version-guard git-tagged-unrelated: no git tag listing runs before the early return"
```

The recording stub's log path is `$guard_recordgit_log` (a `mktemp` file
allocated near the top of the suite, alongside `guard_stub127_dir` and
`guard_stubgrep_dir`), holding one line per `git` invocation with arguments
joined by an ASCII Unit Separator (octal `037`), one line per invocation. The
needle above (`"tag${US}--list"`) is the only new further-needle candidate this
item adds for Item 3.4's BRE re-check; it contains no BRE-live characters and
does not span a line break.
