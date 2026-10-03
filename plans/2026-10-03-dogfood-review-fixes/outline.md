# Outline: dogfood launcher — deliverable-review fixes

## Provenance

- **Derived from:**
  `plans/2026-09-26-dist-copy-dogfood-launcher/reports/deliverable-review.md`
  and its three sub-reports beside it (`deliverable-review-code.md`,
  `deliverable-review-tests.md`, `deliverable-review-prose-config.md`). Finding
  ids below (Major 1, Major 2, m1–m12) are that report's.
- **Base:** `91016e426bb3aae2b7b179c6323d4172f535d1f9`
- **Parent job:** `plans/2026-09-26-dist-copy-dogfood-launcher` (outline,
  runbook, recall artifact). Its decisions D1–D12 stand except where this
  outline amends D4/D9.

## Decisions taken by my human partner

1. **Major 1 — the shim syncs only when the session is not already a dogfood
   session of this repo.** `toolkit/bin/claude` runs `dogfood.sh sync` unless
   `CLAUDE_CODE_PLUGIN_DIRS` already equals `<root>/dist/plugin` (the physical
   root the shim computes). It exports the variable in every case. Effect: a
   launch from a plain shell syncs, `claude -c` included; a `claude -p` an agent
   runs inside a dogfood session of the same repo inherits the variable and
   skips the sync; a session in repo A running `claude` in repo B syncs B. No
   `-p`/`--print` rule: a `just prerelease` my human partner runs from their own
   terminal still syncs on each eval's `claude -p`, accepted as a deliberate
   act.
2. **Major 2 is a test gap, severity minor.** `sync_copy`'s `/%s` anchor is
   correct code; add a fixture that reds when the anchor is dropped — a tracked
   file deeper in the tree sharing its name with an ignored root entry
   (`/build.log` ignored at the root, `skills/demo/build.log` tracked), and an
   ignored root name beginning `- ` or `#`.
3. **m12 — move, don't relabel.** The symlinked-spelling `session-start` case
   moves into `tests/dogfood-session-start-test.sh`; the launcher suite keeps
   testing only the shim.
4. Previously settled, out of scope: v0.9.0 minor bump, no explicit symlink
   refusal in `sync`, the 80-column README reflow, the pending macOS run of the
   sync suites.

## Work

Code and tests (TDD: each behaviour change gets its red first):

- **Major 1** — shim condition above, with launcher-suite scenarios: variable
  unset → syncs; variable equal to this copy → no sync, still execs with the
  variable; variable naming another path → syncs and overrides it.
- **m1** — `pre-tool` must never exit 2 on a jq failure (2 blocks under Claude
  Code); map any jq failure to a non-blocking non-zero status, and assert the
  exact status in the suite.
- **m3** — on a failed sync the shim adds one `dogfood:` line saying `claude`
  was not started, keeping the sync's own stderr and a non-zero exit.
- **m10** — `pre-tool` payloads carry a `cwd` pointing elsewhere.
- **m11** — the `the shim exports the copy` scenario exports
  `CLAUDE_PROJECT_DIR` pointing elsewhere.
- **Major 2**, **m12** — as decided above.

Docs (prose — dispatch on opus):

- **Major 1** — rewrite D4/D9 in place in `docs/design.md` and
  `docs/references/dogfood.md` ("Sync only on deliberate promotion", "The
  shim"); `toolkit/README.md` dogfood section; root `README.md` if it states
  when sync happens.
- **m2** — doc-only: a sandboxed `just dogfood` copies zero-byte sandbox masks
  (e.g. an empty `.mcp.json`) into the copy; widen the manual's "If your plugin
  ships a `.mcp.json`" scoping and settle the node's "zero-byte shape, unprobed"
  Risk as probed.
- **m4** — `install.sh`'s Next steps output and both READMEs' install flow point
  a fresh install at the dogfood Setup. Keep `tests/doc-sync-test.sh` green
  (shared command blocks).
- **m5, m6** — `toolkit/migrations/v0.9.0.md`: step 2 removes the `.bin`
  reference from justfile lines and deletes a line only when that is all it
  checks; name the rsync requirement, and how to launch by the next `claude`'s
  absolute path while sync is broken.
- **m7** — the manual's "what goes live when" list covers `commands/`,
  `.mcp.json`, output styles.
- **m8** — `docs/design.md` Motivation and `README.md` state the problem the
  launcher solves (self-loaded plugin prompts on every edit, runs half-edited
  hooks).
- **m9** — "across four consumers" → "four repositories".
- A dated changelog record `docs/changelog/2026-10-03-dogfood-review-fixes.md`
  plus its index bullet, covering the D4/D9 amendment.

Unprobed observations in the review (nested `CLAUDE.md` in the copy,
case-insensitive APFS) are not in scope.

## Constraints

- `just precommit` green before each commit; never `--no-verify`.
- Never `git stash`, `git reset`, or blanket staging (`git add -A`, `.`, `-u`,
  `commit -a`); stage by explicit path.
- One script under test per suite file; each suite keeps its own harness copy.
