# Item 2.1, slice 1 — code review

Scope: `toolkit/version-guard.sh` as changed by `df2c4c0`. `tests/hook-test.sh`
not touched. Two fixes applied, both in the SUT. Suite and `just precommit`
green after.

Headline: the `|| true` is **correct and must stay** — removing it is a total
guard bypass, which the GREEN's own justification does not say and a later
reader would not guess. The real defect is elsewhere: the initial-release
message named a recipe invocation that `release.sh` *refuses* on an unreleased
plugin, described a bump the first-release path does not perform, and presented
the recipe as the route to `$proposed` — the exact hazard `outline.md:118-121`
names and forbids.

## 1. The `|| true` — verdict: keep, comment rewritten

The GREEN's pipefail reasoning is exactly right, verified by probe: a failed
`git -C` propagates 128 through the pipe under `pipefail` even though the filter
stage already turned its own "no match" into success.

But the verdict does not rest on that. It rests on the hook's exit-status
contract: once the deny is decided, a hook exiting non-zero for any reason other
than 2 is a **non-blocking** error and the refused edit proceeds. Absorbing is
fail-closed; propagating is fail-open. Removing the `|| true` is a total guard
bypass — measured, not reasoned.

Slice 6 does **not** subsume it, and `outline.md`'s prescribed shape for slice 6
would reintroduce a second bypass.

Full argument, every probe transcript, the table of what the absorber now
swallows, and the hazard slice 6 must avoid:
[item-2-1-hook-exit-status-contract.md](item-2-1-hook-exit-status-contract.md).

Fix applied here: comment only. The old one justified `|| true` solely by the
git-128 case, which invites exactly the narrowing that would break it. No
behaviour change.

## 2. Placement — proven by construction

Four `git` stubs on `PATH`: real git, `exit 127`, `kill -9 $$` (137), and one
emitting garbage on stdout + noise on stderr and exiting 3. Six payloads each,
covering every allow and deny path.

```
=== git stub: <real git> / stub127 / stubkill / stubhang ===   (all four identical)
DENY edit                          rc=0    decision=deny   stdout_empty=no    stderr=[]
DENY write                         rc=0    decision=deny   stdout_empty=no    stderr=[]
ALLOW same-field                   rc=0    decision=       stdout_empty=yes   stderr=[]
ALLOW other-file                   rc=0    decision=       stdout_empty=yes   stderr=[]
ALLOW other-tool                   rc=0    decision=       stdout_empty=yes   stderr=[]
ALLOW no-change                    rc=0    decision=       stdout_empty=yes   stderr=[]
```

Every deny still denies and every allow still allows under all four, including
the stub that writes to stderr — `2>/dev/null` keeps the hook's own stderr
empty. The listing sits after the `exit 0` gate and every allow path returns
before reaching it, so it cannot fire on an allow and cannot turn a deny into an
allow. Load-bearing property holds.

## 3. `$project` edge cases, including whitespace

Run, not reasoned:

```
spaced path, tagless repo                rc=0   wording=INITIAL  stderr=[]
spaced path, tagged v1.2.3               rc=0   wording=STEADY   stderr=[]
nonexistent project dir                  rc=0   wording=?        stderr=[]
project dir is a regular file            rc=0   wording=?        stderr=[]
non-repo dir nested in tagged repo       rc=0   wording=STEADY   stderr=[]
```

Fixture path `…/spa ced dir/pro ject` — two spaces — works in both directions.
`git -C "$project"` is quoted and carries it through.

`?` for the nonexistent dir and the regular file is correct, not a miss: the
manifest is not found at `:23` and the hook exits 0 before the listing ever
runs. Both are allow-with-no-output, which is the right answer for "there is no
manifest here".

The nested case is the documented accepted bound: a non-repo
`CLAUDE_PROJECT_DIR` inside a tagged repo lists the enclosing repo's tags and
gets steady-state wording — wording only, never the decision. Comment beside the
listing states it.

## 4. The predicate is genuinely the semver one

```
tags: vnext + v1.2 (non-semver)          rc=0   wording=INITIAL  stderr=[]
tags: v1.2.3                             rc=0   wording=STEADY   stderr=[]
tags: vnext + v1.2 + v0.9.0              rc=0   wording=STEADY   stderr=[]
```

Slice 4's required behaviour already holds as landed. No defect.

Mutations A and B1 were re-run against the committed code and reproduced the
test review's coverage table; both restored, checksum back to HEAD's
`a3aec46bb1c8051fcd111b84d8cb8930` before any fix was applied. The consolidated
analysis — which mutation each slice catches, and why slice 4 is the only slice
that catches all three wrong predicates — is
[item-2-1-slice-coverage.md](item-2-1-slice-coverage.md).

## 5. Steady-state branch is byte-identical to pre-slice

Verified against `git show df2c4c0^:toolkit/version-guard.sh`, same tagged
fixture, same payload — not taken from the report:

```
--- P5: steady-state reason, pre-slice vs post-slice (tagged fixture)
BYTE-IDENTICAL (reason)
b5513b166dcf78e8293dc7c542885605  pre.txt
b5513b166dcf78e8293dc7c542885605  post.txt

--- P5b: whole JSON payload, pre vs post, tagged fixture
BYTE-IDENTICAL (whole JSON)
```

Still byte-identical after this review's fixes (replayed post-fix).

## 6. `systemMessage` did not branch

```
tagged : [version-guard: blocked plugin.json version edit (1.2.3 -> 9.9.9)]
tagless: [version-guard: blocked plugin.json version edit (1.2.3 -> 9.9.9)]
systemMessage IDENTICAL
```

Static confirmation — one assignment, after `fi`:

```
107:if [[ -z "$release_tags" ]]; then
132:fi
134:human_msg="version-guard: blocked plugin.json version edit ($current -> $proposed)"
```

## 7. The agent-facing message — CRITICAL, fixed

As landed:

```
This plugin has never been released -- no vX.Y.Z tag exists yet. The first
release will publish whatever plugin.json holds when
'just release {patch|minor|major}' runs; that recipe validates state,
bumps, commits, tags, and pushes in one step.
```

Judged as prose an agent will act on, three defects — all against the item's own
"offers no escape hatch" and `outline.md:115-121`:

1. **It is a route to `$proposed`.** "will publish whatever plugin.json holds
   when `<recipe>` runs" tells the agent that the manifest value at release time
   is what ships. An agent that was asked to set the version reads that as: edit
   plugin.json to `9.9.9` — the edit just refused — then run the recipe.
   `outline.md:118-121` names this hazard verbatim: "It must not present
   `just release` as a route to `$proposed` … The message may say what the
   recipe publishes, not suggest running it for this edit." The GREEN report
   claims (`:100-104`) the message "does not name the recipe as a route to reach
   the proposed version". It does.

2. **The named invocation is one `release.sh` refuses.** `release.sh:445-455`:

   ```
   if [ -z "$release_tag_list" ]; then
       first_release=1
       if [ -n "$bump_arg" ]; then
           …
           die "'$bump_arg' bump refused: this plugin has never been released"
   ```

   `just release {patch|minor|major}` is exactly what an unreleased plugin
   rejects. The message sends an agent into a guaranteed failure, and
   `outline.md:103` says the first-release form is `just release`, no argument.

3. **"that recipe … bumps …" is false on this path.** `release.sh:460` —
   `note "first release: publishing the manifest version $V as-is (no bump)"`.
   The clause was carried over from the steady-state branch, where it is true.

Also missing: the outline requires the message to say the manifest holds
`$current`, "the version the initial release will publish,
**and that setting it is the maintainer's edit**". That sentence is what makes
the refusal legible without handing over a route, and it echoes
`release.sh:452-454`'s own hint ("it is the maintainer who decides what a plugin
first ships as").

### Fix applied

```
This plugin has never been released -- no vX.Y.Z tag exists yet, so the
manifest is not tracking a previous release. It holds $current, which is
what the initial release will publish, verbatim. Which version a plugin
first ships as is the maintainer's call and their edit to make.

Do not bypass this guard, modify the recipe, or alter version state by
other means.
```

It names no invocation at all — withholding the identifier rather than
forbidding its use, so there is nothing to read as an instruction. Verified
against every constraint:

```
contains 'never been released': YES
contains 'will publish': YES
contains 'last released version': no
9.9.9 absent after line 1: ok
'just release' not named in this branch: ok
max line width: 71
```

No-bypass sentence kept verbatim. Slice 2 (a guard, not a red) still passes;
slice 1's three needles still pass. `$current` is not a route — it is what the
manifest already holds.

Not changed: `no vX.Y.Z tag exists yet`. It discloses the predicate, but
creating a tag flips only the wording and never the deny, so it is not an escape
hatch, and it is the factual ground for the "never been released" claim.

## 8. Heredocs

```
--- P8a: dangerous chars in the two heredoc bodies (lines 101-125)
NONE: no backtick, no backslash, no $( in either body

--- P8b: every $ in the bodies
2:$current   2:$proposed   14:$current   14:$proposed

--- P8c: heredoc delimiters (unquoted EOF => expansion on)
101:read -r -d '' agent_reason <<EOF || true    111:EOF
113:read -r -d '' agent_reason <<EOF || true    124:EOF
```

Both delimiters unquoted, so `$current`/`$proposed` expand as intended; the only
`$` in either body are those four. No backtick, no `$(`, no backslash anywhere,
so `install.sh`'s heredoc hazard does not apply.

Expanded *values* are not re-scanned, confirmed with hostile manifest versions
and hostile `new_string`s carrying `$(touch CANARY)`, backticks, `${HOME}` and a
quote-breaking `'; touch CANARY; #`:

```
version=1.2.3$(touch …CANARY)  rc=0 first_line=[… 1.2.3$(touch …CANARY) -> 9.9.9.] canary=no
version=1.2.3`touch …CANARY`   rc=0 first_line=[… 1.2.3`touch …CANARY` -> 9.9.9.]  canary=no
version=1.2.3${HOME}           rc=0 first_line=[… 1.2.3${HOME} -> 9.9.9.]          canary=no
version=1.2.3'; touch …; #     rc=0 first_line=[… 1.2.3'; touch …; # -> 9.9.9.]    canary=no
proposed=9.9.9$(touch …CANARY) rc=0 first_line=[… -> 9.9.9$(touch …CANARY).]       canary=no
proposed=9.9.9`touch …CANARY`  rc=0 first_line=[… -> 9.9.9`touch …CANARY`.]        canary=no
```

Canary never created; every value reproduced literally; stderr empty throughout.

## 9. Line count

`wc -l toolkit/version-guard.sh` → **143** (was 136). Cap is 400. No
restructuring.

## 10. Flagged, not fixed

- **Slice 6 hazard (for the orchestrator).** `outline.md`'s prescribed shape —
  "only the filter's no-match status is absorbed" — leaves a `grep` status 2
  unabsorbed *after* the deny is decided, which exits the hook non-2 with no
  stdout and lets the refused edit through — measured in
  [item-2-1-hook-exit-status-contract.md](item-2-1-hook-exit-status-contract.md).
  Whatever slice 6 does to separate a failed listing from an empty one must keep
  **every** status after the deny absorbed. Not fixed here: the dispatch put the
  `|| true` in scope, but the failure/empty split is slice 6's.
- **Slice 6's planned RED is intact.** A `git` stubbed to 127 against the
  tagless fixture still yields the initial-release wording — the inversion the
  item calls out. Confirmed post-fix.
- **Slice 5's planned RED is intact.** The tagless fixture invoked with
  `GIT_DIR` pointed at a `v1.2.3` fixture yields **STEADY** wording, i.e. the
  leak is not cleared. Nothing in these fixes touches `GIT_*`.
- **Pre-existing, out of scope.** The final `jq -nc` is itself unguarded: if it
  failed, `set -e` would exit non-2 with no stdout and bypass the guard. It is
  unreachable in practice — `jq` is already required at `:13`, long before the
  deny — and predates this slice.

## 11. Post-fix verification

`bash -n` OK, `shellcheck toolkit/version-guard.sh` clean.

All probes replayed post-fix, unchanged: placement under all four git stubs, the
predicate table, the spaced-path cases, steady-state byte identity, and
`systemMessage` invariance.

`bash tests/hook-test.sh`:

```
=== version-guard (Edit version change: deny) ===
=== version-guard (Edit bare version value: deny) ===
=== version-guard (Edit unrelated field: allow) ===
=== version-guard (Write version change: deny) ===
=== version-guard (unrelated file: allow) ===
=== version-guard (drifted payload cwd: deny) ===
=== version-guard (relative file_path: deny) ===
=== version-guard (BSD realpath, unrelated file: allow) ===
=== version-guard (no tags: initial-release wording) ===
=== check-version (MARKETPLACE_DIR unset: skip) ===
=== check-version (marketplace.json missing: skip) ===
=== check-version (no entry: skip) ===
=== check-version (in sync: pass) ===
=== check-version (drift: fail) ===

all hook scenarios passed
EXIT=0
```

`just precommit` — EXIT=0, tail:

```
all release scenarios passed
update-plugin-dev scenarios passed
dist tree ok (9 files, no gitlink)
docs ok (cap 400 lines, pointers resolve)
doc sync ok (5 shared command blocks, Layout matches toolkit/)
ok
```

Checks that passed in that run: `bash -n` and `shellcheck` over the shell
scripts, `_import-check`, `tests/release-test.sh`,
`tests/update-plugin-dev-test.sh`, `tests/dist-tree-test.sh`,
`tests/docs-test.sh`, `tests/doc-sync-test.sh`, `format-docs`.

## SUT integrity

Mutated four times for §1 and §4, restored from a pre-probe copy each time;
checksum returned to HEAD's `a3aec46bb1c8051fcd111b84d8cb8930` before any fix
landed.

Final working tree:

```
 M toolkit/version-guard.sh
?? plans/…/reports/item-2-1-s1-red.md
?? plans/…/reports/item-2-1-s1-test-review.md
```

`toolkit/version-guard.sh` → `3a7e923a452966bfe5c87d9795806e39`, 143 lines.
`tests/hook-test.sh` unmodified, as the dispatch required. Not committed.
