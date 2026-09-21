## Open decisions

- Whether the fix pass warrants a toolkit release: it changed shipped files
  (`toolkit/release.sh` and `toolkit/version-guard.sh` in comments and deny
  wording only, `toolkit/README.md` in prose). No behaviour changed, so the
  case for a release is the manual's new text reaching consumers.

## Remaining

- Open findings from the run that nobody acted on: `reports/item-3-5.md`'s
  heading calls the fifth citation "stale" against its own opening line (frozen
  record, the changelog carries the right number); Item 3.4's `grep -q --`
  conversion is safe by construction, not by measurement; three Phase 1
  test-only slices have no GREEN report.
- `/gitlore:index-audit` on the root `memory/MEMORY.md`, which is over Claude
  Code's loader cap and does not load, so recall runs against
  `rg --files memory/` filenames. Twelve facts are queued unwritten behind it:
  - mutation-test a refusal's *prose*, not only its decision;
  - to test a property a `set -o` line currently masks, run a `sed`-stripped
    copy of the script with that line removed, as `tests/release-test.sh` does
    for `pipefail`;
  - `git-config-multivalued-read` warns against `git config -z --get-regexp`
    when the key is interpolated, while `shared-claude.md`'s always-on
    whitespace rule names that exact form as a default, with no routing cue
    between them;
  - Claude Code installs a `grep` *shell function* wrapping ugrep, so probing
    grep behaviour by hand measures ugrep and not the `/usr/bin/grep` a script
    actually gets;
  - ralph-loop's completion-promise path can fail to match a `<promise>` tag
    that is byte-identical to the stored promise, so `--max-iterations` is the
    reliable backstop;
  - rumdl's MD013 reflow joins a paragraph's continuation lines, so a runbook
    item whose `Requirements:`, `Model:` and `Change:` fields are continuation
    lines is destroyed by `just format-docs`. Nested bullets survive it;
  - `tests/docs-test.sh` selects its files with `git ls-files`, so a new
    untracked document passes the 400-line cap trivially and only fails on the
    commit that tracks it. Check `wc -l` directly while drafting;
  - `/orchestrate` composes one dispatch per *item* and names it `item-N-M`, so
    merging items is the only mechanism that delivers one agent per file;
  - a local rule duplicating a convention proposed upstream rots silently once
    upstream ships it, because nothing in this repo learns of that. Prefer a
    check, which is not prose and cannot become a duplicate; and an assertion
    of *equality* cannot be mutation-gated by swapping in another equal value;
  - nested subagent spawning works (verified against CC docs and a live probe:
    three layers below the main conversation, `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`,
    background subagents keep `Agent`). The orchestrating layer must be
    `general-purpose`: `edify:*` agents enumerate their tools without `Agent`,
    and the `claude` type carries a background-job narration protocol. One opus
    delegate carries about one heavy `/orchestrate` phase before its context
    fills, so phase-boundary resume blocks are the unit of handoff, and skill
    approval gates come back as the delegate's final message, answered with
    `SendMessage`;
  - a delegate's sandbox refuses SSH to `github.com:22` exactly as the main
    session's does, and a well-behaved delegate stops there: a dispatch whose
    skill fetches (`/gitlore:merge`) names the host to declare in
    `allowed_domains` up front;
  - during a delegated run two staged files outside the work were unstaged and
    rewritten mid-phase, consistent with a child running `git stash` then
    `git stash pop` (cause unconfirmed). Executor prompts forbid `git stash`,
    `git reset` and blanket `git add`, and name any pre-staged files as state to
    check after every commit.
- An intermittent suite failure that appears only inside a combined `just
  precommit` and passes standalone immediately after. First seen 2026-09-17 in
  `tests/release-test.sh`, at `release: still refuses a genuinely dirty
  non-memory path in the marketplace repo`; on 2026-09-20 three more sightings
  in that suite at different scenarios, and one in
  `tests/version-guard-test.sh`, where a steady-state scenario got the
  initial-release wording — it saw no tags where its fixture provides them. Two
  suites and a combined-run-only signature point at cross-suite interference (a
  shared scratch path, a leaked git environment, a `PATH` stub outliving its
  scenario) and not at any one assertion. Uninvestigated; about one run in ten.
