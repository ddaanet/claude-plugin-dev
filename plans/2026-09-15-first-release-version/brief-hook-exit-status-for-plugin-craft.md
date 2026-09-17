## Brief: a decided deny is silently bypassed by any later failure

2026-09-17

For `plugin-craft`'s `hook-authoring` skill. Written from
`/Users/david/code/claude-plugin-dev`, which cannot write to
`/Users/david/code/plugin-craft` — it is not a mounted working directory here.

### What the skill already owns

`skills/hook-authoring/references/output-channels.md:33`:

> **`PreToolUse` — `exit 2` blocks the tool outright.** Any other non-zero exit
> lets the action proceed and adds a "hook error" notice.

That is correct and is the mechanism. The "Blocking asymmetry" section around it
is good, and `:24-26`'s "naive fail loudly ⇒ exit non-zero is backwards" is the
right instinct stated for the *output* channel.

### The gap

The reference states the rule as a fact about **how a hook should exit**. It
does not state the consequence for
**control flow inside a hook that has already decided**, which is where it
actually bites:

> A hook that decides a deny and then does more work — a probe, a lookup, a
> listing to pick between two refusal messages — converts its own deny into an
> allow if any of that later work fails under `set -e`. The hook exits non-2
> with no stdout; Claude Code calls it a non-blocking error; the refused call
> proceeds. Nothing reaches the user, and nothing reaches the agent.

So **the capture-the-status rule inverts after the decision point.** Before it,
discarding a status is the classic defect. After it, discarding is fail-closed
and propagating is fail-open — a bare `|| true` on a capture that only feeds the
*wording* of an already-decided refusal is correct, and narrowing it to the one
error the author had in mind reintroduces the bypass.

### Evidence

`toolkit/version-guard.sh` in claude-plugin-dev grew a `git tag` listing after
its deny, to choose between an initial-release and a steady-state message. Under
`set -euo pipefail`, on a `CLAUDE_PROJECT_DIR` that is not a repository — the
common case for the plugin this guard protects — git exits 128, the script
aborts, and the guard is disabled outright. Measured, with the absorber removed:

```
exit_status=128   stdout=[]   stderr=[]
```

Reachable the same way: `grep` absent from `PATH` (127), an OOM-killed git
(137), a filter erroring (2). Three opus-level reviews reasoned about the shape
before a probe settled it.

### Suggested additions

To `references/output-channels.md`, after the `PreToolUse` line at `:33`:

> **The corollary for hook control flow:** once a hook has decided a deny, every
> later command's failure must be absorbed. `set -e` reaching anything after the
> decision point exits the hook non-2 with no stdout, which is a silent, total
> bypass rather than a loud failure. This inverts the usual "never discard a
> status" rule — after the decision, discarding is fail-closed and propagating
> is fail-open.

Two supporting points worth a line each:

- **A status read inside an `if` condition is safe; a branch *body* is
  errexit-live.** `status=$?` must be the first statement of an `else` branch —
  one `[[ … ]]` inserted above it both clobbers `$?` and kills the hook.
  (Measured: rc 1, no stdout, bypass.) This one overlaps
  `shell-scripting:shell-gotchas`, which has a separate open brief on errexit
  inside an AND-OR list's body.
- **A green suite proves nothing here.** The bypass is invisible unless a
  scenario forces the probe to fail. The test that catches it: stub the probe to
  fail and assert the hook still exits 0 with its decision JSON on stdout. In
  the incident above, dropping the guard that distinguishes a failed filter from
  an empty one left the suite green while a released plugin got the permissive
  "first version is yours to choose" wording.

### Not in scope

No claim that anything currently in `output-channels.md` is wrong. `:19-26`,
`:31-39` and `:42-53` all held up against this work and were useful.

### Provenance

Full argument, the reachable-status table and every probe transcript are in
`plans/2026-09-15-first-release-version/reports/item-2-1-hook-exit-status-contract.md`
in claude-plugin-dev, committed. The call site is `toolkit/version-guard.sh`'s
post-deny block.
