# Item 1.1/5 test review — pattern characters

Verdict: **red on assertions, discriminating; three fixes applied.** Nothing
committed or staged. `toolkit/dogfood.sh` untouched.

## Mechanical

`bash tests/dogfood-test.sh` against the committed SUT: 20 failures, all in this
slice, four per name (exit code, stderr, sentinel, new.md), each an assertion
failure; no harness error. The fixture ignore-list assertion passes for all five
names. Slices 1–4 and the later scenarios pass. `bash -n` and `shellcheck`
clean. Suite now 380 lines (was 367).

`a\b.log` is created with a literal backslash: single-quoted in the loop, and
the ignore-list assertion (`-z`, so git does not C-quote) matches `a\b.log|`;
`ls -b` of the same `printf > "$name"` in scratch shows `a\\b.log`. The stderr
match `[[ … == *"$name"* ]]` is literal: probed, `a*b.log` does not match
`aXb.log`, `a\b.log` does not match `a\\b.log`.

## Fixes

1. **stderr pinned to the interface.** Was "contains the name"; now one line
   starting `dogfood: ` and naming it (`!= "dogfood: "*"$name"*` or holding a
   newline fails). The Interfaces line asks for one `dogfood: …` line; the old
   check passed a multi-line or unprefixed message.
2. **Negative control added**: `a pattern character outside the ignore list` — a
   tracked `skills/demo/a*?[]\b.md` and an untracked non-ignored `a*?[]\b.md`,
   sync exits 0 and copies both. Nothing earlier covered an over-broad check
   (ordinary ignored names not aborting is already covered by slices 1 and 3).
   Green on the baseline, so discrimination is shown by mutation below.
3. **Comment corrected**: the sentinel is removed by `--delete` because it is
   not source, not by `--delete-excluded` as it said.

## Wrong-reason hunt — mutations

Each variant is `toolkit/dogfood.sh` plus a check, run with the edited suite
from a scratch copy (`/tmp/claude/dogfood-build/s5-review/<variant>/`, output in
`mutations.txt`).

| Variant | Result |
|---|---|
| correct: ignore list, `[][*?\\]`, before rsync, one named line | all pass |
| only `*` and `?` | 12 fail: `[`, `]`, `\` fixtures |
| check after rsync | 10 fail: sentinel + new.md per name |
| exits 1, prints nothing | 5 fail: stderr |
| prints `dogfood:` without the name | 5 fail: stderr |
| prints two lines | 5 fail: stderr (fix 1) |
| scans tracked paths (`ls-files -z`) | 23 fail: all 20 + negative control |
| scans tracked + untracked | 3 fail: negative control only (fix 2) |
| scans untracked incl. ignored (`-o`, no `-i`) | 3 fail: negative control only |

The "correct" variant going fully green also shows the slice is satisfiable as
specified (sentinel survives, one-line stderr, exit 1).

## Residuals

- Names are root-level only; an ignored entry holding a pattern character in a
  directory component is not exercised. The outline already bounds the check to
  the entries `--directory` yields.
- "`dist/plugin/` untouched" is observed through the pre-placed sentinel; a
  check placed after `mkdir -p` but before rsync is indistinguishable and
  harmless, since the directory already exists.
