# Item 2.1 — design hub, dogfood node, changelog record

Prose only; no code or test touched. Scope files: `docs/design.md`,
`docs/references/dogfood.md`, `docs/changelog.md`,
`docs/changelog/2026-10-03-dogfood-review-fixes.md`.

## `docs/design.md`

- **m8** — Motivation gains a paragraph after "Both problems want the same
  answer": a session that loads the plugin from its own working tree prompts on
  every agent edit (every path under a loaded plugin root is a sensitive file)
  and runs half-edited hook scripts; consumers' hand-copied shims had drifted.
- **Major 1, D4** — the Requirements launcher bullet and the D4 conclusion now
  say a launch syncs only from outside a dogfood session of the same repository;
  a nested `claude` carries the variable naming the copy and skips the sync; no
  rule reads argv. Rewritten in place, present tense.
- **Major 1, D9** — the shim bullet adds that the variable reaches children,
  which is how a nested `claude` knows it is inside this repository's dogfood
  session, and that the shim syncs unless the variable already equals its own
  physical copy path, exporting it in every case.
- **m3, D8** — "A failed sync is loud" adds the sync's status and the one line
  saying `claude` was not started.
- D6 (m1) left at the hub level: its conclusion does not describe the exit
  status, so the change does not show there.

## `docs/references/dogfood.md`

- **Major 1** — "Sync only on deliberate promotion": the opening moment list is
  amended, and a new subsection "A `claude` started inside a dogfood session
  does not promote" carries the argument: the motivating path (every `claude`
  through the shim promotes, gitlore's evals' per-turn `claude -p`, an agent's
  run re-promoting under its live session; deliverable review Major 1); the rule
  verbatim from decision 1 with its four effects (plain shell incl. `claude -c`
  syncs; nested same-repo skips; A-to-B syncs B; any other value, a list
  carrying the copy included, syncs); rejected alternatives (argv `-p`/`--print`
  rule; opt-out variable and documented "call the next `claude`" rule, argued
  together); costs (`just prerelease` from the human's terminal syncs per eval
  turn, accepted as deliberate; every shimmed `claude` loads the copy, so a
  script wiring the hooks into its own settings may run them twice, unprobed).
- **Major 1, D9** — "The shim" mechanism: the root is resolved physically, sync
  runs unless the variable equals `<root>/dist/plugin`, export in every case;
  why the root must be physical (a symlinked spelling still matches).
- **Major 1, bound** — "Children inherit the variable" now says a child reaching
  this repository's shim skips the sync, and another consumer's shim syncs that
  consumer and overwrites the variable.
- **m3** — "Sync failure is loud" names the
  `dogfood: sync failed, so claude was not started` line, after the sync's own
  stderr, with the sync's status.
- **m1** — the copy guard's last paragraph: exit 1 on any `jq` failure with
  `jq`'s stderr kept, never `jq`'s own status, because `jq` exits 2 on
  usage/system errors and on a parse error in 1.6 (source reading, unprobed),
  and exit 2 blocks.
- **m2** — the `.mcp.json` bound settles the zero-byte shape as probed: a
  zero-byte read-only mask is copied as an empty regular file, into a plugin
  that ships no `.mcp.json` too, and stays until the next unsandboxed sync; how
  Claude Code treats an empty plugin-root `.mcp.json` stays unprobed. Its
  closing clause now says the manual advises promoting from the human's own
  shell, unscoped; that matches the manual once Item 2.2 widens its scoping
  (m2's manual half).
- **m9** — "across four consumers" → "across four repositories".
- The node reached 420 lines after the first draft; the new subsection, the shim
  paragraph and the `.mcp.json` bound were tightened (two rejected alternatives
  merged under one lead-in, the bound turned from a list into prose, two inline
  report links replaced by a named reference) to 398 lines after
  `just format-docs`. It now sits 2 lines under the 400 cap: the next addition
  to this node should come with a split, not a trim.

## Changelog

- New record `docs/changelog/2026-10-03-dogfood-review-fixes.md`, shaped like
  `2026-09-30-dogfood-launcher.md`: opening (review counts, outline path); "The
  shim promoted on every `claude` it fronted" (the bug, the three venues
  offered, my human partner's rule verbatim in substance, why, D4/D9 rewritten
  in place, the twice-loaded-hooks question left open); "The other fixes in the
  same pass" naming m3, m1 (code), Major 2 reclassified and its fixture, m10,
  m11, m12 (tests), and m2, m4, m5, m6, m7, m8, m9 (prose; m4–m7 land in Item
  2.2); the two unprobed observations out of scope.
- `docs/changelog.md` gains the index bullet at the top (newest first).

## Gates

- `just format-docs` run; it re-wrapped the three edited docs.
- `just precommit` in the foreground: rc 0, first run, no flake. `docs-test.sh`
  and `citation-test.sh` passed.
