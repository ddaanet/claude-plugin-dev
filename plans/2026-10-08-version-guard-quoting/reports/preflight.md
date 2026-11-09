VERDICT: GO

Preflight for toolkit 0.9.3 (`just release patch` from 0.9.2), run 2026-10-08.
No blockers. Two non-blocking findings (A, B below) for the caller to weigh
before releasing. Nothing was released, tagged, pushed, committed or staged.

## 1. Git state: pass

- Branch `main`.
- `git diff --quiet HEAD -- . ':(exclude).claude' ':(exclude)memory'`, the guard
  `scripts/self-release.sh` `common_preflight` applies, exits 0. It exited 0
  again after `just precommit` had run `rumdl fmt`, so the formatter rewrote
  nothing. Plain `git diff --quiet HEAD` also exits 0. The real guard will pass.
- `git status --porcelain` shows only untracked sandbox masks and editor/env
  dotfiles:
  ```
  .bash_profile .bashrc .gitconfig .idea .mcp.json .profile .ripgreprc .vscode .zprofile .zshrc
  ```
  and
  `.claude/{agents,commands,hooks,launch.json,loop.md,output-styles,routines,scheduled_tasks.json,skills,workflows}`.
  None are tracked, none block.
- `.claude/handoff-task.md` and `.claude/handoff-todo.md` exist.
  `git diff --cached --name-only` lists nothing, so they are not currently
  staged (git status shows no staged entries). Excluded by the guard in any
  case.
- Submodule `memory` shows `-e98e773...`, which is uninitialised in this
  checkout. The guard excludes it.
- **Finding A (not "up to date with origin"):** local `main` (4c025de) is 5
  commits ahead of `origin/main` (625b6df, which is the v0.9.2 release commit).
  None are pushed. Nothing is behind. `just release` pushes main, so it
  publishes these five along with the release commit. That is expected for this
  plan, but confirm it is intended: the five commits go public with the release.

## 2. Version and tag state: pass

- `toolkit/VERSION` is `0.9.2`. Latest `v*` tag is `v0.9.2` and latest `dist-v*`
  tag is `dist-v0.9.2`.
- `git ls-remote --tags origin` shows `v0.9.2` (peels to 625b6df) and
  `dist-v0.9.2` on origin.
- `gh release view v0.9.2` returns the release, not a draft.
- `v0.9.3` and `dist-v0.9.3` are absent locally and on origin.
  `gh release view v0.9.3` says "release not found".

## 3. Commits since v0.9.2 and what ships: pass

`git log v0.9.2..HEAD` has 5 commits:

- 4c025de version-guard quoting, migration note and record
- 514eb7a quote the version-guard hook command and migrate the legacy entry
- 2817ad4 plan the version-guard hook quoting fix
- dfea8ad add inbox/ for briefs from other repos
- f2b76c3 record the probed dogfood claims, correct the jq 1.6 and reload
  wording

The review fixes and node split (943f8c3 "pin 0.9.2 submodule sync scenarios,
split the dogfood node") landed before the 0.9.2 release commit, so they shipped
in 0.9.2 and are not in this range. The rest of what was expected is present.

`git diff --stat v0.9.2..HEAD -- toolkit/` (what consumers receive):

```text
 toolkit/README.md            | 25 ++++++++++++-----
 toolkit/dogfood.sh           |  8 +++---
 toolkit/install.sh           | 67 ++++++++++++++++++++++++++++++++++++++++----
 toolkit/migrations/v0.9.3.md | 33 ++++++++++++++++++++++
 4 files changed, 116 insertions(+), 17 deletions(-)
```

In substance: `install.sh` quotes the version-guard hook command and migrates
the legacy unquoted entry in place, `dogfood.sh` corrects the probed jq/reload
wording, `README.md` follows, and one new migration note. `toolkit/VERSION` is
untouched (the release bumps it).

## 4. Migration note: pass, with one nit (B)

- `toolkit/migrations/v0.9.3.md` exists. The name matches the patch bump of
  0.9.2. `tests/dist-tree-test.sh` accepts it (pattern
  `^migrations/v[0-9][0-9.]*\.md$`) and passed: "dist tree ok (11 files,
  bin/claude executable, no gitlink)".
- `toolkit/update.sh` range logic: `old_version` is read from
  `plugin-dev/VERSION` before the pull; each `migrations/v*.md` is printed when
  `v > old_version && !(v > new_version)`. A consumer on 0.9.2 pulling
  `dist-v0.9.3` prints exactly `v0.9.3.md`. `v0.9.0.md` and `v0.9.1.md` are not
  printed.
- Its commands, checked on a throwaway fixture in `$TMPDIR` (a fake consumer
  holding the legacy unquoted entry under matcher `Write`), not on any real
  consumer:
  - `bash plugin-dev/install.sh` rewrote the entry in place and printed
    `.claude/settings.json (version-guard hook requoted)`, as the note says.
  - `grep version-guard .claude/settings.json` then showed exactly one line.
  - A second run printed `already installed, nothing to do.`, as the note says.
  - The note's claim that an agent's sandboxed Bash refuses
    `.claude/settings.json` writes matches this session's sandbox config
    (`denyWithinAllow` lists it).
- **Finding B (non-blocking wording nit):** step 2 says the surviving line reads
  `bash "${CLAUDE_PROJECT_DIR}/plugin-dev/version-guard.sh"`. `grep` on the JSON
  file actually prints
  `"command": "bash \"${CLAUDE_PROJECT_DIR}/plugin-dev/version-guard.sh\""` with
  backslash-escaped quotes. The legacy line has no quotes at all, so a reader
  can still tell good from bad. Only the literal text differs. The note ships in
  the dist tree, so any fix means a further commit before the release. Caller's
  call; I did not edit it.

## 5. Docs agree with code: pass

- `docs/changelog.md`: two new bullets at the top (version-guard-quoting,
  probed-dogfood-claims), each pointing at an existing
  `docs/changelog/2026-10-08-*.md`. No blank line between bullets (the only
  blank line after the preamble is line 11, before the list).
- `CLAUDE.md` Layout vs `toolkit/`: `tests/doc-sync-test.sh` passed ("5 shared
  command blocks, Layout matches toolkit/"). `CLAUDE.md` also gained the
  `inbox/` entry and the `legacy_hook_cmd` convention text.
- Unprobed claims: a grep for "unprobed" finds none of the four 2026-10-08 items
  remaining in `docs/` or `toolkit/` outside dated records. The hits left are
  the changelog records, plans, and the genuine macOS rsync bound
  (`docs/design.md:296`, `docs/references/dogfood-sync.md:145`), which is a
  different item.

## 6. `just precommit`: pass (exit 0, run twice)

Checks that passed, from its output: whitespace; format-docs
(`rumdl fmt docs plans` rewrote no tracked file); shellcheck on the 8 shell
scripts; `bash -n` on the 15 test scripts; `_import-check` ("release.just
import: ok (plain + widened + missing gate, resume-release, dogfood)"); then
version-guard, check-version, release, self-release ("ok"), update-plugin-dev,
install ("install.sh scenarios passed"), dist-tree ("dist tree ok"), docs ("docs
ok (cap 400 lines, pointers resolve)"), doc-sync, citation, dogfood-sync,
dogfood-sync-refusal, dogfood-pre-tool, dogfood-session-start and
dogfood-launcher, each ending with its own "all ... passed" or "ok" line.

Noise to know about: `rumdl fmt` prints
`Issues: Found 100 issues in 58/353 files`, all MD013 line-length on long lines
it cannot wrap. Almost all are in old `plans/` reports; the `format-docs` recipe
is written to exit 0 on those. Two are in `docs/`:
`docs/changelog/2026-10-08-dogfood-no-copy-remedy-and-submodule-ignores.md:20`
and `docs/references/dogfood-sync.md:106`. Neither is in a file this release
touches beyond the earlier entries, and neither fails the gate.

## 7. Release recipe preconditions: pass

- `gh auth status`: logged in to github.com as `ddaanet`, active, scopes
  `delete_repo gist read:org repo`, git protocol ssh.
- `git ls-remote origin HEAD` returns 625b6dfc... (origin main = the v0.9.2
  commit), so origin is reachable.
- `git config --get-regexp 'url\..*\.insteadof'` prints nothing (exit 1), so no
  push-route rewrite. `origin` is `git@github.com:ddaanet/claude-plugin-dev.git`
  for fetch and push.

## Summary

All seven checks pass. Before running `just release patch`, confirm two things:
the five unpushed commits will go out with it (A), and whether the migration
note's step-2 expected-output wording (B) is worth a fix commit first.
