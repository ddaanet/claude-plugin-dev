# Item 1.1/5 code review — an ignored pattern-character entry aborts sync

Scope: `toolkit/dogfood.sh` as changed in HEAD, the pattern-character `case` in
`sync_copy`.

## Verdict

Correct. The refusal always exits 1, removes the temp list and runs before
`mkdir` and rsync. Two wording defects were fixed in place: the comment and the
stderr line each stated something false.

## Correctness, probed

- **Exit status under SIGPIPE.** Fixture: `a*b.log` followed by 6000 ignored
  names of 60+ chars (396 KB of `ls-files` output, well over a pipe buffer). An
  instrumented copy of the pipeline shows `PIPESTATUS=141 1`: git does die of
  SIGPIPE once the loop exits early. `pipefail` reports the *rightmost* non-zero
  status, so the pipeline's status is still 1. Five runs of the real script gave
  `rc=1` each time, with the temp list removed every time (the loop exits only
  its own subshell, and the parent's EXIT trap runs). The script also exits 1
  with SIGPIPE inherited as ignored (`trap '' PIPE` in the parent): git exits
  quietly on EPIPE and adds no stderr. No fix needed.
- **Ordering.** The pipeline is the first statement to fail under errexit, so
  `mkdir -p dist/plugin` and rsync never run. The suite's sentinel and
  not-copied `new.md` assertions cover this.
- **Bash 3.2 / BSD.** `*'*'*`, `*'?'*`, `*'['*`, `*']'*` and `*\\*` are plain
  POSIX `case` patterns: a quoted character or a backslash-escaped one matches
  literally. Nothing here depends on the bash version. This was checked by
  reading only, since no bash 3.2 binary is on this box (bash 5.2.37 here).

## Fixes applied

1. **Comment: "pipefail carries its status out" was wrong.** The loop is the
   pipeline's last stage, so its status becomes the pipeline's with or without
   `pipefail`. `pipefail` matters only because it keeps that 1 over git's 141,
   and errexit is what ends the script. The comment was rewritten to say exactly
   that.
2. **Stderr and comment: "rsync would read it as a pattern" is false for
   `a\b.log`.** Probed on rsync 3.5.0: the exclude `/a\b.log` matched the
   literal file and excluded it. That is consistent with outline decision 2,
   where a backslash is an escape only when a wildcard is present. The refusal
   of a lone backslash is the decision's uniform rule, not something rsync
   forces. The stderr line is now true for all five names:
   `dogfood: ignored entry '<entry>' holds a pattern character (* ? [ ] or \); sync refused`.
   The comment now gives the real reason: wildcards for the four, and an escape
   that depends on context for the backslash.
3. **`echo` of data → `printf '%s'`** (`shell-gotchas` rule 5). The entry can
   hold a backslash, which is exactly the operand `echo` leaves
   implementation-defined.

## Residual

- **A name holding a newline breaks the "one line" contract.** An entry that
  holds both a newline and a pattern character prints across two lines. Fixing
  it would mean transforming the displayed name (for example `\n` substitution).
  That makes the name ambiguous against a literal backslash, and a backslash is
  itself one of the refused characters. It costs more than it buys for a
  top-level ignored name that must also hold `* ? [ ]` or `\`, so it is left as
  is.

## Layout

Entry point first (`main`), then `usage`, `sync_copy`, then its helper
`root_dir`. Unchanged and conforming.

## Verification

- `bash tests/dogfood-test.sh`: all dogfood scenarios passed.
- `shellcheck toolkit/dogfood.sh`: clean.
- `just precommit` (unsandboxed): `ok`, exit 0.

## Refactor flagged

None.
