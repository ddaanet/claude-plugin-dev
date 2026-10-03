# Deliverable review, Layer 1: code

**Scope:** `git diff fd16ae65f4b244f1098b94b7ee848f5a7f74c8f2..HEAD` over
`toolkit/dogfood.sh`, `toolkit/bin/claude`, `toolkit/install.sh` and
`toolkit/release.just`. The baseline is the outline's D1–D12, Items, Scope and
Risks. **Date:** 2026-10-02.

**Excluded as already settled:** findings in `reports/review-code.md`,
`reports/tdd-audit.md` and `reports/tdd-audit-followup.md`, and the "Unpinned by
choice" list in orchestrator-3's report. Also excluded are the decisions already
taken: the v0.9.0 minor bump, no explicit symlink refusal, and the README
reflow. None of the items in those reports turned out to be wrong.

**Probe environment:** Linux, bash 5.2.37, jq 1.7, rsync 3.5.0. The probes ran
on a `git archive HEAD` extract under `$TMPDIR/dr-code` and on a fixture
consumer under `$TMPDIR/dr-code-probe/c`. No tracked file was edited.

## Severity counts

- Critical: 0
- Major: 1
- Minor: 4

## Findings

### M1. The shim promotes on every `claude` it fronts, scripted runs included, and loads the copy into them

- **Location:** `toolkit/bin/claude:19-27`.
- **Axis:** conformance (D4), robustness.
- **Severity:** Major. This is a design gap with a concrete consumer impact, not
  a deviation from D9's letter.

**Description.** The shim syncs and exports `CLAUDE_CODE_PLUGIN_DIRS` for every
invocation, whatever its argv. Inside a migrated consumer, any `claude` that a
script or recipe runs from the user's direnv shell goes through it. Two things
follow.

1. Every such process re-promotes the working tree into `dist/plugin/`,
   repo-wide and under any live session. This is the half-edited-hook exposure
   that D4 ("sync only on deliberate promotion") exists to prevent. The same
   applies to `claude --version`, `claude mcp …` and `claude update`.
2. Every such process loads the copy as an inline plugin. That holds even when
   the script has set its plugin surface up on purpose.

The outline's Risk "Children inherit the variable" covers only children of a
dogfood session, where the shim is already off PATH. It does not cover this
path.

**Evidence (read-only, gitlore):**

- `tests/evals/lib/claude-runner.sh:64` runs
  `(cd "$CWD" && claude "${args[@]}" < /dev/null)`, with
  `--setting-sources project`.
- `tests/evals/lib/setup.sh:53-71` deliberately copies the plugin's
  `hooks/hooks.json` into the eval repo's `.claude/settings.json`. The comment
  says this "bypasses the plugin".
- `setup.sh:78` copies the skills into `.claude/skills`.

After gitlore adopts the shim per `toolkit/migrations/v0.9.0.md`, each eval turn
does the following:

- it runs a sync;
- it starts `claude -p` with `CLAUDE_CODE_PLUGIN_DIRS=<gitlore>/dist/plugin`;
- it therefore loads gitlore's hooks twice, once through settings and once
  through the copy, and its skills twice;
- under a parallel eval run, it also risks the concurrent-sync collision that
  the outline accepts as rare.

`just prerelease` runs these evals from the user's shell, per
`memory/ddaanet/sandbox-effects.md`.

**What would settle it.** This is a design question about venue, not an obvious
fix. One option is a shim-side bypass, such as an opt-out variable or no sync
for a non-interactive argv. The other is a documented consumer-side rule, under
which scripts call the real `claude`. Route to `/design`.

### m1. `pre-tool` can exit 2, which blocks, where its comment promises a non-blocking error

- **Location:** `toolkit/dogfood.sh:85-88` (the comment) and `:98` (the code).
- **Axis:** error signaling.
- **Severity:** Minor.

**Description.** The comment says that a payload jq cannot read "stops the
script non-zero: Claude Code shows a non-blocking hook error". errexit
propagates jq's own status, and a `PreToolUse` hook exiting 2 is a blocking
error.

- jq 1.7 exits 5. I probed this.
- jq 1.6, still the distro jq on Debian 11 and Ubuntu 22.04, returns 2 for an
  input parse error in its `main.c` (`ret = 2` after `parse error:`). I did not
  probe this; it comes from reading the source.

Under jq 1.6 an unreadable payload therefore blocks the edit, with jq's stderr
fed to the agent. The trigger is near-hypothetical, since Claude Code sends
valid JSON. The problem is that the stated contract depends on the jq version.
The suite asserts only "non-zero" (`tdd-audit-followup.md` §A1), so it passes
either way.

**Evidence:**

```text
$ printf 'not json' | jq -j '.tool_input.file_path // ""'; echo rc=$?
jq: parse error: Invalid numeric literal at line 1, column 4
rc=5          (jq-1.7)
```

### m2. A sandboxed `just dogfood` copies zero-byte sandbox masks into the copy, including into plugins that ship no `.mcp.json`

- **Location:** `toolkit/dogfood.sh:56-69`.
- **Axis:** robustness.
- **Severity:** Minor.

**Description.** The README caveat (`toolkit/README.md:244-248`) and the node
(`docs/references/dogfood.md:334-341`) cover only a plugin that ships a
`.mcp.json`, and they call the zero-byte mask shape "unprobed". That shape is
the live one in this session. Masks are untracked and not ignored, so they are
not in the exclude list, and rsync copies them as regular files. A plugin with
no `.mcp.json` therefore gains an empty `dist/plugin/.mcp.json` after an agent's
`just dogfood`. It lasts until the next unsandboxed sync deletes it.

I did not probe how Claude Code treats an empty plugin-root `.mcp.json`. The
README's "If your plugin ships a `.mcp.json`" scoping is the part shown to be
too narrow.

**Evidence:**

```text
$ ls -la /Users/david/code/claude-plugin-dev/.mcp.json   # sandboxed, this session
-r--r--r-- 1 david david 0 Oct  2 16:21 .mcp.json
# fixture: simulated mask, sync, then mask removed and sync again
$ : > .mcp.json && chmod 444 .mcp.json && bash plugin-dev/dogfood.sh sync; echo rc=$?
rc=0
-r--r--r-- 1 david david 0 Oct  2 16:26 dist/plugin/.mcp.json
$ rm -f .mcp.json; bash plugin-dev/dogfood.sh sync; ls dist/plugin/.mcp.json
ls: cannot access 'dist/plugin/.mcp.json': No such file or directory
```

A related case is also unprobed. `sandbox-effects.md` records that a plugin's
own `hooks/hooks.json` is held read-only while it is the session's active hooks
config. In a dogfood session that file is `dist/plugin/hooks/hooks.json`, so an
agent's sandboxed `just dogfood` after a `hooks.json` change would likely fail
with rsync code 23. That failure is loud, so the case is noted here rather than
counted as a finding.

### m3. A failed sync at launch is not attributed to the shim

- **Location:** `toolkit/bin/claude:19`.
- **Axis:** error signaling.
- **Severity:** Minor.

**Description.** D8 holds: the shim aborts before the exec with the sync's
status. The user typed `claude`, though, and for an rsync failure (code 23/24,
or a concurrent-sync collision) they see only rsync's stderr. No line says that
the shim's sync failed and that `claude` was not started. The refusals carry a
`dogfood:` prefix, but rsync's own errors do not. A single
`dogfood: sync failed, claude not started` line to stderr on a non-zero sync
would close this.

### m4. `install.sh`'s closing output says nothing about the dogfood setup it now depends on

- **Location:** `toolkit/install.sh:189-193`.
- **Axis:** functional completeness and usability (D11).
- **Severity:** Minor.

**Description.** A fresh install now wires a `SessionStart` hook that warns on
every session until the consumer does three things:

- adds `PATH_add plugin-dev/bin` to `.envrc`;
- ignores `/dist/plugin/`;
- launches through the shim.

"Next steps" still lists only the recipes and a `git add` of
`plugin-dev justfile .claude/settings.json`. D11 puts these steps in the README
on purpose, and the migration note carries them for updaters. A first-time
installer, though, reads only this output and the session warning, and neither
points at the README's Dogfooding section.

## Unprobed observations (no severity assigned)

- **Nested `CLAUDE.md` in the copy.** `dist/plugin/CLAUDE.md` is a copy of the
  root's. If Claude Code loads subdirectory `CLAUDE.md` files on a Read under
  them, a Read of a copy path, which the README presents as the way to inspect
  promoted content, would inject a second and possibly stale copy of the project
  instructions. If it does, this contradicts the Risk "costs bytes, not
  behaviour". I did not verify whether that loading skips git-ignored
  directories.
- **macOS case-insensitive spelling.** `physical_path` keeps the spelled case,
  and `case "$physical" in "$root/$copy/"*` is case-sensitive. On default APFS,
  `<root>/Dist/Plugin/x` therefore names the copy but is allowed. Whether Claude
  Code's `realpathSync.native` canonicalises case, which would leave its own
  `ask` still standing, was not checked. This could not be probed on Linux.

## Checked and found clean

- **Conformance to D1–D3, D5–D11.** Each holds as written, apart from the two
  divergences that `review-code.md` already accepted (no `paste`, and the
  leaf-link `readlink -fn`). Spot-checked against code:
  - D6's three-channel deny with `notebook_path`;
  - D7's whole-entry match, resolved on both sides, with the ANSI reset and the
    jq notice on `systemMessage` only;
  - D9's overwrite, `unset CDPATH`, `-ef` strip and 127 exit;
  - D10's single-line doc comment with no gate;
  - D11's matcher-agnostic presence check and quoted new commands.
- **rsync rule-prefix and comment parsing.** Every ignore entry is emitted as
  `/<entry>`, so no entry can start with `+ `, `- `, `!`, `#` or `;`. Probed
  with ignored files named `!x`, `- d`, `+ p`, `#h`, `;s` and `tr ` (trailing
  space) beside a tracked `tr`. All six were excluded, `tr` was copied, and the
  exit was 0.
- **Copy-path spellings.** `dist//plugin/./a.txt`,
  `nonexist/../dist/plugin/a.txt` and a not-yet-existing
  `dist/plugin/new/dir/x.md` were each denied, with the correct source mapping.
  `dist/plugin` and `dist/plugin/` themselves, and a source path, were allowed
  silently with rc 0.
- **The deny and the warning wording.**
  - `permissionDecisionReason` is a bare refusal with no escape hatch, sync
    included.
  - The recovery goes on `additionalContext`.
  - `systemMessage` is one curt line.
  - session-start's remedy on `systemMessage` comes from the runbook. Its
    `additionalContext` states a fact with nothing to act on.
- **The first sync's stray directory.** On a first sync, rsync leaves an empty
  `dist/plugin/dist/`. The second sync removes it, because git then lists
  `dist/` as wholly ignored. This was probed, and it is transient and harmless.
- **Errexit paths.** The following were checked:
  - `root_dir` and `physical_path` chain each step explicitly, which is correct
    under SC2310's disabled-errexit context;
  - the `[[ … ]] && exit 0` inside `while` does not trip errexit;
  - the pattern-char `exit 1` surfaces through pipefail as the loop's status;
  - the EXIT trap preserves rsync's status;
  - `install.sh`'s `{ … | add_hook … ; } || {…}` fails closed under pipefail.
- **shellcheck.** Clean at default severity on all three scripts. `--enable=all`
  reports only style and info (SC2250, SC2310, SC2249, SC2292), and none of them
  is a defect.
- **bash 3.2 and BSD.** The scripts use no associative arrays, `mapfile`,
  `${x,,}` or `inherit_errexit`. `read -r -d ''`, `[[ -ef ]]`, `pipefail` and
  `printf '%s\0'` all exist in 3.2. No `case` sits textually inside `$( )`.
  `mktemp` has an explicit template, and there is no `sed -i`, `stat`, `paste`,
  `timeout` or `date -d`.
- **Consumer collisions.** No consumer justfile defines a `dogfood` recipe, and
  none tracks a symlink, so `rsync -a`'s link preservation is never exercised.
  Checked across the 11 consumers: candidature, craft, cwd-safety, gitlore,
  gitmoji, handoff, onekeys, plugin-craft, prohibitions, sandbox-lies and
  shell-gotchas. candidature's `dist/` ignore covers `dist/plugin/`.
- **Idempotency.** Re-syncs converge, and a re-run of `install.sh` is
  byte-identical, so nothing is written.
- **Excess.** No unspecified behaviour was found in the four files.
