# Recall artifact — deliverable-review fix pass

Memory entries selected at the `/runbook` implementation-recall checkpoint,
2026-09-19. Planning-relevant only; execution-level detail reaches executors
through dispatch prompts, not this file.

The root `memory/MEMORY.md` index is over Claude Code's loader cap and did not
load this session, so selection ran against `rg --files memory/` filenames — the
degraded path `edify:recall` step 2 prescribes. Treat the list below as
under-selected rather than exhaustive.

## Selected

- `memory/ddaanet/claude-plugin-dev.md` — what this repo is and where its two
  manuals live. Bounds the pass: `toolkit/` is the shipped boundary, so Items
  4.1 and 4.4 edit files every consumer vendors.
- `memory/ddaanet/commit-bundling.md` — each code change rides with the test
  that proves it and the comment that documents it; nothing is carved out of a
  commit silently. The runbook's Gate section cites it, and it is why no cluster
  B item commits its mutation.
- `memory/ddaanet/git-protocol-file-allow.md` —
  `fatal: transport 'file' not allowed`; the child *clone* reads
  `protocol.file.allow`, so fixture-repo config cannot supply it and
  `git -c protocol.file.allow=always` is required. Load-bearing for Item 2.3's
  submodule fixture, and the reason the outline calls that flag required rather
  than optional.
- `memory/ddaanet/uv-direnv-venv.md` — no `uv run` under Claude Code; `uv sync`
  materializes `.venv` and direnv puts it on PATH. `just format-docs` finds
  `rumdl` that way, and it runs inside `just precommit`, the gate every item
  must pass.
- `memory/ddaanet/sandbox-effects.md` — the command sandbox distorts git,
  `$TMPDIR` and background-job visibility. Relevant to executors running the
  suites and to any dispatch that hardcodes a scratch path.

## Not selected, and why

No entry matched the phase-typing question (whether a mutation-verified fixture
change is `tdd` or `general`), which is the pass's one planning fork. The
runbook resolves it in its "Phase typing" section and states the deviation.

Two facts the task frame lists as **queued but unwritten**, behind the
`memory/MEMORY.md` loader-cap audit, bear directly on this pass and are worth
re-reading from the frame rather than from memory:

- to test a property a `set -o` line currently masks, run a `sed`-stripped copy
  of the script with that line removed, as `tests/release-test.sh` already does
  for `pipefail` — Items 1.1 and 1.2 both depend on this;
- Claude Code installs a `grep` *shell function* wrapping ugrep, so probing grep
  behaviour by hand measures ugrep and not the `/usr/bin/grep` a script gets.
  This produced a wrong EPIPE threshold before it was caught, and is why Item
  1.2's bound is ≥1 MB rather than the measured GNU grep 3.11 figure.
