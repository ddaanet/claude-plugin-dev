# Review: Item 1.2 slice 6 code (leaf symlink), post-GREEN

**Scope**: `toolkit/dogfood.sh` as changed by `3d78728` (✨ Item 1.2/6 —
pre-tool follows a symlink at the leaf): the leaf-resolution branch in
`pre_tool` and the comment above `pre_tool`. The tests were read, and not
edited. **Date**: 2026-09-30 **Mode**: review + fix

## Summary

The code change is correct. It is whitespace- and newline-safe, and it is
portable to GNU coreutils and macOS 12.3+. The comment above `pre_tool` had one
false claim, and the ragged line the dispatch named. Both are fixed. The suite
is green and `shellcheck` is clean.

**Overall Assessment**: Ready

## Issues Found

### Critical Issues

None.

### Major Issues

1. **The comment claimed a fallback for a dangling leaf link that does not
   exist**
   - Location: `toolkit/dogfood.sh`, comment above `pre_tool`.
   - Problem: the comment said a dangling leaf link into the copy "passes here
     and meets Claude Code's own sensitive-file ask instead". Claude Code's
     check (research Q1, `memory/ddaanet/cc-plugin-dirs-env-var.md`) walks up to
     the nearest existing ancestor before it runs `realpath`. A dangling link
     does not exist, so that check resolves the link's own directory, which is
     in the source. The link name is then compared in the source, which is not
     under the plugin root. So there is no ask. The claim was carried over from
     the old sentence about *existing* leaf links. For those it was true, and
     this slice now denies them. The same comment also said "that same ask still
     stands", whose antecedent was the sentence being removed.
   - Fix: the comment now says that a leaf link that does not resolve (dangling,
     looping, or through a directory that cannot be entered) is compared as
     spelled. It says that a Write through a dangling one into the copy is
     therefore not refused here. It does not say whether such a Write actually
     lands in the copy, because that depends on how Claude Code writes the file
     (open-through versus temp-and-rename), and that was not verified. The later
     sentence names "its own sensitive-file ask" directly. That claim is true:
     for a path that physically exists in the copy, Claude Code's `realpath`
     puts it under the plugin root.
   - **Status**: FIXED.

### Minor Issues

1. **Ragged comment line, and the claim about Claude Code was worded
   imprecisely**
   - Location: `toolkit/dogfood.sh`, comment above `pre_tool`. The line ended "…
     sensitive-file ask instead. A".
   - Problem: the paragraph was not reflowed after the edit. "Since Claude Code
     realpaths the leaf" was also overbroad. Claude Code realpaths the nearest
     *existing* path, which is exactly why the `-e` gate matches it.
   - Fix: the paragraph is reflowed to 80 columns. The sentence now reads "An
     existing path that ends in a symlink is resolved in full with readlink -f,
     chains included, as Claude Code's own check resolves it."
   - **Status**: FIXED.

## Security-review finding: one-hop readlink

**Claim:** the leaf-symlink branch uses `readlink -n -- "$physical"` (one hop,
raw target that may be relative). If so, a chain or a relative target escapes
the `"$root/$copy/"*` prefix check.

**It does not hold for any committed or working-tree state.**

- `git show HEAD:toolkit/dogfood.sh` and the working tree both read
  `readlink -fn -- "$physical"`.
- `git log -S'readlink -n --' -- toolkit/dogfood.sh` finds no commit that ever
  contained the one-hop form.
- The exact string the finding quotes is the mutation this review applied in
  place, for one suite run (see "Mutated-SUT run" below). The security review
  most likely read the tree during that window. The restore was confirmed: the
  grep count for the mutated form is 0, `git diff` on the file was empty before
  the comment fix, and the suite is green.

**The finding's own scenario, run against the current SUT:** `skills/x.md -> a`
and `skills/a -> ../dist/plugin/y`, a two-hop chain with a relative target. With
an absolute payload the result is `deny`, and the source is named `<root>/y`.
With a relative payload (`x.md`, cwd `skills/`) the result is also `deny`.

**Pinning in the slice's tests:**

- (a) Two-hop chain: `pre-tool follows a chain of leaf symlinks into the copy`
  (`y.md -> x.md -> ../dist/plugin/skills/demo/SKILL.md`) is denied.
- (b) Relative target: the same test. Both of its links are relative, and the
  test-review made them so for exactly this reason.
- Evidence that they bite: under the one-hop `readlink -n` mutation, that test
  failed on 6 assertions, with stdout `''`. No test was added. A single-link
  relative-target test would be redundant, because a one-hop raw `readlink`
  already fails the chain test on its relative first hop.

**`readlink -f` kept.** Evidence:

- Linux: GNU coreutils 9.7 here. The suite passes, and the probes below pass.
- macOS 26.6: this was not run on a Mac. The evidence is documentary.
  `readlink -f` has been in macOS since 12.3 (shell-gotchas
  `references/portability.md`, citing the macOS realpath/readlink man pages).
  macOS `readlink` is the BSD `stat(1)` binary, which parses its options with
  `getopt(3)`. That makes the combined `-fn` and the `--` terminator standard.
  Its `-n` is documented as "do not force a newline". Its `-f` goes through
  `realpath(3)`. The `-e` gate keeps `readlink` to paths that exist, which is
  where GNU and BSD `-f` agree. They can differ only on a missing last
  component, and the gate never reaches that case.
- No concrete reason for failure was found on either platform.

## Probes (scratch copy of the SUT, root spelled `my root`)

| Leaf | Result |
|---|---|
| Link to a copy file whose name ends in a newline | deny; the source ends `skills/t\n.` (newline kept) |
| Link to a copy file named `a b` | deny; the source is `<root>/skills/a b` |
| Link named `n<NL>` into the copy | deny; the reason keeps `n\n` |
| Link to a directory in the copy | deny, through `physical_path`'s `cd -P` (not this branch) |
| Dangling link into the copy | allow, exit 0 (the residual) |
| Link loop | allow, exit 0 (`-e` is false on ELOOP) |
| Link through a `chmod 000` directory | allow, exit 0 (`-e` is false on EACCES; a write fails anyway) |
| Relative payload `-n` naming a link | deny; `--` keeps it from being read as an option |

## Mutated-SUT run

- Mutation: `readlink -fn -- "$physical"` was changed to
  `readlink -n -- "$physical"`, by exact string replacement in place.
- Result: `follows a chain of leaf symlinks` failed (6 failures). The
  single-link and allow tests stayed green, as expected: the single link is
  absolute and one hop.
- Restore: done by the inverse replacement. `grep -c 'readlink -n --'` returned
  0, `git diff` was empty, and the suite passed after the fix.
- Not pinned, by design: removing the `-e` gate. GNU `readlink -f` would then
  follow a dangling link into the copy and deny it. That is stricter, not wrong,
  and the residual is stated in the comment.

## Fixes Applied

- `toolkit/dogfood.sh`, comment above `pre_tool`:
  - replaced the false dangling-link fallback claim;
  - named the unresolved-leaf cases;
  - gave "its own sensitive-file ask" an explicit referent;
  - reflowed the paragraph to 80 columns.

## Requirements Validation

| Requirement | Status | Evidence |
|---|---|---|
| D6: physical comparison, an existing leaf symlink resolved in full | Satisfied | `pre_tool` leaf branch; the three slice tests; the chain probe |
| Item 1.2 interface: exit 0 always, empty stdout when allowing | Satisfied | Probes above: dangling, loop and unenterable are all allowed silently with exit 0 |

## Positive Observations

- The `&& printf x` / `${physical%x}` shield together with `-n` keeps a newline
  at the end of a target intact. The probe confirms it.
- The `-e` gate lines up with Claude Code's own nearest-existing-ancestor walk.
  It also keeps `readlink -f` off the one input class where GNU and BSD
  disagree.
- A link to a directory is already resolved by `physical_path`, so this branch
  only ever sees non-directory leaves. The inline comment "physical_path
  resolves directories only" says exactly that.

## Verification

- `bash tests/dogfood-test.sh`: all dogfood scenarios passed.
- `shellcheck toolkit/dogfood.sh`: clean.
