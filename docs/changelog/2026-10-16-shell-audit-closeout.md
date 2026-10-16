# 2026-10-16 — The two shell audits are closed out

The audits of 2026-09-01 (`plans/2026-09-01-shell-audit-toolkit.md` and
`plans/2026-09-01-shell-audit-tests.md`) landed their confirmed defects at the
time. This pass re-checked every item they left open against the code as it
stands, fixed the ones that still applied and were cheap, and recorded why the
rest stay. The plans themselves are kept: no plan in `plans/` has ever been
deleted on landing, and `825e118` marked a landed one rather than removing it.

## Fixed

- **`update.sh` and a missing incoming `VERSION`.** With `migrations/` present
  and no `VERSION` in the pulled tree, the notes were skipped without a word,
  while the missing-old-version case printed a "review by hand" note. Both now
  do.
- **A manifest with no `.name`.** `jq -r .name` printed `null`, and a release
  went public before `bump_marketplace` created an entry called `null`. The
  preflight both modes share (`--resume` runs no `check-version.sh`) and
  `check-version.sh` itself now refuse it.
- **`check-version.sh` and a marketplace file with no plugins list.** jq exited
  5 and errexit passed that on as the script's status; it now says the file has
  no plugins list and exits 1.
- **`install.sh` in a repo with no commits.** `git diff HEAD` failed and the
  refusal read "uncommitted changes". It now says there are no commits yet.
- **`ls_remote_sha`'s failure.** It already died with its own message, but every
  caller runs after the local commit and tag exist, so the message now carries
  the `just resume-release` hint the push steps give.
- **The marketplace no-op guard compared bytes.** jq always writes 2-space JSON,
  so a `marketplace.json` kept in another style, already at the version, was
  rewritten and committed as a whole-file diff. The guard now compares the two
  files as JSON values.

## Left, with the reason

- **A two-component manifest version bumping to `1.2.1`.** Unreachable: a bump
  runs only when the manifest version equals the newest `vX.Y.Z` tag, and the
  tag list is filtered to full three-component versions, so a manifest of `1.2`
  is refused as not matching the latest tag before the bump is computed.
- **`ls-remote | cut` under `pipefail` (`release.sh:235`, `:263`, `:337`).** The
  pipelines no longer exist; the reads are captured whole in `ls_remote_sha`.
- **The migration-notes block being dead code.** `toolkit/migrations/` exists
  now and the block runs on every update that crosses a note.

## Tests

- The three `chmod 555` scenarios in `tests/release-core-test.sh` print a
  `SKIP:` line naming the scenario when `id -u` is 0, instead of failing on a
  permission bit root ignores. Checked by putting a stub `id` that prints 0
  first on `PATH`.
- Audit-tests defect 2 (`|| true` missing on `dist-tree-test.sh`'s second
  `grep -v`) was already fixed; the line carries the guard. Defect 1
  (`unset CDPATH`) is likewise in place in every suite.
