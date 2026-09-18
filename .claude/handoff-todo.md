## Open decisions

- Scope of the fix pass. Four of the six Majors are in work the plan's
  outline never scoped — `scripts/self-release.sh` and
  `tests/self-release-test.sh` (Majors 1, 3, 4) — while two are in the
  plan's own deliverables: `toolkit/release.sh:307`'s `release_tags()`
  still resting on `pipefail` (Major 2), and `toolkit/version-guard.sh:3-7`'s
  header clause contradicting the file's own initial-release deny message
  (Major 6). Major 5 is `docs/references/version-guard.md:44-48`'s "cannot
  disagree" clause. Whether the self-release half is in scope for this pass
  is the fork.
- `outline.md:262` says the no-tag refusal has three hints; the code
  (`toolkit/release.sh:577`, `:585`, `:596`, `:603`), `runbook.md` Item 3.3
  and `docs/references/recovery.md:85-103` all say four. Whether to correct
  the executed outline or leave it as the dated record it is.
- Publish this repo's own gitlore memory store with `/gitlore:push`? The
  shared `ddaanet` tier was merged and published on 2026-09-17; the `memory`
  store's own remote was deliberately left alone, publishing it being wider
  than the tier merge that was asked for.

## Remaining

- `/edify:design` over the deliverable-review findings.
- Root `memory/MEMORY.md` is over Claude Code's loader cap, so entries past
  the cutoff never reach a session; `/gitlore:index-audit` addresses it.
  Three facts stay unwritten for that reason: mutation-test a refusal's
  *prose*, not only its decision; to test a property that a `set -o` line
  currently masks, run a `sed`-stripped copy of the script with that line
  removed, as `tests/release-test.sh:1427-1448` now does for `pipefail`;
  and `git-config-multivalued-read` warns against `git config -z
  --get-regexp` when the key is interpolated, while `shared-claude.md`'s
  always-on whitespace rule names that exact form as a default, with no
  routing cue between them.
- `tests/release-test.sh` failed once on 2026-09-17, at "release: still
  refuses a genuinely dirty non-memory path in the marketplace repo", and
  has been clean on five subsequent full runs of the suite. Unreproduced
  and unexplained; that scenario is where to look if it recurs.
