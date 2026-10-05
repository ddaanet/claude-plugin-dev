# Build summary — the dogfood shim stops syncing (0.9.1)

Outline: `plans/2026-10-05-dogfood-drop-auto-sync/outline.md` (decisions 1-5,
each overridable except the drop itself). Not released.

## What changed

- `toolkit/bin/claude` — the skip on `CLAUDE_CODE_PLUGIN_DIRS` equal to the copy
  and the sync-failure path are removed. After the physical root resolution, a
  missing `<root>/dist/plugin` directory refuses the launch with one line,
  `dogfood: no copy at <root>/dist/plugin, so claude was not started; run just dogfood to create it`,
  exit 1, before the PATH strip. Export, PATH strip, exit 127 and exec with argv
  unchanged are as before. The header comment is rewritten. The physical root is
  now justified as matching `dogfood.sh`'s own resolution, since the skip it
  served is gone.
- `toolkit/install.sh` — Next steps gain step 4: create the copy with
  `just dogfood`, then launch from the repo root.
- `tests/dogfood-launcher-test.sh` — the fixture starts with an empty copy. New:
  "a launch does not sync, the variable unset" and "a missing copy refuses the
  launch". Dropped: sync-before-exec, the two skip scenarios, the list-syncs
  scenario, failed sync and failed rsync. "the shim exports the copy" now gives
  its decoy a copy of its own. "an inherited variable is overwritten" uses a
  list value naming the copy and asserts no sync. The 127 scenario's tool list
  is trimmed to `bash dirname`.
- `tests/install-test.sh` — the fresh install's output names `just dogfood`.
- Docs:
  - `docs/design.md`: the Requirements bullet; D4 rewritten as "syncs only on
    `just dogfood`"; a new decision "a launch with no copy is refused"; the
    failed-sync, shim and `just dogfood` bullets; Limitations now name
    `dist-vX.Y.Z`.
  - `docs/references/dogfood.md`: the problem section; "Sync only on
    `just dogfood`" with a new "Rejected: sync at launch" and a subsection "A
    launch with no copy is refused"; sync failure; the shim section, which now
    says the exported PATH strip keeps an agent's `claude` off the shim; the
    hooks-twice note moved into it; bounds. 389 lines, so no split was needed.
  - `toolkit/README.md`: the component list; Setup ends with `just dogfood`;
    Launching rewritten; Promoting; the sandbox paragraph; Conventions; the
    install flow; a pointer to the 0.9.1 step.
  - `README.md`: the problem paragraph, the `just dogfood` bullet and the
    install flow.
  - `CLAUDE.md`: the Layout bullet for `bin/claude`, and the "cuts the" wrap.
  - `toolkit/migrations/v0.9.0.md`: the closing paragraph only, per outline
    decision 4.
  - New: `toolkit/migrations/v0.9.1.md`.
  - New: `docs/changelog/2026-10-05-the-shim-stops-syncing.md`, with its index
    bullet in `docs/changelog.md`. The 2026-10-03 record is untouched.

## Red evidence

Run against the unchanged 0.9.0 shim and `install.sh`. Full output is in
`reports/red-launcher.txt` and `reports/red-install.txt`. All failures are
assertion failures:

- "a launch does not sync, the variable unset": the copy held the manifest at
  start (`expected 'absent', got 'present'`), and `.claude-plugin` existed in
  the copy afterwards.
- "a missing copy refuses the launch": exit 0, not 1; stderr had zero lines and
  no `dogfood:` line naming `just dogfood`; the stub ran; a copy was made.
- "an inherited variable is overwritten: the launch does not sync": the copy
  held the manifest (`present`).
- "no next claude exits 127": stderr held the sync's `git: command not found`
  and `dogfood: sync failed, so claude was not started`, not the shim's one
  line.
- `install-test.sh`:
  `install.sh's next steps create the copy: output did not contain 'just dogfood'`.

Launcher total: 9 failures. Install total: 1 failure. After the change, both
suites pass.

## Precommit

`just precommit` was run in the foreground: exit 0. Checks passed:

- `whitespace` and `format-docs`. rumdl reflowed the new record, the hub, the
  node, the outline and the three untracked 2026-10-03 deliverable-review
  reports.
- `shellcheck` on the seven toolkit scripts and `scripts/self-release.sh`.
- `bash -n` on all 15 suites.
- `_import-check`: plain, widened and missing gate, `resume-release`, `dogfood`.
- Suites: version-guard, check-version, release, self-release,
  update-plugin-dev, install and dist-tree (11 files, `bin/claude` executable,
  no gitlink).
- docs: cap 400, pointers resolve.
- doc-sync: 5 shared blocks, and the Layout matches `toolkit/`.
- citation.
- dogfood-sync, dogfood-sync-refusal, dogfood-pre-tool, dogfood-session-start
  and dogfood-launcher.

The pre-commit hook re-ran it green on each commit, once after a flaky failure
(see Open). A fourth commit adds this note's final state.

## Commits

1. `e444427`
   `🐛 the dogfood shim no longer syncs; a launch with no copy is refused`.
   Shim, `install.sh`, launcher and install suites.
2. `8a30180` `📝 just dogfood is the only promotion`. Hub, node, both READMEs,
   `CLAUDE.md`, the migration notes, the dated record and its index.
3. `a012894`
   `📝 dogfood drop-auto-sync outline, red evidence and build summary`. This
   directory, plus the three 2026-10-03 deliverable-review reports. They were
   untracked at the start, and the new dated record cites
   `deliverable-review.md` by path, so a fresh clone needs it.

## Review findings, dispositioned

- **Major 1 (the skip's premise)**: moot. The skip is gone. Its premise is
  corrected in the new dated record. The node's "Rejected: sync at launch" and
  shim section say that the exported strip keeps an agent's `claude` off the
  shim. The settle probe in a consumer was not run; with nothing depending on
  it, it is no longer needed.
- **Minor 1**: reworded. The exposure is any sync run through sandboxed Bash,
  `just dogfood` or `dogfood.sh sync`, since the shim never syncs. The manual
  says a launch is unaffected.
- **Minor 2**: moot. The `CLAUDE.md` bullet is rewritten without "names". The
  2026-10-03 index bullet stays as written, as a dated record, and the new
  record corrects it.
- **Minor 3**: fixed. The README Conventions now read "`release: X.Y.Z` (the
  gitmoji hook maps it to `🔖 X.Y.Z`)".
- **Minor 4**: corrected in the new dated record.
- **Minor 5**: moot. No `claude` subcommand promotes, and the manual says "any
  other `claude` you run in the repo loads the copy as it stands".
- **Minor 6**: fixed in the surviving text. That is the manual's Launching
  fallback, narrowed to "`just dogfood` cannot create the copy". It is given
  verbatim in two forms:
  - bash/zsh:
    `"$(which -a claude | grep -v '/plugin-dev/bin/claude$' | head -n1)"`
  - fish: `set -l c (…); $c`, because fish 4.0.2 refuses a command substitution
    in command position. Both forms were probed against a stub PATH.

  The v0.9.0 note's fallback paragraph is replaced, not fixed.
- **Minor 7**: fixed.
- **Outside the range**: fixed. The hub's Limitations say
  `just update-plugin-dev dist-vX.Y.Z`. `docs/references/distribution.md` still
  mentions `update-plugin-dev vX.Y.Z`, but only in a past-tense account of why
  VERSION exists, so it is left as is.

## Open

- Decision 4 (editing the v0.9.0 note's closing paragraph) and decision 5 (the
  fallback kept) are defaults for my human partner to confirm.
- The refusal exit status (1) and the check's placement (before the PATH strip,
  so with neither a copy nor another `claude` the copy refusal wins) are
  defaults.
- Unprobed, as before: hooks firing twice in gitlore's evals under the shim, and
  an empty plugin-root `.mcp.json`.
- Not run: a dogfood session of a real consumer on the new shim, which is the
  release's dogfood step.
- **A pre-existing flake, not fixed (out of scope).** The pre-commit hook failed
  once on the third commit, in `tests/self-release-test.sh`:
  `happy: dist tree has README: output did not contain 'README.md'`, with
  `README.md` printed as the first line of the output. The suite's
  `assert_contains` runs `printf '%s' "$1" | grep -q` under `set -o pipefail`.
  `grep -q` exits on the first-line match, `printf` takes SIGPIPE, and the
  pipeline fails. A re-run passed. The same harness is copied into the other
  suites. A here-string (`grep -q -- "$2" <<<"$1"`) removes the race.
