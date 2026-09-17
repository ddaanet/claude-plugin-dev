# Task — Phase 1 complete, awaiting a call on three referred findings

## Current task

Executing `plans/2026-09-15-first-release-version/runbook.md` via `/orchestrate`
(edify). 12 items, four phases. **Phase 1 is COMPLETE and checkpointed** at
`f2d5f25` — 57 scenarios green, `just precommit` green, verify-step CLEAN.

### Phase 1, as landed (all four items, all reviewed)

- **Item 1.1** — initial release detected by absence of a semver tag.
  `semver_tags` (`^v[0-9]+\.[0-9]+\.[0-9]+$`, absorbs grep status 1 only),
  `release_tags` (`git tag --list 'v*' --sort=-v:refname | semver_tags`),
  `latest_tag` routed through the filter, `marketplace_entry_exists` conjunct
  dropped from detection. FR-1/2/3.
- **Item 1.2** — the lost-tags origin probe, first in `release_preflight`.
  `origin_release_tags` reads `git ls-remote --tags --sort=-v:refname origin`,
  captured once with its status read. Decision 1's hint branch at the
  `check-version.sh` failure point, gated on a `verifiably_unpublished` flag.
  FR-4/8.
- **Item 1.3** — `common_preflight` refuses a diverged push route
  (`remote.origin.pushurl`, `branch.$branch.pushRemote`, `remote.pushDefault`),
  before any side effect, both modes, reading `--get-all` and advising
  `--unset-all`. FR-6.
- **Item 1.4** — `resume_preflight`'s no-tag refusal picks its hint from ONE
  `origin_release_tags` read. Four branches in this order: origin membership
  (`grep -qxF`) → origin non-empty → no local tags → else. A failed listing is
  absorbed to the branch that claims least, never fatal. FR-5.

### Dispatch protocol in use

Strict sequential, one dispatch per message. Per tdd slice: RED
(`edify:test-driver`, sonnet) → test review (`edify:corrector`, opus) → GREEN
(test-driver) → code review (corrector). Reports at
`plans/2026-09-15-first-release-version/reports/<dispatch name>.md`; agents
reply with the path only. Orchestrator commits review fixes, then runs
`bash /Users/david/.claude/plugins/cache/ddaanet/edify/0.2.0/skills/orchestrate/scripts/verify-step.sh`
— **must run with `dangerouslyDisableSandbox: true`**.

**Batching lesson from this run:** when a slice's GREEN implements the
runbook's *declared interface* rather than just that slice, later slices pass
on arrival and become characterization guards. That happened to Item 1.2
slices 2-5 and was handled by batching them into one test-writing dispatch
whose scenarios are proven by *mutation* instead of by failing against
unchanged code. Item 1.4's four slices were batched from the start for the
same reason (one hint ladder, not four features). Do this deliberately, and
say in the dispatch which case obtains.

### Review technique that repeatedly earned its keep

Reviews that *ran* probes found real defects; reviews that read did not. The
highest-value probe is writing the plausible WRONG implementation and seeing
whether the suite catches it. That found: a fail-open detection predicate, a
half-proved contract, an unpinned `sed` address, a hint that would have been
dropped unconditionally, a needle (`other`) matched by ordinary English
(`another`), and two wrong ladder shapes that passed every delivered scenario.

### Environment caveats (carry in every dispatch prompt)

- The Bash sandbox binds `$HOME` dotfiles into the repo working directory, so
  `git status` inside a script or nested `bash -c` lists `.bashrc`, `.zshrc`,
  `.gitconfig`, `.idea`, `.mcp.json`, `.claude/agents` as untracked. The real
  tree is clean; a plain top-level `git status` is accurate. Never stage or
  delete them; `git add -A`/`git add .` fail against them. Stage explicit paths.
- **`$TMPDIR` is unset in dispatch shells** — every dispatch hit this. Use an
  explicit absolute path under `/tmp/claude-1000`.
- **This box is ~2GB and OOM kills things.** One dispatch at a time, one suite
  invocation at a time. A background commit job was killed mid-run once (its
  work had already landed — check `git log` before redoing anything).
- Run `just format-docs` BEFORE staging a report, or the pre-commit hook
  reflows it after staging and leaves the tree dirty.

### Next action

Open **Phase 2** — Item 2.1, `toolkit/version-guard.sh`'s message branch, 6
slices, independent of Phase 1. First apply the `release.sh:235` fix if
approved (see the todo's open decisions).
