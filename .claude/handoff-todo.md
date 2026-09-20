## Open decisions

- None. The four carried here were settled at a `/ddaa:proof` pass on
  2026-09-19 and written into `runbook.md` and `runbook-test-suites.md`, which
  record each outcome where it applies. The one structural change: the citation
  convention is enforced by a precommit check rather than a `CLAUDE.md` bullet,
  so old Item 4.6 became `general` Item 3.5 in the node and the number 4.6 is
  left vacant.

## Remaining

- `/proof plans/2026-09-18-deliverable-review-fixes/runbook.md`, then
  `/orchestrate`. Only the open decisions have been proofed; the runbook's items
  have not had their item-by-item read. The proof edits are uncommitted.
- `/gitlore:index-audit` on the root `memory/MEMORY.md`, which is over Claude
  Code's loader cap — it did not load at all this session, so recall ran against
  `rg --files memory/` filenames. Eight facts are queued unwritten behind it.
  The five carried forward:
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
    actually gets — this produced a wrong EPIPE threshold before it was caught;
  - ralph-loop's completion-promise path can fail to match a `<promise>` tag
    that is byte-identical to the stored promise, so `--max-iterations` is the
    reliable backstop rather than the promise.

  And three from this session:
  - rumdl's MD013 reflow joins a paragraph's continuation lines, so a runbook
    item whose `Requirements:`, `Model:` and `Change:` fields are continuation
    lines — the shape edify's `runbook-format.md` shows — is destroyed by
    `just format-docs`. Nested bullets survive it;
  - `tests/docs-test.sh` selects its files with `git ls-files`, so a new
    untracked document passes the 400-line cap trivially and only fails on the
    commit that tracks it. Check `wc -l` directly while drafting;
  - `/orchestrate` composes one dispatch per *item* and names it `item-N-M`, so
    a `Depends on:` chain across several items on one file yields one fresh
    agent per item, not one per file. Merging items is the only mechanism that
    delivers a one-agent-per-file preference.
- The unreproduced `tests/release-test.sh` failure of 2026-09-17, at `release:
  still refuses a genuinely dirty non-memory path in the marketplace repo`.
  Clean on every full run since, including three this session; that scenario is
  where to look if it recurs.
