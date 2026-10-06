# Review fixes — 2026-10-05-dogfood-drop-auto-sync

Input: `reports/deliverable-review.md` and its two sub-reports. My human
partner's decisions are recorded in `outline.md`, section "Deliverable-review
fixes (2026-10-06)". Mid-task they changed one decision: a launch with no copy
no longer refuses; it warns and launches. That replaced outline decision 2,
reversed decision 5 (the fallback), made Major 2 moot and resolved minor 7.

## Findings and what was done

- **Major 1: rsync missing left an empty copy.** `toolkit/dogfood.sh` gains
  `require_rsync`, called after `require_manifest` and `require_ignored_copy`,
  so it runs before the `mkdir`. It prints one stderr line,
  `dogfood: rsync is not on PATH; sync refused`, and exits 1, which matches the
  other three refusals. The header comment lists it. The new scenario "refuses
  without rsync on PATH" in `tests/dogfood-sync-refusal-test.sh` uses a PATH of
  symlinks (`bash cat dirname git mkdir mktemp rm`), with a precondition that
  rsync is absent. It asserts rc 1, empty stdout, one `dogfood:` line naming
  rsync, and `dist/plugin` absent. Docs updated:
  - the manual's sync-refusal list;
  - the node's "Sync failure is loud" and its no-copy section;
  - the hub's "A failed sync is loud";
  - the dated record, in a new section.

  The manual's fallback sentence went with the fallback; see Minor 7.
- **Major 2: exit 1 over 127.** Moot under the new decision. Replaced by the
  scenario "a missing copy and no next claude: the warning, then 127". It
  asserts rc 127, two stderr lines, the warning first and the 127 line second.
- **New decision 2: warn and launch.** In `toolkit/bin/claude`, when
  `<root>/dist/plugin` is a directory the shim exports it. Otherwise it prints
  `dogfood: no copy at <root>/dist/plugin, so claude starts without it; run just dogfood to create it`
  and leaves the variable untouched. The PATH strip, the 127 check and the exec
  are unchanged. Launcher scenarios:
  - "a missing copy warns and launches without it": rc 0, one warning line, argv
    intact, exec'd in-process, the variable `<unset>`, no copy made;
  - "a missing copy passes an inherited variable through";
  - the two below.

  Also updated: `install.sh` Next steps step 4 and the `install-test.sh`
  comment.
- **Minor 9: `-d` vs `-e`.** The scenario "a file at dist/plugin is no copy"
  asserts the warning, the variable `<unset>`, and the file left alone.
- **Minors 1, 5, 6.**
  - Hub: "would promote the working tree repo-wide on every `claude` that
    reaches the shim", and "would run".
  - Node: "Rejected: sync at launch" is argued in the conditional, and "left the
    human's own terminal syncing" is now "would leave every other launch
    syncing". "Took one" is now "would take one".
  - Hub: "and children" dropped.
- **Minors 2, 3, 4 (record amended in place).**
  - The record now says the shim and the skip both arrived in 0.9.0.
  - The nine red assertions are split: seven in the new scenarios, two in the
    rewritten inherited-variable and 127 scenarios.
  - The premise correction now says the syncs ran with `plugin-dev/bin` on PATH
    and the variable unset, in the human's terminal or in a session started past
    the shim. The 0.9.0 manual's fallback is included there.
  - A new section, "After the review: the sync refuses without rsync, a launch
    with no copy warns", holds the rsync refusal and its red. It says the launch
    refusal was replaced before release, records Major 2 as moot and minor 7 as
    removed, and gives the launcher red.
  - The minor 6 bullet says the fallback was removed before release.
  - The index bullet in `docs/changelog.md` is updated.
  - The 2026-10-03 record is untouched.
- **Minor 7: resolved by removal.** The fallback passage is deleted from
  `toolkit/README.md`: the sentence, both command blocks and their lead-ins. In
  its place: "That session does not load the copy, and the `SessionStart` check
  says so. Run `just dogfood`, then relaunch." The v0.9.0 and v0.9.1 notes, the
  node and the hub had no fallback text left. The node instead gains "Rejected:
  refuse the launch", and the hub bullet gives the reason.
- **Minor 8: the hand-read route.** The manual's pointer now reads "a plugin
  coming from before 0.9.1 runs `just dogfood` before its next launch". The
  closing of `v0.9.0.md` names `plugin-dev/migrations/v0.9.1.md` instead of
  "printed after this one when your update crosses both".
- **Other prose for the new behaviour:**
  - the manual's component list, Launching, the install paragraph and the
    Session check's first-warning causes;
  - the root `README.md` install paragraph;
  - the `CLAUDE.md` Layout bullet;
  - `v0.9.1.md` step 1;
  - the node's shim section, its "The variable, not the flag", and the renamed
    section "A launch with no copy warns and starts without it";
  - the hub bullet "A launch with no copy warns and starts without it".

## Red evidence

- **Major 1: `reports/red-sync-refusal.txt`.** Against unchanged `dogfood.sh`
  the suite exits 1 with three failures:
  - `no rsync exit code: expected '1', got '127'`;
  - stderr was `…dogfood.sh: line 68: rsync: command not found`;
  - `the copy is not created: '…/dist/plugin' exists`.
- **Warn-and-launch: `reports/red-launcher-warn.txt`.** Against the refusing
  shim at 631042a the reworked launcher suite exits 1 with 11 failures across
  the four new or reworked scenarios. Among them: rc 1 where 0 or 127 was
  expected, the stub never ran, and stderr was one line where two were expected.
- **Minor 9 and the line order: `reports/red-launcher-mutants.txt`.** These are
  scratch copies under `$TMPDIR/review-fix-mut2`.
  - The `e_test` mutant (`-d` changed to `-e`) fails the "file at dist/plugin"
    scenario twice: no warning line, and the variable set to the file.
  - The `order` mutant (copy check moved below the `claude` lookup) fails "a
    missing copy and no next claude" twice: one stderr line, and the first line
    is the 127 line.
  - The tracked shim passes, exit 0.

## Precommit

`just precommit` was run in the foreground on the full working tree and exited
0. These passed:

- `whitespace`, `format-docs`, `shellcheck`, `bash -n`;
- `_import-check` (plain, widened and missing gate, `resume-release`,
  `dogfood`);
- version-guard, check-version, release, self-release, update-plugin-dev;
- install;
- dist tree (11 files);
- docs (cap 400; `docs/references/dogfood.md` is now 399 lines);
- doc sync (5 blocks, Layout);
- citations;
- dogfood sync, sync refusal, pre-tool, session-start and launcher.

The node sits one line under the cap, so its next addition needs a split.

## Commits

- `631042a` — `🐛 dogfood sync refuses without rsync on PATH`: `dogfood.sh`, the
  sync-refusal scenario, and `red-sync-refusal.txt`.
- **Not committed.** The next commit, for the shim and launcher-test change, was
  refused by the auto-mode classifier as "Modify Shared Resources". It was not
  retried. Everything else in the job is in the working tree, uncommitted, for
  my human partner to commit.
