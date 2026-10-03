# Build summary: 2026-10-03-dogfood-review-fixes

**Status:** complete. Every outline item is done, both review groups returned
Ready with no UNFIXABLE, and the TDD audit found no open violation.

- **Baseline:** `f7a9bcf` ("pin the sync exclude list's root anchor", which is
  Major 2, done before this run).
- **Work:** `plans/2026-10-03-dogfood-review-fixes/outline.md`. There was no
  runbook, so I defined the items and slices at dispatch time. The list is
  below.

## Commits

| sha | subject |
|---|---|
| `9104046` | Item 1.1/1 — the shim syncs only outside a dogfood session of its own repo |
| `6b985df` | Item 1.1/1 — code-review fixes |
| `e77ca7d` | Item 1.1/2 — a failed sync at launch says claude was not started |
| `b6aa831` | Item 1.1/2 — code-review fixes |
| `d6df153` | Item 1.2/1 — pre-tool maps a jq failure to a non-blocking status |
| `0a2631d` | Item 1.2/1 — code-review fixes |
| `b8da498` | Item 1.3 — pin the payload cwd, CLAUDE_PROJECT_DIR and session-start symlink cases |
| `f000bce` | Item 2.1 — dogfood design and node amend D4/D9, changelog record |
| `58f24a1` | Item 2.2 — manuals, install pointer and migration note follow the review |
| `cb64414` | Finish — code and test review fixes |
| `3780b7d` | Finish — documentation review fixes |

The commit that adds this summary also carries `reports/tdd-audit.md`.

## Outline items

| Finding | Item | Status |
|---|---|---|
| Major 1, code | 1.1/1 (TDD: RED, test review, GREEN, code review) | done |
| m3 | 1.1/2 (TDD) | done |
| m1 | 1.2/1 (TDD) | done; status 1 chosen as the non-blocking status |
| Major 2 | — | done before the run (`f7a9bcf`), skipped as instructed |
| m10, m11, m12 | 1.3 (test-only, with a mutation proof per test) | done; the m12 move was completed in `cb64414` |
| Major 1, docs; m2; m8; m9; changelog record | 2.1 (opus) | done |
| Major 1, user-facing; m2 manual; m4; m5; m6; m7; m8 front page | 2.2 (opus) | done |

The behaviour now in place:

- **The shim and sync.** The shim skips the sync when `CLAUDE_CODE_PLUGIN_DIRS`
  exactly equals `<physical root>/dist/plugin`, and it exports the variable
  every time.
- **A failed sync.** The shim prints
  `dogfood: sync failed, so claude was not started` after the sync's own stderr,
  and exits with the sync's status.
- **pre-tool and jq.** `pre-tool` exits 1 on any jq failure, whether reading the
  payload or building the deny, and keeps jq's stderr.

## Reviews and what was done with them

Every reviewer applied its own fixes. I committed each review report together
with those fixes.

### Test reviews

- **1.1/1.**
  - Scenario 2 now reaches the shim through a symlinked spelling, which kills a
    logical-root mutant.
  - A new list-valued scenario kills an entry-match mutant ("equals", not
    "contains").
- **1.1/2.**
  - A stub-rsync scenario pins the sync's own status: exit 23, not a fixed 1.
  - The not-started pattern now requires `claude` as a word, so it cannot match
    through the temp path.
  - The empty-stderr check on a successful launch and the stdout check on a
    failed sync were added.
- **1.2/1.** A third scenario fails the deny-building jq call. Without it, a
  GREEN that mapped only the payload read would have passed.

### Code reviews

- **1.1/1.** The header now says why `<root>` must be physical. The reviewer
  recommended a glob-metacharacter root fixture, which Item 1.3 absorbed.
- **1.1/2.** The not-started line was restyled to match the other `dogfood:`
  messages: no backticks, single-quoted.
- **1.2/1.**
  - The comment's rationale was widened: jq 1.7 also exits 2, on usage and
    system errors, which the reviewer probed. "non-zero" now reads "exit 1".
  - The audit of every exit path found no path out of `pre_tool` that carries
    status 2.

### Finish, code and tests (`reports/review-code.md`)

- The m12 move had dropped the case's rejection half. It is restored in the
  session-start suite.
- The decoy payload `cwd` now comes from one helper.
- A redundant `unset` was removed.
- The m10 proof was re-run with a mutant that prefers the payload's `cwd` only
  when one is present. It is red on the current suite and green on the pre-m10
  suite, so the new field is what catches the mutant.
- The reviewer judged the suite lengths and took no action: launcher is 429
  lines and pre-tool 448, both over the 400-line soft guideline. Each suite is
  one cohesive script under test. If pre-tool grows again, its jq-failure group
  is the seam to split along.

### Finish, docs (`reports/review-docs.md`)

- `CLAUDE.md`'s Layout bullet for `toolkit/bin/claude` said the shim always
  syncs. It now states the condition.
- The node's "The migration is a note" summary now follows m5.
- The A→B effect is worded as "a `claude` that reaches B's shim", in the node
  and in the new changelog record.
- The hub's D4 bullet now says "of the same repository".
- One 85-column line in the manual was re-wrapped.

### TDD audit (`reports/tdd-audit.md`)

- **Slices.** The three behaviour slices comply on every check. The audit
  reproduced each RED against the parent commit's code, and every dogfood suite
  is green at every code commit.
- **Item 1.3: no test review.** The test-only item had no test-review dispatch,
  so its mutation proofs were not reproduced in-process. The closing review
  reproduced two of them, and the audit reproduced the other two (m11 and the
  glob root) in a `git archive` extract. All four proofs stand.
- **Item 1.3: the m12 move.** The move dropped the rejection half; fixed in
  `cb64414`.
- **Recommendations.** Give test-only items a test review. Keep RED reports in
  step with the scenarios added at test review. Record the item and slice map
  durably when there is no runbook; this summary is that record for this run.

## Execution notes

- **List revisions.** There was no runbook to revise. The 1.1/1 code review's
  glob-root recommendation was added to Item 1.3. Each test review added
  scenarios within its own slice.
- **Build baseline file.** `tmp/` is not git-ignored in this repo, so the
  skill's `tmp/build-baseline` made the post-item gate report DIRTY. I moved the
  file to `.git/edify-build-baseline`. Nothing was committed.
- **Post-item gate after 1.1/2.** `verify-step.sh`, run unsandboxed, reported
  DIRTY, listing only the zero-byte sandbox mask dotfiles in the repo root.
  `memory/ddaanet/sandbox-effects.md` documents unsandboxed readers seeing them.
  Tracked files were clean (`git status --porcelain --untracked-files=no`) and
  no other untracked file existed. I took the gate as clean. The full
  `just precommit` ran green in the pre-commit hook on every later commit.
- **Pre-commit format-docs.** It re-wrapped one staged report after staging
  (1.1/2's code review), which I fixed with `--amend`. After that, I ran
  `rumdl fmt` on each report before staging it.
- **Known flake.** It did not occur in any `just precommit` run.

## Left open

- **Node near the cap.** `docs/references/dogfood.md` is at 399 of 400 lines.
  The next addition to it needs a split.
- **Unprobed questions.** These are recorded in the node, the manual and the
  changelog record:
  - whether hooks fire twice in a script that wires the plugin's hooks into its
    own settings while the shim loads the copy (the gitlore evals);
  - how Claude Code treats an empty plugin-root `.mcp.json`;
  - whether `/reload-plugins` refreshes commands, `.mcp.json` and output styles;
  - the jq 1.6 parse-error exit status, which was read from source and not
    probed.
- **Out of scope, as the outline says.** The nested `CLAUDE.md` in the copy,
  case-insensitive APFS, and the pending macOS run of the sync suites.
- **Not done here.** No release, push or `update-plugin-dev` in consumers.
- **Follow-up.** `/deliverable-review plans/2026-10-03-dogfood-review-fixes`
  (opus, fresh session).
