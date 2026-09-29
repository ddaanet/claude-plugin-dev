# Item 1.1/3 test review: names with spaces survive

Verdict: **fixed, green**. The scenario was extended. Every assertion in it is
now shown to be the only one that reds under some mutation of `sync`. Nothing is
staged or committed.

## Check 1: reproduce the red with a different mutation

The RED report used `read -d ' '`. This review used the mutation M1, unquoting
the printf argument in `toolkit/dogfood.sh`: `printf '/%s\0' "$entry"` →
`printf '/%s\0' $entry`. Each entry is then word-split into separate patterns.
Against the RED's test as written, only the new scenario failed, and it failed
on its own assertions:

```text
FAIL: names with spaces survive: an ignored file under a spaced directory is absent: '.../my consumer/dist/plugin/out dir/x' exists
FAIL: names with spaces survive: the ignored spaced directory is absent: '.../my consumer/dist/plugin/out dir' exists
2 failure(s)
```

The mutation was restored by the inverse exact-string Edit. After that,
`git diff --quiet toolkit/dogfood.sh` exited 0 and the suite printed
`all dogfood scenarios passed`.

## Check 2: wrong-reason findings

1. **Only one list shape was tested.** `/out dir/` is a wholly ignored
   directory, which `--directory` collapses to the single entry `out dir/`. A
   lone ignored file inside a directory that also holds tracked content is
   listed as itself, with spaces in the middle of the path
   (`skills/a b/draft x.log`). The test never exercised that shape. **Fixed:**
   added it with a `*.log` ignore.
2. **`IFS=` was pinned by nothing.** Without it, `read` trims leading and
   trailing whitespace from each entry. No spaced name in the test started or
   ended with whitespace, so dropping `IFS=` stayed green. **Fixed:** added an
   ignored root-level ` lead.log`. A trailing-space name was not used, because
   `.gitignore` drops unescaped trailing spaces from its patterns.
3. **The NUL-delimited git side was pinned by nothing.** The SUT's comment
   claims that a newline in a name survives. With `-z` dropped and a
   newline-delimited `read`, spaces still survive, so the test stayed green.
   **Fixed:** added an ignored `nl<newline>x.log`. Without `-z`, git also
   C-quotes this name, so its exclude never matches.
4. **The tracked presence assertion earns its place.** The RED report was right
   that no whitespace bug in the ignore list reddens it. Its role is different:
   it pairs with the absences. A sync that dropped every spaced name would pass
   all of them. It is now a sibling of the ignored `draft x.log` in the same
   spaced directory, so the two paths differ only in what excludes them.
   Mutation M4 below shows it is the only assertion that catches that sync.
5. **The fixture's shapes were not guarded.** The absences only mean what their
   labels say if git lists each name in the intended shape. The old
   `check-ignore` guard is replaced by an `assert_eq` on the whole NUL list
   (`tr '\0' '|'`): `" lead.log|nl\nx.log|out dir/|skills/a b/draft x.log|"`. If
   the fixture drifts, for example the draft's directory losing its tracked file
   and collapsing, that guard fails first.
6. **One assertion was redundant.** The absence of `out dir/x` follows from the
   absence of `out dir` and never failed alone, so it was dropped.

## Check 3: per-assertion discrimination of the revised test

Each mutation was applied in place and confirmed with `git diff`. Each was
restored by the inverse exact-string Edit, then proven with
`git diff --quiet toolkit/dogfood.sh` and a green suite before the next one.

| Mutation | Failing assertions (whole suite) |
|---|---|
| M1 `printf '/%s\0' $entry` (word-split) | `out dir`, `draft x.log`, ` lead.log`, `nl<newline>x.log` (4) |
| M2 `while read -r -d ''` (no `IFS=`) | ` lead.log` only |
| M3 `ls-files` without `-z`, `read -r` on newlines | `nl<newline>x.log` only |
| M4 hard exclude `'* *'` added | the tracked `skills/a b/SKILL.md` presence only |

After the final restore, `git diff --quiet toolkit/dogfood.sh` exited 0,
`bash -n` and `shellcheck` on `tests/dogfood-test.sh` were clean, and the suite
printed `all dogfood scenarios passed`. The suite is 295 lines.

## Findings for the lead

- The scenario name `names with spaces survive` is the slice's verbatim name,
  but the scenario now covers leading-space and newline names too. The comment
  above it says so. Rename it only if the runbook's slice text changes to match.
- Portability is unverified. `tr '\0' '|'` and a newline in a filename should
  work on macOS (BSD `tr` accepts `\0`, and APFS allows newlines), but the macOS
  suite run from outline Risks has not happened yet.
- No SUT gap was found. The committed `sync` passes every new case.
