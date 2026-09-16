## Current task

Executing `plans/2026-09-15-first-release-version/runbook.md` via `/orchestrate`
(edify). 12 items, four phases. **Phase 1 Item 1.1 is COMPLETE**; next dispatch
is Item 1.2 slice 1 RED.

### Landed so far (all committed, tree clean, `just precommit` green)

Item 1.1 — `toolkit/release.sh` detects the initial release by absence of a
semver tag. Three slices, each run as RED -> test-review -> GREEN -> code-review:

- `semver_tags()` — `^v[0-9]+\.[0-9]+\.[0-9]+$`, absorbs grep status 1 only.
- `release_tags()` — `git tag --list 'v*' --sort=-v:refname | semver_tags`.
- Detection predicate is now `[ -z "$release_tag_list" ]`, fed by
  `release_tag_list=$(release_tags) || die "could not list this plugin's release
  tags — nothing was done"`. That capture is a **fail-open fix**: the bare
  `[ -z "$(release_tags)" ]` form discarded a failed listing's status, so a
  broken `git tag` or a real grep error read as "never released" and would have
  tagged and published. The same discipline binds every new caller in Items 1.2
  and 1.4.
- `latest_tag` rebuilt from that same captured listing (not a second
  `release_tags` call — `$(release_tags | sed …)` would take `sed`'s status).
- `marketplace_entry_exists` conjunct dropped from detection; the variable stays
  for `bump_marketplace`. Header comment restated. Bump-refusal hint gained
  `commit that edit`.

Commits: `74c4733` (1.1/1), `979e285` (1.1/2), `3fd4d64` (1.1/3), plus
review-fix, report and guard-test commits (`9414fcb` pins which end of the
listing `latest_tag` takes).

### Dispatch protocol in use

Strict sequential, one dispatch per message. Per tdd slice, four dispatches:

- RED — `edify:test-driver` (sonnet), mode RED named in the prompt, writes the
  slice's tests only, proves each fails on its own assertion, **no commit**.
- test review — `edify:corrector` (opus). Mechanical check first (every test
  FAILED on an assertion, none PASSED/ERROR), re-running the suite itself rather
  than trusting the report; then wrong-reason hunting. Fixes tests, no commit.
- GREEN — `edify:test-driver` (sonnet), mode GREEN, narrowest implementation
  that passes this slice, commits `<type>: Item N.M/k — <title>`.
- code review — `edify:corrector` (opus), implementation only, may mutate the
  SUT in place once to prove the tests bind. No commit; the orchestrator commits
  its fixes.

Dispatch names: `item-N-M-s<k>-red` / `-test-review` / `-green` / `-code-review`,
`phase-P-corrector`, `final-review`, `tdd-audit`. Reports go to
`plans/2026-09-15-first-release-version/reports/<dispatch name>.md`. Every prompt
carries item text verbatim, the runbook's standing constraints, IN/OUT scope,
and design + recall artifact **by path** (`outline.md`, `recall-artifact.md`).

Verification after every committed dispatch:
`bash /Users/david/.claude/plugins/cache/ddaanet/edify/0.2.0/skills/orchestrate/scripts/verify-step.sh`
— **must run with `dangerouslyDisableSandbox: true`**, see below.

### Environment caveat (carried in every dispatch prompt)

The Bash sandbox binds `$HOME` dotfiles into the repo working directory, so
`git status` run inside a script or a nested `bash -c` lists `.bashrc`,
`.zshrc`, `.gitconfig`, `.idea`, `.mcp.json`, `.claude/agents` etc. as
untracked. The real tree is clean; a plain top-level `git status` is accurate
(the `git:*` exclusion). `git add -A` fails outright against them — stage
explicit paths. This is why `verify-step.sh` returns a false DIRTY sandboxed.
Already documented in `memory/ddaanet/sandbox-effects.md`; nothing new to write.

### Next action

Dispatch `item-1-2-s1-red` — Item 1.2 slice 1, the lost-tags origin probe.
Item 1.2 adds `origin_release_tags()` and runs it first in `release_preflight`,
before `check-version.sh` and before any side effect, only when `release_tags`
is empty. Six slices. `tests/release-test.sh` needs a helper that drops a tag
locally while leaving origin's in place (slices 1-4).
