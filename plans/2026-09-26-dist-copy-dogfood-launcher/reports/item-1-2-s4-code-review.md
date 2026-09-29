# Review: Item 1.2/4 code review — physical spelling

**Scope**: `toolkit/dogfood.sh` as of HEAD (`pre_tool`, the new `physical_path`,
the comment above `pre_tool`). Tests were edited only to add regression cases
for the fixes below, each shown red against the committed SUT first. **Date**:
2026-09-30 **Mode**: review + fix (TDD code review)

## Summary

The committed `physical_path` walks up with `basename`/`dirname` to the nearest
existing directory, resolves it with `pwd -P` and re-appends the missing tail.
That handles the slice's three tests. It has two gaps against the contract,
"compared physically". First, a `..` in the missing tail stays in the compared
path, so an edit into the copy spelled through a not-yet-created directory is
allowed, and a source path spelled through the copy is denied. Second, every
`$(...)` capture strips a trailing newline from a name, so `dirname` can turn a
link into the copy into a same-named directory outside it. Both are fixed by
rewriting `physical_path` as a forward walk in one subshell, with `cd -P` into
each existing directory, `..` applied to the missing tail, and the result read
from `$PWD`. The two captures in `pre_tool` gained an `x` sentinel.

**Overall Assessment**: Ready

## Issues Found

### Critical Issues

None.

### Major Issues

1. **`..` in the missing tail is compared as spelled**
   - Location: `toolkit/dogfood.sh`, `physical_path`
   - Problem: `$root/skills/nope/../../dist/plugin/skills/demo/SKILL.md` (with
     `nope/` absent) resolves to `$root/skills` plus a tail that still holds
     `..`. It fails the `"$root/dist/plugin/"*` prefix, so the hook allows an
     edit that lands in the copy. The converse,
     `$root/dist/plugin/new/../../../skills/demo/SKILL.md`, is a source path and
     was denied, with an `additionalContext` source path of
     `<root>/new/../../../skills/…`. The kernel cannot resolve a `..` past a
     missing directory, so the edit lands where the `..` leads. That holds
     whether Claude Code normalises the path first or makes the missing
     directories first.
   - Fix: `physical_path` is rewritten as a forward walk. It starts at `/` (or
     `.`) with `cd -P` and takes one name at a time. Each existing directory is
     entered with `cd -P`. After the first missing name, the names go on a
     `tail`, and a `..` drops the tail's last name, or runs `cd -P ..` when the
     tail is empty. The result is `${PWD%/}$tail`. This keeps kernel semantics
     for the existing prefix: a `..` after an existing symlink goes to the
     target's physical parent.
   - Test: `pre-tool follows .. past a directory not yet created`. This is a
     pair over one fixture: into the copy (deny, source
     `$root/skills/demo/SKILL.md`) and out of it (exit 0, silent). Red against
     HEAD on 3 assertions: the deny, the source path, and stdout non-empty on
     the out case.
   - **Status**: FIXED

2. **A trailing newline in a name is stripped, letting a copy edit through**
   - Location: `toolkit/dogfood.sh`, `physical_path` (`basename`, `dirname`,
     `pwd -P` captures) and `pre_tool` (the `jq -r` and `physical_path`
     captures)
   - Problem: take `$sandbox/lnk<NL>` as a link to the copy and `$sandbox/lnk`
     as a real directory. The payload `$sandbox/lnk<NL>/new/file.md` walks up to
     `dirname` → `$sandbox/lnk<NL>`, which the capture strips to `$sandbox/lnk`.
     The path compares outside the copy and is allowed. The source path in
     `additionalContext` also lost a trailing newline from the leaf name. The
     project rule treats whitespace safety as essential, and the sync half of
     this script already handles newline names.
   - Fix: the forward walk splits names with parameter expansion and reads
     `$PWD` rather than capturing `pwd -P`. `physical_path` prints with no
     trailing newline. Both captures in `pre_tool` append an `x` and strip it:
     `jq -j … && printf x`, and `physical_path … && printf x`. The `&&` keeps a
     failed command's status on the assignment, so errexit still fires.
   - Test: `pre-tool keeps a trailing newline and a bare - in a name`. It uses a
     link named `lnk<NL>` beside a real `lnk/`, and a payload whose leaf also
     ends in a newline. It expects a deny and an `additionalContext` that holds
     `$root/new/file.md<NL>.`, with the full stop pinning the kept newline. Red
     against HEAD on the deny and the source path.
   - **Status**: FIXED

### Minor Issues

1. **Ragged comment above `pre_tool`**
   - Location: `toolkit/dogfood.sh`, the comment above `pre_tool`
   - Note: the edit left "… A payload jq cannot read" as a short line.
   - Fix: reflowed. The comment now also states the two residual behaviours
     below: the unfollowed leaf symlink, and a non-enterable directory stopping
     the script non-zero.
   - **Status**: FIXED

2. **A failed `physical_path` exits the hook 1, against "exit 0 always"**
   - Location: `pre_tool`, `physical="$(physical_path …)"`
   - Note: probed with a mode-000 directory on the path. `[[ -d ]]` holds, `cd`
     fails, and the script exits 1 with `cd: <abs path>: Permission denied` on
     stderr. This is the same loud failure the comment already gives a payload
     jq cannot read. Claude Code shows a non-blocking hook error, the
     path-safety ask still guards the copy, and the edit itself cannot reach an
     unenterable directory. A silent allow would hide that the hook made no
     determination. The behaviour is kept and is now documented in the comment.
     The rewrite passes `cd` an absolute operand, so the error names the full
     path rather than `./locked`.
   - **Status**: FIXED (documented; behaviour deliberately kept)

## Flag (beyond the slice contract, not changed)

- **A symlink at the leaf is not followed.** Take `$root/skills/x.md` as a link
  to a file in `dist/plugin/`, or a dangling link to a path there. An Edit or
  Write through it lands in the copy, and the hook allows it. The contract says
  "nearest existing ancestor through `pwd -P`", and `pwd -P` resolves
  directories only. Claude Code's own check `realpath`s the leaf, which is what
  decision 6's "as Claude Code's own check does" points at
  (`memory/ddaanet/cc-plugin-dirs-env-var.md`: "walking up to the nearest
  existing ancestor"). So this is a gap against the design intent, not against
  the Item 1.2 interface. The fallback is the path-safety ask, which flags the
  resolved target. A fix would follow the leaf link with a bounded `readlink`
  loop (no `-f`, for BSD). That is beyond the contract, so it is left as a flag
  and the comment above `pre_tool` states the residual bound.
  - **Status**: DEFERRED — beyond the Item 1.2 contract; the dispatch directs a
    flag, not a change. The orchestrator decides whether to widen the contract.

## Portability and edge probes (fixed SUT, run against this repo's root)

| Payload `file_path` | Result |
|---|---|
| `""`, field missing | exit 0, silent |
| `/` | exit 0, silent (resolves to empty) |
| `<root>/dist/plugin`, `<root>/dist/plugin/` | exit 0, silent (the directory itself, not under it; unchanged from HEAD) |
| `<root>//dist///plugin/./a` | deny, source `<root>/a` |
| relative `dist/plugin/a` (cwd = root) | deny, source `<root>/a` |
| relative `-x/y` | exit 0, silent |
| `42` (non-string) | exit 0, silent (`jq -j` prints `42`, a relative path) |
| `/../../<root>/dist/plugin/x` | deny, source `<root>/x` |
| `not json` | exit 5, jq's parse error (unchanged, documented) |
| under a mode-000 directory | exit 1, cd's error naming the absolute path |

- **BSD `basename`/`dirname` and `--`:** moot. The rewrite uses neither, which
  also drops two forks per missing name.
- **bash 3.2:** it uses only `[[ ]]`, `${x%%/*}`, `${x#*/}`, `${x%/}`, `local`
  in a function-body subshell, and `printf '%s'`. `jq -j` needs jq 1.5 or later.
- **`cd -`:** a directory named `-` is entered as `${PWD%/}/-`, never as a bare
  operand; `cd -- -` still means OLDPWD in bash (probed). The test's `-` link
  case guards it. It is green at HEAD, since the old code passed absolute paths,
  and it is there for the rewrite.
- **Spaces:** the fixture's `my consumer` root carries them through every new
  case.

## Mutated-SUT run (once)

The mutation turned the forward walk logical. On the name step,
`cd -P -- "${PWD%/}/$name" || exit 1` became `cd -- "${PWD%/}/$name" || exit 1`.
That is the plausible implementation the slice exists to rule out. The suite
reported `8 failure(s)`: the deny and the source path in each of
`… through a symlinked repo`, `… through a symlink to the copy`,
`pre-tool keeps a trailing newline` and `pre-tool follows a link named -`. Every
symlink-spelled test redded.
`… invoked through the symlink denies a physical path` stayed green. That is
expected: its payload is physical, and it pins `root_dir`, which the mutation
did not touch. The code was restored by the inverse replacement. `grep -cF`
finds the original line once and the mutant 0 times, and the suite is green.

(My first landing and restore checks used `grep -c` in BRE mode and printed 0
for both spellings, which proved nothing. The fixed-string re-check above is the
evidence.)

## Fixes Applied

- `toolkit/dogfood.sh` `physical_path`: rewritten as a forward walk in one
  subshell. It uses `cd -P` per existing directory, lets `..` pop the missing
  tail, gives `cd` an absolute operand, reads `$PWD` for the result and prints
  no trailing newline. Its comment was rewritten to match.
- `toolkit/dogfood.sh` `pre_tool`: `jq -r` became `jq -j … && printf x`, and the
  `physical_path` capture takes the same sentinel. Each is stripped with
  `${var%x}`.
- `toolkit/dogfood.sh`, the comment above `pre_tool`: reflowed. It now adds the
  leaf-symlink bound and the non-enterable-directory failure.
- `tests/dogfood-test.sh`: two new blocks,
  `pre-tool follows .. past a directory not yet created` and
  `pre-tool keeps a trailing newline and a bare - in a name`. They sit before
  `pre-tool invoked through the symlink denies a physical path`.
- Verification: `bash tests/dogfood-test.sh` passes
  (`all dogfood scenarios passed`). `shellcheck` is clean on both files, and
  `bash -n toolkit/dogfood.sh` passes.

## Requirements Validation

| Requirement | Status | Evidence |
|---|---|---|
| exit 0 always on a valid payload | Satisfied, with a documented exception | every probe above exits 0 except an unreadable payload (jq's status) and a non-enterable directory (cd's status), both stated in the comment |
| path = `.tool_input.file_path // .tool_input.notebook_path` | Satisfied | `pre_tool` `jq -j` line |
| compared physically, nearest existing ancestor via `pwd -P` | Satisfied | forward walk with `cd -P`; symlinked repo, symlink to copy, `..` and newline tests; mutation run |
| deny object and `<root>/<rel>` source path, `<rel>` under missing directories | Satisfied | `new/` absent in the symlink tests; `$root/new/file.md` asserted |
| silent otherwise | Satisfied | the `..`-out-of-copy case and the Item 1.2/3 tests |
| silent without jq | Not in this slice | Item 1.2/5 (scope OUT) |

## Positive Observations

- `pre_tool` keeps the as-given spelling in `permissionDecisionReason` and the
  physical spelling for the source path. The agent sees what it typed and where
  to go.
- The committed helper already chained each fallible step against the
  errexit-off `$(...)` context. The rewrite keeps that discipline with
  `|| exit 1` on each `cd`.

## Recommendations

- `tests/dogfood-test.sh` is now 634 lines. The split is already deferred to the
  phase boundary.
- The leaf-symlink flag above needs a call on whether decision 6's "as Claude
  Code's own check does" should widen the Item 1.2 interface.
