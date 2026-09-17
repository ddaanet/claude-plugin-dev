## Current task

Executing `plans/2026-09-15-first-release-version/runbook.md` via `/orchestrate`
(edify). 12 items, four phases. **Phases 1 and 2 are implemented and Phase 2's
corrector checkpoint has run.** What resumes: Phase 3's six inline docs items
(3.1-3.6, orchestrator executes them directly, no dispatch), stopping before
Phase 4.

### The invariant Item 2.1 rests on

A `PreToolUse` hook exiting non-zero for any status but 2 is a non-blocking
error and the refused edit proceeds. So after the deny is decided, every status
must be absorbed; `set -e` reaching anything there is a silent total bypass.
This inverts the usual capture-the-status rule. The semver filter now binds its
status to its own capture with `||` rather than reading `$?` as the first
statement of an errexit-live branch body. The region is still errexit-live: what
that restructure removed is the silent clobber, not the exposure. Full argument
and probe transcripts in `reports/item-2-1-hook-exit-status-contract.md`; the
composed review is `reports/phase-2-corrector.md`.

### The review technique that keeps earning its keep

Reviews that *ran* probes found real defects; reviews that read did not. The
highest-value probe is writing the plausible **wrong** implementation and seeing
whether the suite catches it — including mutating the **prose** of a refusal,
not just its decision. The Phase 2 checkpoint found the no-bypass sentence could
be deleted from either deny message, or a `.claude/settings.json` escape hatch
added to either, with the suite staying green.

### Dispatch protocol in use

Strict sequential, one dispatch per message. Per tdd slice: RED
(`edify:test-driver`, sonnet) -> test review (`edify:corrector`, opus) -> GREEN
-> code review. Reports at `plans/2026-09-15-first-release-version/reports/`;
agents reply with the path only. Orchestrator commits review fixes, then runs
`bash /Users/david/.claude/plugins/cache/ddaanet/edify/0.2.0/skills/orchestrate/scripts/verify-step.sh`
— **must run with `dangerouslyDisableSandbox: true`**. Phase 3 needs none of
this; the `edify:tdd-auditor` at completion does.

When a slice's GREEN implements the runbook's declared interface rather than
just that slice, later slices pass on arrival and become characterization guards
proven by **mutation** instead of by failing against unchanged code. That
happened to Item 1.2 slices 2-5, all of Item 1.4, and Item 2.1 slices 2-4. Do it
deliberately and say in the dispatch which case obtains.

### Environment caveats (carry in every dispatch prompt)

- **`$TMPDIR` is unset in dispatch shells.** Use an explicit absolute path under
  `/tmp/claude-1000`.
- **A commit outruns the 120s Bash timeout** — the pre-commit hook runs the full
  `just precommit`. Run commits with `run_in_background: true`.
- The Bash sandbox binds `$HOME` dotfiles into the repo working directory, so
  `git status` inside a script or nested `bash -c` lists `.bashrc`, `.zshrc`,
  `.gitconfig`, `.idea`, `.mcp.json`, `.claude/agents` as untracked. The real
  tree is clean; a plain top-level `git status` is accurate. Never stage or
  delete them; `git add -A`/`git add .` fail against them. Stage explicit paths.
- **This box is ~2GB and OOM-kills things.** One dispatch at a time, one suite
  invocation at a time.
- **gitmoji's commit-msg hook rewrites a conventional-commit prefix to an emoji,
  which rewrites the commit and changes its hash.** Read a hash from `git log`
  after the fact, never from a report that predicted it.
- Run `just format-docs` BEFORE staging a report, or the pre-commit hook reflows
  it after staging and leaves the tree dirty.
- **Reports must stay under 400 lines** — `tests/docs-test.sh` enforces the cap
  over `docs/` and `plans/`. Tell each dispatch up front.
