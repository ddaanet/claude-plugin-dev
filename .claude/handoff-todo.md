## Open decisions

- Item 2.1 part (a) covers review finding N7 — `tests/self-release-test.sh`'s
  happy-path `tree left dirty` check uses `git diff --quiet HEAD`, tracked-only,
  so an untracked leftover passes. No `outline.md` item claims it; it was found
  by mapping all 21 findings to items. Keep it or delete the part whole, with
  its mutation gate, leaving (b)-(d) untouched.
- Whether Item 4.6's citation convention — name unambiguous line context (the
  enclosing symbol plus a quoted fragment) rather than a line number, with
  citations into frozen dated artifacts exempt — also becomes a bullet in
  `CLAUDE.md`'s Conventions section, where this repo's binding rules live. The
  runbook states the executor default as no: it lands in Item 4.7's dated
  changelog entry and nowhere else. A brief proposing the same convention
  upstream sits at `../edify/inbox/brief-cite-line-context-not-line-numbers.md`;
  dropping it was the end of this repo's involvement there.
- Two deviations `/runbook` took from `outline.md`, both overturnable: Phases 2
  and 3 are typed `general` rather than `tdd`, each item carrying a Mutation
  gate — apply the named edit, observe the assertion fail, revert — in place of
  a RED step that would have nothing to fail on, since every cluster B
  assertion passes against unchanged production code. And Phase 2 is one item
  in four parts rather than four items, which buys one agent on the 336-line
  suite at the cost of one commit and one proof verdict for all four fixtures.
- Item 3.2 resolves a fork `outline.md` left open, and the runbook says so:
  re-invoke the hook before capturing `tagless_sysmsg` rather than adding a note
  that the capture is stale. The note-only option is the weaker one, not wrong.

## Remaining

- `/proof plans/2026-09-18-deliverable-review-fixes/runbook.md`, then
  `/orchestrate`.
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
