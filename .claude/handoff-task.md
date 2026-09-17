## Current task

Executing `plans/2026-09-15-first-release-version/runbook.md` via `/orchestrate`
(edify). 12 items, four phases. **Phases 1, 2 and 3 are implemented**, Phase 2's
corrector checkpoint has run, and Phase 3's six docs items landed inline with no
dispatch. What resumes is Phase 4 — one outward-facing item — then the audit and
the run summary.

### Phase 4 is gated on my human partner

Item 4.1 is `just precommit`, then `just release minor` on the toolkit. Minor
because the toolkit is pre-1.0, where a minor bump is the conventional home for
a behaviour change, and a marketplace entry no longer disqualifying a first
release is one. Outward-facing and irreversible: run only on an explicit
go-ahead, never as an autonomous dispatch.

### What Phase 3 recorded

A first release is now detected by tag alone — no `vX.Y.Z` tag locally or on
origin, the marketplace entry playing no part — with the old two-part conjunct
rewritten in place as the overturned decision across `docs/design.md`, the three
`docs/references/` nodes, `toolkit/release.just`, `toolkit/README.md` and a
dated changelog record. The hub gained two recovery conclusions Item 3.4's
stated scope did not name (the origin probe's ordering, the push-route refusal),
because Item 3.3 introduced two decisions the hub was otherwise silent on.

### Settled bounds Phase 3 recorded rather than reopened

`toolkit/release.sh` is not split (791 lines = 380 code / 381 comment / 30
blank; the executable artifact is under the cap, the overage is argument prose
CLAUDE.md forbids shaving, and a second file is a new *shipped* path); the
marketplace-writability false refusal stays (fails closed, recovery works, code
and comment agree it is deliberate); the steady-state deny wording doubles as
the "don't know" answer and ships unqualified; the hardcoded eight-name `GIT_*`
`unset` list is right over `unset $(git rev-parse --local-env-vars)`, because
that discovery call is itself a `git` invocation and would clear nothing in
exactly the runs where the listing is unreliable.

### The review technique that keeps earning its keep

Reviews that *ran* probes found real defects; reviews that read did not. The
highest-value probe is writing the plausible **wrong** implementation and seeing
whether the suite catches it — including mutating the **prose** of a refusal,
not just its decision.

### Dispatch protocol in use

Strict sequential, one dispatch per message. Reports live at
`plans/2026-09-15-first-release-version/reports/`; agents reply with the path
only. The `edify:tdd-auditor` at completion reads every slice's RED, GREEN and
review reports.

### Environment caveats (carry in every dispatch prompt)

- **`$TMPDIR` is unset in dispatch shells.** Use an explicit absolute path under
  `/tmp/claude-1000`.
- **A commit outruns the 120s Bash timeout** — the pre-commit hook runs the full
  `just precommit`. Run commits with `run_in_background: true`.
- The Bash sandbox binds `$HOME` dotfiles into the repo working directory, so
  `git status` may list `.mcp.json`, `.bashrc`, `.zshrc`, `.gitconfig`, `.idea`
  and `.claude/agents` as untracked. The real tree is clean. Never stage or
  delete them; `git add -A` / `git add .` fail against them. Stage explicit
  paths.
- **This box is ~2GB and OOM-kills things.** One dispatch at a time, one suite
  invocation at a time.
- **gitmoji's commit-msg hook rewrites a conventional-commit prefix to an
  emoji**, which rewrites the commit and changes its hash. Read a hash from
  `git log` after the fact, never from a report that predicted it.
- Run `just format-docs` BEFORE staging a report, or the pre-commit hook reflows
  it after staging and leaves the tree dirty.
- **Reports must stay under 400 lines** — `tests/docs-test.sh` enforces the cap
  over `docs/` and `plans/`. Tell each dispatch up front.
