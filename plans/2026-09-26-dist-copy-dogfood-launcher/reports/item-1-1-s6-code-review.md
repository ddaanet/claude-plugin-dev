# Item 1.1/6 code review

Scope: `toolkit/dogfood.sh` as changed in HEAD — `require_manifest`,
`require_ignored_copy`, their call sites in `sync_copy` and the comments.

## Fixed

- **Minor — `echo` carried a path.** Both refusal lines interpolated the root
  into an `echo` operand. Switched to `printf '...%s...\n' "$1"`, matching the
  pattern-character refusal from 1.1/5. The root is absolute, so a leading `-`
  cannot arise, but a backslash can. Probed with a root named `a\nb`: both lines
  print the literal backslash.
- **Minor — ignore refusal wording.**
  `/dist/plugin/ must be git-ignored in <root>` put the path apart from its root
  and stated a requirement rather than the fact. Now
  `dogfood: <root>/dist/plugin/ is not git-ignored; sync refused`, parallel to
  the manifest line
  (`<root>/.claude-plugin/plugin.json not found; sync refused`). It names the
  full offending path and still contains `/dist/plugin/`, as the test and the
  Interfaces require.
- **Minor — comment grammar.** `sync_copy`'s header read "a root whose
  dist/plugin/ git does not ignore"; now "a root where git does not ignore
  dist/plugin/".

## Verified, no change

- **Interfaces.** Each refusal writes one `dogfood: ` line, exits 1, and runs
  before `mktemp`, the trap or `mkdir`, so `dist/` is left untouched. The ignore
  check passes `dist/plugin/` with the trailing slash.
- **Trailing slash, re-probed on git 2.47.3.** `check-ignore -q dist/plugin/`
  exits 0, both before and after `dist/plugin` exists, under each of `dist/`,
  `/dist`, `dist`, `/dist/plugin`, `/dist/plugin/`, `dist/plugin` and `*`.
- **git error pass-through.** Probed with the manifest present and no `.git`
  (outside any repo). git prints its `fatal: not a git repository` stderr, the
  script exits 128, and `dist/` is not created. `|| status=$?` exempts the call
  from errexit and captures git's real status, so `exit "$status"` is reached.
  The helper runs in the main shell, not a subshell, so its `exit` ends the
  script.
- **Placement.** The helpers directly follow `sync_copy`, their only caller.
  `root_dir` stays last as the shared helper that `pre-tool` and `session-start`
  will also use. This is consistent with entry-point-first.
- **bash 3.2 / BSD.** Uses only `[[ -f ]]`, `case`, `local`, `$?` and `git -C`.
  No 4.x features.

## Note (not a defect in this slice)

- The 128 branch of `require_ignored_copy` has no test: the git-failure test now
  stubs `ls-files` and deliberately passes the ignore check. Mutating
  `*) exit "$status"` into `*) exit 1` would stay green. The branch's behaviour
  was confirmed only by the probe above. Test content is out of scope here; this
  is flagged for the lead.

## Results

- `bash tests/dogfood-test.sh`: all dogfood scenarios passed.
- `just precommit` (unsandboxed): green, through `dogfood-test.sh`.

## Refactor flagged

None.
