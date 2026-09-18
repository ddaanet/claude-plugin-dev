## Open decisions

- A2 (outline item 3) — the EPIPE fix at `toolkit/release.sh:577` is bounded to
  hint quality, and pinning it needs an origin tag listing over 64 KiB. Stub
  `git ls-remote` with a `seq`-driven printf, create ~8 000 real tags (minutes
  on every `just precommit`), or land the herestring untested on the grounds
  that it is structurally immune to EPIPE?
- B2 (outline item 6) — the `':(exclude)memory'` half of
  `scripts/self-release.sh:56` needs a real submodule in the self-release
  fixture to construct a gitlink ahead of HEAD, possibly with
  `-c protocol.file.allow=always`. Build it, or land only the `.claude/` half
  (cheap and real, reusing `tests/release-test.sh:179-192`'s shape) and record
  the `memory` half as an untested bound?
- B7 (outline item 11) — `tests/version-guard-test.sh:34-47` implements
  `assert_contains` as a literal glob where `release-test.sh:30`,
  `self-release-test.sh:34` and `update-plugin-dev-test.sh:32` use `grep -q --`.
  No needle produces a false pass today, so there is no live defect, and
  converting touches every assertion in a 447-line file. Converge now, or record
  the divergence as a known bound the way C9 records `release.sh`'s comment
  volume?
- C4 (outline items 12 and 13) — a whole-tree sweep found four
  `<script>.sh:<line>` citations, three of them stale: `toolkit/release.sh:254`
  (cites `:780-785`, should be `:837-843`), `tests/version-guard-test.sh:340`
  (cites `release.sh:446-455`, should be `:472-481`) and `:341` (cites
  `:456-460`, should be `:470-486` and `:618-626`). `tests/release-test.sh:1248`
  is accurate. A1 and A2 will shift `release.sh`'s lines again. Fix the three
  and keep the convention, or drop line numbers for function names at all four
  sites?
- Publish this repo's own gitlore memory store with `/gitlore:push`? The shared
  `ddaanet` tier was merged and published on 2026-09-17; the `memory` store's
  own remote was deliberately left alone, publishing it being wider than the
  tier merge that was asked for.

## Remaining

- Run the `/edify:proof` item loop over
  `plans/2026-09-18-deliverable-review-fixes/outline.md`, approving each item,
  once the decisions above are folded into items 3, 6, 11 and 12.
- `/runbook` over the proofed outline, then `/orchestrate`.
- Root `memory/MEMORY.md` is over Claude Code's loader cap, so entries past the
  cutoff never reach a session; `/gitlore:index-audit` addresses it. Three facts
  stay unwritten for that reason: mutation-test a refusal's *prose*, not only
  its decision; to test a property that a `set -o` line currently masks, run a
  `sed`-stripped copy of the script with that line removed, as
  `tests/release-test.sh:1427-1448` now does for `pipefail`; and
  `git-config-multivalued-read` warns against `git config -z --get-regexp` when
  the key is interpolated, while `shared-claude.md`'s always-on whitespace rule
  names that exact form as a default, with no routing cue between them.
- `tests/release-test.sh` failed once on 2026-09-17, at "release: still refuses
  a genuinely dirty non-memory path in the marketplace repo", and has been clean
  on every subsequent full run of the suite. Unreproduced and unexplained; that
  scenario is where to look if it recurs.
