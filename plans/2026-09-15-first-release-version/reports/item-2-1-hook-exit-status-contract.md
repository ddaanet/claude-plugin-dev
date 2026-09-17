# Item 2.1 — the hook's exit-status contract

Extracted from the slice-1 code review, which is where it was measured. It is
its own node because slices 5 and 6 both change code that runs *after* the deny
is decided, and this is the invariant they must not break.

## The contract

A `PreToolUse` hook that exits non-zero for any reason **other than 2** is a
non-blocking error: Claude Code lets the tool call proceed. `outline.md`'s third
shell constraint states this and calls it "a silent, total bypass".

So once the deny has been decided, every subsequent command's failure must be
absorbed. The usual rule — capture a status, never discard it — **inverts**
here:

- Absorbing a status after the deny is **fail-closed**. The worst outcome is the
  wrong *wording* on a refusal that still refuses.
- Propagating it is **fail-open**. `set -e` exits the hook non-2 with no stdout,
  and the edit the hook just refused goes through.

This is not the capture-that-discards-status defect found five times in
`release.sh` during Phase 1. There the discarded status changed a *decision*;
here it can only change wording, and letting it through changes the decision to
"allow".

## The `|| true` on the listing capture — verdict: keep

```sh
release_tags="$(git -C "$project" tag --list 'v*' --sort=-v:refname 2>/dev/null \
  | { grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' || [ "$?" -eq 1 ]; })" || true
```

The GREEN added the `|| true` outside the plan. It is correct and must stay.

### The pipefail reasoning behind it is exactly right

```
--- P1a: pipefail reports rightmost NON-ZERO, not last stage's status
false|true rc=1
git128|grepblock rc=128
nopipefail rc=0

--- P1b: does set -e abort the assignment without || true?
script rc=128
REACHED t=[]
script rc=0
```

`sh -c 'exit 128' | { grep -E 'x' || [ "$?" -eq 1 ]; }` returns **128** under
`pipefail` even though the right-most stage returned 0, and 0 without it.

### What else it absorbs

```
--- P1c: grep real error (status 2)
no-|| true rc=1
REACHED t=[]
with-|| true rc=0

--- P2a: git absent from PATH -- is 'command not found' suppressed by 2>/dev/null?
rc=127 out=[]
(stderr of the above, unsuppressed:)
bash: line 1: git: command not found
rc=127 out=[]

--- P2b: stub git exiting 127 via PATH prefix
rc=127 out=[]

--- P2c: git -C on a nonexistent dir / on a file
fatal: cannot change to '.../nope': No such file or directory
nonexistent rc=128
fatal: cannot change to '.../afile': Not a directory
file rc=128

--- P2d: git killed by signal (SIGKILL) -- what status
rc=137 out=[]
```

| Status | Cause | Reachable? |
| --- | --- | --- |
| 128 | `$project` not a repo / missing / a file | Yes — every `$proj` fixture, and the common pre-release case |
| 127 | `git` absent from `PATH` | Yes — slice 6's own stub |
| 137 | `git` killed by a signal (this box OOM-kills) | Yes, rarely |
| any | a `git` that exits non-zero for its own reasons | Yes |
| 1 | `grep` real error (status 2) demoted by the `\|\| [ "$?" -eq 1 ]` block | Essentially no — constant regex, pipe I/O |

`2>/dev/null` also suppresses bash's own `git: command not found`, so the 127
path stays stderr-clean.

### Removing it, measured

```
=== SUT with '|| true' REMOVED: non-repo project dir (git exits 128) ===
exit_status=128  (2 == blocking; anything else is a NON-blocking error and the edit proceeds)
stdout=[]
stderr=[]

=== same, grep forced to a REAL error (status 2) with a tagless repo ===
exit_status=1 stdout=[] stderr=[/usr/bin/grep: /nonexistent-file-forcing-status-2: No such file or directory]
```

Both statuses are non-2 and carry no stdout. Without `|| true`, a non-repo
project dir disables the guard entirely.

### The comment was rewritten

The original comment justified `|| true` solely by the git-128 case, which
invites exactly the narrowing that would break it. It now states the invariant
that makes blanket absorption correct, and notes that the inner
`|| [ "$?" -eq 1 ]` is kept for text parity with `release.sh:269` rather than
because it is live here. No behaviour change.

## Hazard for slice 6 — read this before implementing it

Slice 6 separates a failed listing from an empty one. `outline.md` prescribes:

> The listing is its own command whose status an `if` reads;
> **only the filter's no-match status is absorbed.**

Under that shape a `grep` status 2 after the deny is unabsorbed, `set -e` fires,
the hook exits 1 with no stdout, and the refused edit proceeds — reintroducing
the second bypass measured above. **Whatever slice 6 does to separate failure
from emptiness must keep every status after the deny absorbed.** Read the
listing's status into a variable without letting it reach `set -e`.

## Pre-existing, out of scope

The final `jq -nc` is itself unguarded: if it failed, `set -e` would exit non-2
with no stdout and bypass the guard. Unreachable in practice — `jq` is already
required at `:13`, long before the deny — and it predates this slice.
