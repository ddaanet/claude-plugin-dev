# Item 3.5 — design hub, dogfood node and changelog

Dated 2026-09-30 (`date +%F`).

## Where each clause landed

- **Hub Requirements bullet**: `docs/design.md`, `## Requirements`, a new bullet
  after the installer one: "Provide a dogfood launcher: a `claude` shim that
  loads the consumer plugin from a copy at `dist/plugin/` …".
- **Hub decision group linking the node**: `docs/design.md`, the heading "The
  dogfood launcher" linking `references/dogfood.md` in the existing
  group-heading form, placed after the version-guard group and before
  `## Limitations`. It has twelve one-line conclusions, one per decision D1–D12,
  in outline order.
- **Node with D1–D12's arguments**: `docs/references/dogfood.md`, one section
  per decision:
  - D1: "A real copy, not a symlink";
  - D2: "The source set: the whole tree minus what git ignores", which also
    holds the rejected `--files-from` list;
  - D3: "The plugin root is the repo root";
  - D4: "Sync only on deliberate promotion";
  - D5: "One script, three subcommands, rooted at its own location";
  - D6: "The copy guard denies; it does not rewrite", which also holds the
    rejected `updatedInput` rewrite;
  - D7: "The session check reports; it does not refuse";
  - D8: "Sync failure is loud";
  - D9: "The shim: `plugin-dev/bin/claude`", which also covers the subdirectory
    launch;
  - D10: "`just dogfood`";
  - D11: "`install.sh` wires the hooks, and only the hooks";
  - D12: "The migration is a note".
- **Why sync-on-edit was rejected**: node, "Sync only on deliberate promotion",
  in the paragraph "**Rejected: sync on edit.**". It gives the design's
  mechanism, taken from `outline-review.md` and the brief, and the two reasons
  from the outline's Approach: a sync on every tool call (Q2's 60–108 ms), and
  half-edited hook scripts going live. The changelog entry carries the history.
- **Q3 and subdirectory probe results with CC 2.1.284**: node, "## Probe
  evidence". Each result links its report and carries CC 2.1.284. The node's
  bundle-read claims (Q1, `notebook_path`, the variable's format) carry CC
  2.1.283, as their sources do.
- **Outline Risks that stay true once shipped**: node, "## Bounds accepted". See
  "Risks carried" below.
- **Hub `install.sh` summary under Distribution**: rewritten in place. See
  "Sentences rewritten" below.
- **`distribution.md`'s "Single `install.sh` handles bootstrap and wire"**:
  rewritten in place. See "Sentences rewritten" below.
- **Limitations: the subdirectory launch and the unprobed macOS rsync**:
  `docs/design.md`, `## Limitations`, two new bullets before "Solo-author
  workflow assumed".
- **Changelog record**: `docs/changelog/2026-09-30-dogfood-launcher.md`. Its
  index line sits at the top of `docs/changelog.md`'s newest-first list, in the
  existing link-plus-summary format.

## Sentences rewritten

- **`docs/design.md`, Distribution bullet "One `install.sh` bootstraps and wires
  in a single invocation"**: "hook into `.claude/settings.json`" became "the
  version-guard and two dogfood hooks into `.claude/settings.json`". It gained
  the any-matcher idempotency rule: a hook counts as present when any entry
  under its event runs its command, whatever the matcher. The old text named
  only one hook.
- **`docs/design.md`, Motivation, "The toolkit captures: …"**: the list of what
  the toolkit ships named three things and gains the dogfood launcher. Left
  alone, it would state an incomplete set as the whole.
- **`docs/references/distribution.md`, "Single `install.sh` handles bootstrap
  and wire"**:
  - the first paragraph's "add the version-guard hook" became "wire three
    hooks", naming them and linking `dogfood.md`;
  - "a jq pass that appends one hook" became "one jq pass per hook, each
    appending its entry only if absent";
  - it gained the any-matcher rule and its reason (a rescoped hook would
    otherwise run twice where the matchers overlap), and that the file is
    written only when the result differs.

  The hard-error sentence after it is unchanged and still true.

I checked the other reference nodes. `recovery.md` calls `.claude/settings.json`
"(the version-guard wiring)" in a parenthetical, to name what an exempted edit
there costs. The file now also carries the dogfood hooks, but the sentence stays
true: it claims nothing exclusive, and the file is out of scope, so I left it.
No other sentence in `release-flow.md`, `recovery.md`, `self-release.md` or
`version-guard.md` became false.

## Risks carried

All ten outline Risks are still true once shipped. All are in the node's "Bounds
accepted", except the subdirectory one, which is argued under D9:

- **Claude Code drift**: carried with the re-run procedure from
  `probe-hooks.md`, plus the requirement that it run unsandboxed (a sandboxed
  `claude -p` drops `SessionStart` hooks, per `sandbox-effects`).
- **macOS rsync is unprobed**: carried, but only the unprobed part. The
  outline's contingency, that the README names a Homebrew rsync and `sync` fails
  with that message, was not built. The node says only that a failure there
  surfaces as a failed sync. It is also a hub Limitation.
- **Benign rsync exits**: carried.
- **The copy lags the source by design**: carried.
- **A sandboxed sync cannot read `.mcp.json`**: carried.
- **Subdirectory launches run without the hooks**: carried under D9 and in
  Limitations.
- **Promotion is repo-wide**: carried.
- **Children inherit the variable**: carried.
- **Only tool edits to the copy are guarded**: carried.
- **The copy carries non-plugin content**: carried.

None was judged no longer true.

## Divergences between the outline and the code

The node follows the code in each case. The changelog entry records them under
"Where the shipped code departs from the outline".

- **D2**: the outline pipes `git ls-files` into rsync. `sync_copy` writes the
  exclude list to a temp file first, so a git failure cannot leave rsync running
  on a partial list.
- **D6**: the code adds two behaviours:
  - an existing target that is itself a symlink is resolved in full
    (`readlink -f`), and a dangling or looping leaf is compared as spelled;
  - a payload `jq` cannot read, or an unenterable directory, exits non-zero,
    which Claude Code shows as a non-blocking hook error.
- **D7**: the `systemMessage` names the remedy, "launch claude through
  plugin-dev/bin/claude from the repo root". The code also defines how
  non-absolute and unenterable entries are compared: as spelled, trailing
  slashes stripped.
- **D9**: the outline says PATH stripping "passes an explicit `-` to `paste`".
  The shim's `path_without` uses parameter expansion and no `paste`.
- **D12**: the migration note adds that `install.sh` must be re-run from the
  human's own shell, since the sandbox refuses writes to
  `.claude/settings.json`.
- **Risks, macOS rsync**: the Homebrew fallback was not built (above).

Two changelog facts were checked against the brief and corrected before commit:

- craft's, cwd-safety's and handoff's shims passed `--plugin-dir <repo root>`,
  so they caused the prompt rather than working around it;
- the `unset CDPATH` drift is craft's.

## Final line counts (after `just format-docs`)

- `docs/design.md`: 291 (was 241)
- `docs/references/dogfood.md`: 346 (new)
- `docs/references/distribution.md`: 271 (was 264)
- `docs/changelog.md`: 155 (was 148)
- `docs/changelog/2026-09-30-dogfood-launcher.md`: 105 (new)

## Checks run

- `just format-docs`: my five files reflowed. `rumdl check` on them reports "No
  issues found in 5 files". The command's remaining findings are all in other,
  pre-existing files under `plans/`, which I left alone.
- `bash tests/docs-test.sh`: "docs ok (cap 400 lines, pointers resolve)". This
  includes the `../../plans/...` links from the node.
- `bash tests/citation-test.sh`: ok. There are no `<script>.sh:<line>` citations
  in `docs/` outside `docs/changelog/`.
- `just precommit` in the foreground, first run: exit 1. `tests/docs-test.sh`
  reported `broken-link` in this report, because the hub heading was quoted
  inside an inline code span, and the link check does not skip inline code. I
  rewrote that line without link syntax.
- `just precommit` in the foreground, second run: exit 0. No intermittent suite
  failure occurred.
- The commit's pre-commit hook: its result is in the commit outcome. The log is
  `/tmp/claude/dogfood-build/commit-3-5.log`.
