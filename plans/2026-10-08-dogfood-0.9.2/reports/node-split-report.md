# Node split report (m3, m6)

## Task A (m3)

Verified on git 2.47.3 in a scratch repo under `$TMPDIR`:
`git ls-files --recurse-submodules -s` exits 0, and
`git ls-files --recurse-submodules -o -i --exclude-standard --directory` exits
128 with `fatal: ls-files --recurse-submodules unsupported mode`.

The parenthesis in the source-set section now reads
`(`--recurse-submodules` does not support `-o`)`. To keep the line at 80 columns
with no added line, "does not enter" became "never enters" in the same sentence
(the full form is 81 columns). The dated record
`docs/changelog/2026-10-08-dogfood-no-copy-remedy-and-submodule-ignores.md` is
untouched.

## Task B (m6)

### Seam

Sync decisions (what the copy holds, when it is promoted, how a failed sync
reports) against the launcher around the copy (why a copy, the guards, the shim,
hook wiring, migration, probes). Chosen from the content: the first group shares
one script subcommand (`sync`) and one set of probes (rsync, git ls-files, Q2
timings); the second group shares the Claude Code behaviour it rests on
(realpath, hooks, `CLAUDE_CODE_PLUGIN_DIRS`) and the Q3 probes.

- `docs/references/dogfood-sync.md` (new, 177 lines): The source set; The plugin
  root is the repo root; Sync only on `just dogfood` (with its "A launch with no
  copy warns" subsection); Sync failure is loud; `just dogfood`; and a "Bounds
  accepted" section holding the six bounds that concern the sync (macOS rsync,
  benign rsync exits, copy lags, promotion is repo-wide, sandboxed sync cannot
  read `.mcp.json`, copy carries non-plugin content).
- `docs/references/dogfood.md` (now 234 lines): The problem; A real copy; One
  script, three subcommands; The copy guard; The session check; The shim;
  `install.sh` wires the hooks; The migration is a note; Probe evidence; and
  "Bounds accepted" holding the three remaining bounds (Claude Code drift,
  children inherit the variable, only tool edits to the copy are guarded).

Sections moved whole; the Bounds section was split by bold paragraph, each
paragraph moved verbatim under a repeated "Bounds accepted" heading.

### Text changes beyond moving

- `dogfood.md`: one added sentence in the intro pointing to `dogfood-sync.md`;
  in the shim paragraph,
  `(see "A launch with no copy warns and starts without it")` gained
  ` in dogfood-sync.md (as a link)` (the section moved, so the plain-title
  pointer would dangle), and the paragraph was re-wrapped to 80 columns.
- `dogfood-sync.md`: new H1 and a five-line intro pointing back to `dogfood.md`
  and the hub. The two internal `see "Sync failure is loud"` pointers stay valid
  because that section moved with them.
- Remaining "below"/"above" references still resolve in place ("Q3 probe below"
  and "as above" are both in `dogfood.md`).

### Files touched

- `docs/references/dogfood.md` (edited), `docs/references/dogfood-sync.md` (new,
  untracked; I did not `git add`).
- `docs/design.md`: the dogfood group heading (line 209) now links both nodes:
  `### The dogfood launcher — references/dogfood.md (as a link), references/dogfood-sync.md (as a link)`.
  No conclusion was changed. The group's bullets map to both nodes and the
  heading is the only pointer.
- `CLAUDE.md`: only the Layout bullet for `docs/references/*.md`; the list of
  node names gained `dogfood-sync` (re-wrapped over the same three lines). The
  sentence "one node per group of decisions" now has one group with two nodes;
  left as is, say if you want it reworded.

### Pointers examined and left alone

- `docs/references/distribution.md:150` links `dogfood.md` for the `install.sh`
  hook wiring, which stayed in `dogfood.md`.
- `docs/changelog/*`, `plans/*`, `.claude/handoff-todo.md`: frozen or not mine.
- No test pins the old node's name or line content (`grep` over `tests/`,
  `toolkit/`, `README.md`, `toolkit/README.md`: no reference to
  `references/dogfood.md`). `tests/dogfood-sync-test.sh` matches only by
  filename coincidence. Nothing to report.
- Not edited: `docs/changelog.md` (it shows as modified in the tree; that is the
  other agent's), `toolkit/`, `tests/`, `inbox/`. No changelog entry added.

### Checks (foreground)

- `bash tests/docs-test.sh`: pass (cap and pointers).
- `bash tests/doc-sync-test.sh`: pass.
- `bash tests/dist-tree-test.sh`: pass.
- `bash tests/citation-test.sh`: pass.
- `wc -l`: `dogfood.md` 234, `dogfood-sync.md` 177.
- `.venv/bin/rumdl check docs/references/ docs/design.md`: one finding,
  `dogfood-sync.md:105` MD013 (a 101-column inline code span, the
  `dogfood: no copy at ...` message). It is the same line that was flagged at
  `dogfood.md:129` before the split, so it is pre-existing, not new.
- Losslessness: multiset of stripped non-blank lines, post-m3 old file against
  the union of the two new files. Lost: only the two lines of the shim paragraph
  that I re-wrapped. Added: the cross-reference lines, the two new headings
  (`# The dogfood sync`, repeated `## Bounds accepted`), the new intro and the
  re-wrapped shim lines. No argument text lost.

Not run, per instructions: `just precommit`, `just format-docs`.
