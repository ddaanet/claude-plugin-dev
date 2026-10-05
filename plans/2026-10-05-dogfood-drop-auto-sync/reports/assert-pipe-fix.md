# Assertion helpers piped into an early-exiting grep under pipefail

`tests/self-release-test.sh` failed once in a pre-commit run with
`happy: dist tree has README: output did not contain 'README.md'` while
`README.md` was the first line of the output. Its `assert_contains` ran
`printf '%s' "$1" | grep -q -- "$2"` under `set -euo pipefail`: `grep -q` exits
on its first match, `printf` takes SIGPIPE on the unread rest, and pipefail
reports the pipeline as failed. The same shape was copied across the suites and
inlined in a few more checks.

## Audit

Every file under `tests/` was searched for a pipeline ending in an early-exiting
reader (`grep -q`, `grep -m`, `head`, `sed …q`, an `awk` with `exit`). Only
`grep -q` occurs. Readers that consume all input (`grep -c`, `grep -o`,
`grep -v`, `tail`, `wc`, `cut`, `sort`, `jq -e`, the `awk` in
`doc-sync-test.sh`) were left alone.

`assert_contains` (a present match reads as absent, so the assertion fails
wrongly) is in nine suites: `citation`, `dogfood-pre-tool`,
`dogfood-sync-refusal`, `dogfood-sync`, `install`, `release`, `self-release`,
`update-plugin-dev`, `version-guard`.

`assert_not_contains` (the negated form: a present match reads as absent, so the
assertion **passes wrongly**) is in five of them: `citation`, `release`,
`self-release`, `update-plugin-dev`, `version-guard`.

Inline checks with the same shape:

- `tests/check-version-test.sh`, four `echo "$out" | grep -q … || fail` checks:
  fails wrongly.
- `tests/release-test.sh`, the marketplace-push resume's
  `if printf '%s' "$out" | grep -q "already complete (nothing to do)"; then fail`:
  passes wrongly.
- `tests/dist-tree-test.sh`'s gitlink check, and `assert_clean_vendor` in
  `tests/install-test.sh` and `tests/update-plugin-dev-test.sh`, which run
  `if git ls-files -s … | grep -q '^160000'; then fail`: git is the writer
  there, and a present gitlink reads as absent, so the check passes wrongly. On
  an index large enough to fill the pipe this is a real hole, not a theoretical
  one (probe below).

Comments in `tests/release-test.sh` that quote the `grep -qxF` pipe describe
`toolkit/release.sh`'s old ladder. That code already uses a here-string, so
those comments were left unchanged.

## Before: deterministic reproduction

`$TMPDIR/assert-probe/probe.sh <suite>` pulls `fail`, `assert_contains` and,
where present, `assert_not_contains` out of the suite verbatim with awk and
`eval`s them under `set -euo pipefail`. It then runs each 20 times against a 600
KB haystack whose first line is the needle (`README.md`). A correct helper never
fails `assert_contains` and always fails `assert_not_contains`.

```text
citation-test.sh                   assert_contains: 20/20 wrongly failed; assert_not_contains: 20/20 wrongly passed
dogfood-pre-tool-test.sh           assert_contains: 20/20 wrongly failed; assert_not_contains: n/a
dogfood-sync-refusal-test.sh       assert_contains: 20/20 wrongly failed; assert_not_contains: n/a
dogfood-sync-test.sh               assert_contains: 20/20 wrongly failed; assert_not_contains: n/a
install-test.sh                    assert_contains: 20/20 wrongly failed; assert_not_contains: n/a
release-test.sh                    assert_contains: 20/20 wrongly failed; assert_not_contains: 20/20 wrongly passed
self-release-test.sh               assert_contains: 20/20 wrongly failed; assert_not_contains: 20/20 wrongly passed
update-plugin-dev-test.sh          assert_contains: 20/20 wrongly failed; assert_not_contains: 20/20 wrongly passed
version-guard-test.sh              assert_contains: 20/20 wrongly failed; assert_not_contains: 20/20 wrongly passed
```

`$TMPDIR/assert-probe/inline-probe.sh` runs each inline shape verbatim against a
600 KB first-line match. For the gitlink shape it uses a scratch repo whose
index holds a `160000` entry first, then 10000 files. The result was the same on
all three runs:

```text
check-version echo|grep -q || fail: failures=1 (expect 0)
release-test if printf|grep -q (match present): detected=no (expect yes)
assert_clean_vendor/dist-tree if git ls-files|grep -q (gitlink present): detected=no (expect yes)
```

## Fix

No pipeline remains in any of these checks. Each helper now runs
`grep -q -- "$2" <<<"$1"`, and a two-line comment says why it must not be a
pipe. The pattern semantics are unchanged: every helper was BRE without `-F` and
stays BRE without `-F`. The check-version and resume checks now run
`grep -q "…" <<<"$out"`. The gitlink checks first capture `git ls-files -s …`
into a variable (`toolkit_index`, or a `local vendor_index`) and then grep it
with a here-string. A failing `git` now aborts under `set -e`, where before it
silently read as "no gitlink".

The input changes in one way. A here-string appends a newline, so an empty
haystack becomes one empty line, and a needle that matches an empty line (`''`,
`^$`) would now match it. No caller passes such a needle. A search of every
`assert_contains`/`assert_not_contains` call found none.

Files changed: `tests/check-version-test.sh`, `tests/citation-test.sh`,
`tests/dist-tree-test.sh`, `tests/dogfood-pre-tool-test.sh`,
`tests/dogfood-sync-refusal-test.sh`, `tests/dogfood-sync-test.sh`,
`tests/install-test.sh`, `tests/release-test.sh`, `tests/self-release-test.sh`,
`tests/update-plugin-dev-test.sh`, `tests/version-guard-test.sh`. Each suite
keeps its own copy of the harness.

## After: same probes against the fixed code

```text
citation-test.sh                   assert_contains: 0/20 wrongly failed; assert_not_contains: 0/20 wrongly passed
dogfood-pre-tool-test.sh           assert_contains: 0/20 wrongly failed; assert_not_contains: n/a
dogfood-sync-refusal-test.sh       assert_contains: 0/20 wrongly failed; assert_not_contains: n/a
dogfood-sync-test.sh               assert_contains: 0/20 wrongly failed; assert_not_contains: n/a
install-test.sh                    assert_contains: 0/20 wrongly failed; assert_not_contains: n/a
release-test.sh                    assert_contains: 0/20 wrongly failed; assert_not_contains: 0/20 wrongly passed
self-release-test.sh               assert_contains: 0/20 wrongly failed; assert_not_contains: 0/20 wrongly passed
update-plugin-dev-test.sh          assert_contains: 0/20 wrongly failed; assert_not_contains: 0/20 wrongly passed
version-guard-test.sh              assert_contains: 0/20 wrongly failed; assert_not_contains: 0/20 wrongly passed
```

The inline probe, rewritten to the fixed shapes, gave the same result on all
three runs:

```text
check-version echo|grep -q || fail: failures=0 (expect 0)
release-test if printf|grep -q (match present): detected=yes (expect yes)
assert_clean_vendor/dist-tree if git ls-files|grep -q (gitlink present): detected=yes (expect yes)
```

## Gate

`just precommit` was run in the foreground and exited 0 with no `FAIL` lines.
These checks passed:

- `whitespace`
- `format-docs`, with only the advisory MD013 notes that were already there
- `shellcheck`
- `bash -n` on every suite
- `_import-check` (plain, widened and missing gate, `resume-release`, `dogfood`)
- the `version-guard`, `check-version`, `release`, `self-release`,
  `update-plugin-dev`, `install`, `dist-tree` (11 files, no gitlink), `docs`,
  `doc-sync`, `citation`, `dogfood-sync`, `dogfood-sync-refusal`,
  `dogfood-pre-tool`, `dogfood-session-start` and `dogfood-launcher` suites

The commit hook runs the same gate again on the commit that carries this report.
