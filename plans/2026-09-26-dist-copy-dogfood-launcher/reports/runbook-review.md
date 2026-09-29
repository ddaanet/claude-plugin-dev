# Runbook Review: dist-copy dogfood launcher

**Artifact**: plans/2026-09-26-dist-copy-dogfood-launcher/runbook.md **Design**:
plans/2026-09-26-dist-copy-dogfood-launcher/outline.md (no design.md)
**Requirements input**: plans/2026-09-26-brief-dist-copy-dogfood-launcher.md (no
IDs; the outline's Key decisions D1–D12 stand in) **Date**: 2026-09-29 **Mode**:
review + fix-all

## Summary

The runbook traces all twelve decisions, keeps the gate bookkeeping where
`dist-tree-test.sh` and `doc-sync-test.sh` force it, and its slices are specific
enough to execute. The review found no Critical issues. It found five Major
ones: a slice-4 fixture that contradicted slice 1's assertion in the same
install scenario, a watchdog (`timeout`) macOS does not ship, a PATH that would
have made the shim's own shebang fail, a `git check-ignore` trap on a first
sync, and three docs that still describe install.sh as wiring one hook. All were
fixed in place. The runbook is 392 lines after `just format-docs` (cap 400).

**Overall Assessment**: Ready

## Requirements Coverage

| Requirement | Phase | Items | Coverage | Notes |
|---|---|---|---|---|
| D1 real copy | 1 | 1.1 | Complete | 1.1/1 asserts `-f`, not `-L`, and `cmp` |
| D2 source set | 1 | 1.1 | Complete | 1.1/1–5; residual on the hard exclude stated |
| D3 root = repo root | 1 | 1.1 | Complete | 1.1/6 refusal |
| D4 promotion only | 2, 3 | 2.1, 3.1 | Complete | no `PostToolUse` anywhere |
| D5 one script, own location | 1 | 1.1–1.3 | Complete | 1.1/1 runs with a foreign cwd and `CLAUDE_PROJECT_DIR` |
| D6 copy guard | 1, 2 | 1.2, 2.2 | Complete | 2.2 added (it wires the matcher) |
| D7 session-start | 1, 2 | 1.3, 2.2 | Complete | 2.2 added |
| D8 loud failure | 1, 2, 3 | 1.1, 2.1, 3.1 | Complete | 3.1 added (inherits 1.1/7) |
| D9 shim | 2, 3 | 2.1, 3.2, 3.3 | Complete | 3.2 and 3.3 added (`.envrc`, docs) |
| D10 `just dogfood` | 3 | 3.1 | Complete | `_import-check` pins it |
| D11 install wiring | 2, 3 | 2.2, 3.3 | Complete | fresh-settings branch now tested (2.2/5) |
| D12 migration note | 3 | 3.2 | Complete | `v0.9.0.md` against `toolkit/VERSION` 0.8.0 |

The brief's points all trace too: its sync-on-edit and `Bash`-matcher options
are superseded by D4, the `clean` requirement is in 3.2 and 3.3, whitespace
safety is in the space-bearing fixture and 1.1/3, and the precommit gate is in
the bookkeeping.

## Review Findings

### Critical Issues

None.

### Major Issues

1. **2.2/4 contradicted 2.2/1 in a shared fixture**
   - Location: Item 2.2, slice 4.
   - Problem: "the fixture's `PreToolUse` gains an entry with matcher `Bash`
     carrying the exact pre-tool command" edits the one scenario's fixture
     before install. Install then adds no pre-tool entry, so slice 1's "its
     matcher `Write|Edit|NotebookEdit`" fails. The version-guard half, "under a
     matcher-less entry", is already true of today's install.sh
     (`.matcher == null` counts as present), so it tested nothing new.
   - Fix: slice 4 now runs after slice 2's re-run. It rewrites the matchers of
     the pre-tool and version-guard entries to `Bash` and installs again, and
     the file must be byte-identical. The mutation is named: restore today's
     null-or-`Write|Edit` test.
   - **Status**: FIXED

2. **`timeout 10` is not on macOS**
   - Location: Item 2.1, slice 3.
   - Problem: no suite in this repo uses `timeout`, and macOS ships none. The
     outline names a suite run on a macOS consumer as the check for the macOS
     rsync risk, so a GNU-only watchdog would break exactly that run.
   - Fix: added a watchdog fixture (run in the background, kill after 10 s, fail
     on the kill), and slice 3 now uses it.
   - **Status**: FIXED

3. **2.1/3's PATH had no system directories**
   - Location: Item 2.1, slice 3.
   - Problem: PATH = `<root>/plugin-dev/bin/:<root>/plugin-dev/bin:<stubdir>`
     leaves `#!/usr/bin/env bash` unable to find `bash`, and `dogfood.sh sync`
     unable to find `git` or `rsync`. The test would fail at exit 127 for a
     reason unrelated to stripping.
   - Fix: `:$PATH` appended. The stub still wins, because `<stubdir>` comes
     first.
   - **Status**: FIXED

4. **`git check-ignore dist/plugin` misses `/dist/plugin/` on a first sync**
   - Location: Item 1.1 Interfaces (the 1.1/6 refusal).
   - Problem: probed on git 2.47.3. With `.gitignore` holding `/dist/plugin/`
     and no `dist/plugin/` on disk, `git check-ignore -q dist/plugin` exits 1
     and `git check-ignore -q dist/plugin/` exits 0. A check written the first
     way refuses every consumer's first launch. 1.1/1's fresh fixture would go
     red, but the easy "fix" of pre-creating the directory in the fixture would
     hide the bug.
   - Fix: an Interfaces line saying the check asks about `dist/plugin/` with the
     trailing slash, and why.
   - **Status**: FIXED

5. **Docs still said install.sh wires one hook (semantic propagation)**
   - Location: Items 3.3, 3.4, 3.5, 3.6.
   - Problem: the refactor changes install.sh from one hook to three and changes
     the idempotency rule. Several places describe the old shape or were not
     covered:
     - `docs/references/distribution.md`, "Single `install.sh` handles bootstrap
       and wire", says it "appends one hook".
     - `CLAUDE.md`'s Conventions bullet on `hook_cmd`'s quoting covers
       version-guard only.
     - `toolkit/README.md`'s `release.just` Contents bullet lists the recipes,
       and `dogfood` was missing from it.
     - The root `README.md` has a Requirements section of its own, and it did
       not gain `rsync`.
   - Fix: added each place to its owning item: distribution.md to 3.5, the
     Conventions bullet to 3.6, the Contents bullet to 3.3, and root
     Requirements to 3.4.
   - **Status**: FIXED

### Minor Issues

1. **The fresh-settings branch of install.sh was untested**
   - Location: Item 2.2.
   - Problem: the only settings scenario starts from an existing file. A GREEN
     that keeps the separate from-scratch document would wire no dogfood hooks
     into any new consumer, and every test would still pass.
   - Fix: the item text now says the no-settings branch seeds `{}` and goes
     through the same function. New slice 2.2/5 asserts all three commands in
     the existing `install.sh: no ref resolves the newest dist tag` scenario,
     whose fixture has no `settings.json`.
   - **Status**: FIXED

2. **Outline Risks had no destination in `docs/`**
   - Location: Item 3.5.
   - Problem: most of the outline's Risks stay true once the work ships:
     - CC drift and its re-run procedure
     - benign rsync exits
     - repo-wide promotion
     - the inherited variable
     - unguarded Bash writes
     - non-plugin content in the copy

     Only two of them (subdirectory launch, macOS rsync) were routed to
     Limitations. The rest would have lived only in a frozen plan.
   - Fix: 3.5's node now carries them.
   - **Status**: FIXED

3. **Missing `Depends on:` declarations**
   - Location: 2.2 (uses 1.2's and 1.3's subcommand names), 3.2 (its
     `PATH_add plugin-dev/bin` step is 2.1's shim).
   - Fix: added `Depends on: Item 1.2, Item 1.3` to 2.2, and `Item 2.1` to 3.2.
   - **Status**: FIXED

4. **2.2's Requirements omitted D6 and D7**
   - Location: Item 2.2.
   - Problem: 2.2 wires D6's `Write|Edit|NotebookEdit` trigger and D7's
     matcher-less `SessionStart` entry, but listed only D11.
   - Fix: added D6 and D7, with matching rows in the mapping table.
   - **Status**: FIXED

5. **Mapping-table rows narrower than the items**
   - Location: Requirements mapping, rows D8 and D9.
   - Fix: D8 gains 3.1 and D9 gains 3.2 and 3.3.
   - **Status**: FIXED

6. **Fixture ambiguities**
   - Location: Fixtures section.
   - Problem: two things were ambiguous:
     - The fixture's `.gitignore` holds only `/dist/plugin/`, while tests need
       `build.log`, `out dir/` and `*.log` ignored.
     - `<root>` was not pinned to the physical spelling. macOS `mktemp` paths
       sit under `/var` → `/private/var`.
   - Fix: "Each test appends the ignore patterns it needs", and `<root>` is the
     fixture's `pwd -P` spelling.
   - **Status**: FIXED

7. **doc-sync's rule stated one-way**
   - Location: "Two gates" paragraph.
   - Problem: the paragraph said every shipped path must appear. The test
     requires the backtick-quoted `toolkit/` paths to equal the shipped set, so
     an extra path such as `toolkit/bin/` also fails.
   - Fix: reworded the paragraph.
   - **Status**: FIXED

8. **install.sh's own text not named**
   - Location: Item 2.2.
   - Problem: the header's step list ("3. wire the version-guard hook") and the
     `changed+=("… (added version-guard hook)")` label would go stale.
   - Fix: 2.2 now names both.
   - **Status**: FIXED

9. **Growth projection: test suites near or over the cap**
   - Location: Phase 1; Item 2.2.
   - Problem: two suites are at issue:
     - `tests/update-plugin-dev-test.sh` is 406 lines and grows by about 40. The
       outline accepts this (item 4), but the runbook did not say so.
     - `tests/dogfood-test.sh` is projected at 300–400 lines across 1.1–1.3.
   - Fix: 2.2 carries an explicit out-of-scope note. Phase 1 asks the executor
     to report the suite's line count at the phase end and to return a split to
     the planner if it passes 400. The split would change 3.6's suite list and
     the precommit wiring, so it is a planning call, not a reviewer's.
   - **Status**: FIXED (a measurement trigger stands in for the decision)

10. **Post-phase state for `justfile` in 3.1**
    - Location: Item 3.1.
    - Fix: added a note that `precommit` already carries 1.1/1's and 2.1/1's
      lines, and that 3.1 touches only `_import-check`.
    - **Status**: FIXED

### Checked and left as is

- **Slice 1s that carry several tests** (1.1/1, 2.1/1). Each one is the external
  contract. 1.1/1's naive GREEN (a `--files-from` sync) is exactly what makes
  1.1/2 genuinely red, so splitting it would cost the planned red.
- **Slices whose GREEN predecessor may already pass them**: 1.3/3, 2.2/2, 2.2/3
  and 1.1/4. The runbook's "Genuine red" rule already requires a stated mutation
  for these.
- **1.3's "no jq → copy check skipped"**. This refines D7 (the static message
  cannot carry a path jq would have to quote) and does not contradict it.
- **No code blocks, no model lines, and no decision language** ("choose",
  "decide", "determine"). Field lines are nested bullets and survived the
  reflow.

## Fixes Applied

- "Two gates": doc-sync stated as set equality.
- Fixtures: ignore patterns per test; `<root>` is `pwd -P`; new watchdog
  fixture.
- Mapping table: rows D6, D7, D8 and D9 widened.
- Phase 1: suite-size measurement trigger.
- 1.1 Interfaces: `check-ignore` with the trailing slash.
- 2.1/3: `:$PATH` appended; watchdog replaces `timeout 10`.
- 2.2:
  - fresh branch seeded with `{}`
  - header and `changed` label
  - out-of-scope suite split
  - D6 and D7 added
  - `Depends on: 1.2, 1.3`
  - slice 4 rewritten
  - new slice 5
- 3.1: post-phase note.
- 3.2: `Depends on: 2.1`.
- 3.3: the `release.just` Contents bullet names `dogfood`.
- 3.4: root README Requirements gains `rsync`.
- 3.5: distribution.md section, and the outline Risks in the node.
- 3.6: the `hook_cmd` Conventions bullet.

## Design Alignment

The items follow the outline's decisions without contradiction:

- the copy is built with the ignore-list `rsync` (D2);
- the root is found from the script's own location (D5, D9);
- the deny is split three ways (D6);
- the variable is compared entry by entry, physically (D7);
- nothing syncs except at promotion (D4);
- `install.sh` wires `settings.json` only, with version-guard's spelling left
  alone (D11).

The migration note's steps and their order match D12. Repo facts were checked
against source, not assumed:

- `dist-tree-test.sh`'s exact list and its `migrations/` exemption;
- `doc-sync-test.sh`'s set equality;
- install.sh step 3's null-or-`Write|Edit` rule and its separate from-scratch
  branch;
- the scenario's matcher-less fixture;
- `_import-check`'s `resume-release` block and recap line;
- `release.just`'s `Requirements:` header;
- `toolkit/VERSION` = 0.8.0.

## Unresolved

Nothing blocks execution. One item is deferred on purpose: whether
`tests/dogfood-test.sh` splits is decided when Phase 1 ends, from its measured
line count.

**Final runbook length:** 392 lines after `just format-docs` (cap 400). Only
`runbook.md` and this report were written.
