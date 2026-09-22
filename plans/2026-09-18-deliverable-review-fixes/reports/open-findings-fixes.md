# Open findings from the deliverable review — fixes, 2026-09-22

Three findings left unacted when the plan closed. All three are now addressed.
Nothing is committed: the working tree carries the changes and
`git status --short` is at the foot of this report.

## Finding 1 — `reports/item-3-5.md` contradicts itself

An `## Erratum — 2026-09-22` section is appended to
`plans/2026-09-18-deliverable-review-fixes/reports/item-3-5.md`. The report's
own text is untouched; the heading stands as written.

**The discrepancy, named precisely.** The offending line is the section heading
"### 1. `tests/version-guard-test.sh:17` — leaked-git-environment citation,
stale". The citation it heads is `See release-test.sh:8-13`, and that citation
was never stale. Measured, not read:

- `git log -S'release-test.sh:8-13' -- tests/version-guard-test.sh` names
  `e229e1b` ("✅ one script under test per suite file") as the commit that wrote
  it.
- `git show e229e1b:tests/release-test.sh | sed -n '8,13p'` is exactly the
  leaked-git-environment comment block, ending on line 13 with
  `unset $(git rev-parse --local-env-vars)`.
- The same read at `9ba5dd5^` — the tree Item 3.5 converted — gives the same six
  lines.

So the runbook's stated ground for the "stale" label (`runbook-test-suites.md`,
Item 3.5: "off by one at each end — it takes in `set -euo pipefail` and stops
short of the `unset` line") does not hold at either commit. The report's own
opening line, "the stale/accurate `<script>.sh:<line>` citations it finds", is
the accurate wording, and
`docs/changelog/2026-09-20-deliverable-review-fixes.md` records the same mix
rather than calling all five stale. `phase-4-corrector.md` had flagged the
heading in its verification table and left it standing because `plans/` is
frozen; the erratum is the record that note pointed at.

**A residual the erratum states and does not fix.** The changelog's count, "Four
of the five", inherits the runbook's label for this citation. Counting only the
citations measured to have drifted, three of five were stale
(`release.sh:780-785`, `:446-455`, `:456-460`). The fifth, `release.sh:138` in
`tests/release-test.sh`, was written in `cfb4bc2` and lands on
`tree_is_clean "."` there — accurate, as the runbook itself says. The changelog
is a dated record and is not revised; the number is noted in the erratum
instead. **This is worth a decision:** the changelog's sentence is now known to
be one off, and nothing else records that.

## Finding 2 — the `grep -q --` conversion, measured rather than argued

### (a) The measurement

A one-off run, not a permanent test — the check is a runtime instrumentation of
the two helpers, which a permanent version would have to carry in the suite
forever to re-measure something that only changes when a needle changes.

Method: `git archive HEAD | tar -x -C "$TMPDIR/vg-probe"`, then in that export
only, both helpers in `tests/version-guard-test.sh` were prefixed with a probe
that, for every call, records the needle and compares the two matchers on the
real haystack:

```sh
_probe_needle() {
    case "$2" in
        *$'\n'*) printf 'NEEDLE-SPANS-NEWLINE\t%s\n' "$2" >> "$PROBE_LOG" ;;
    esac
    local g=0 r=0
    [[ "$1" == *"$2"* ]] || g=1
    printf '%s' "$1" | grep -q -- "$2" || r=1
    if [ "$g" != "$r" ]; then
        printf 'DIVERGENCE\tglob=%s\tgrep=%s\t%s\n' "$g" "$r" "$2" >> "$PROBE_LOG"
    fi
    printf 'NEEDLE\tglob=%s\tgrep=%s\t%s\n' "$g" "$r" "$2" >> "$PROBE_LOG"
}
```

Result — `bash tests/version-guard-test.sh` in that export, exit `0`, closing
`all version-guard scenarios passed`:

```
calls recorded: 27
spans-newline: 0
divergence: 0
--- per-call glob/grep verdict counts ---
     11 glob=0	grep=0
     16 glob=1	grep=1
--- distinct needles (cat -v) ---
9.9.9
Do not bypass this guard, modify the recipe, or alter version state by
just release
last released version
never been released
settings.json
tag^_--list
version-guard
will publish
```

What that establishes, stated as a bound and not more: over the
**27 helper calls the suite actually executes** (20 static call sites;
`assert_no_escape_hatch` re-enters some of them), carrying
**9 distinct needles**, no needle contains a newline, and the glob form and
`grep -q --` agree on every single call — 11 matches and 16 non-matches,
identical verdicts. `tag^_--list` is the raw `\037`-separated needle rendered by
`cat -v`; it is among the 27 agreeing calls, so Item 3.4's hazard 1 is now
measured at runtime rather than argued from the byte not being a BRE
metacharacter.

The measurement covers the needles reached on a green run. A needle only reached
on a failing path is outside it; there is none in this suite, since every call
site is unconditional within its scenario.

### (b) The residual-bound comment

Added to both helper definitions in all five suites that use the form — the four
named in the finding plus `tests/citation-test.sh`, which carries the same
helpers and had no such comment either:

```sh
    # Residual bound: the needle is a grep BRE matched line by line --
    # a metacharacter in it is live, and a needle that spans a newline
    # can never match.
```

The four-way identity the Item 3.4 report established is preserved, and now
holds across five: stripping comments from the two helper bodies in each of
`tests/version-guard-test.sh`, `tests/release-test.sh`,
`tests/self-release-test.sh`, `tests/update-plugin-dev-test.sh` and
`tests/citation-test.sh` gives the same md5 (`39f62b6e…`) for all five.
`version-guard-test.sh`'s extra haystack-constraint comment on `assert_contains`
survives above the new lines.

## Finding 3 — the three missing GREEN reports

Written, each headed "**Written retroactively on 2026-09-22**, after the fact":

- `reports/item-1-1-s2-green.md` — commit `45891f8`
- `reports/item-1-2-s1-green.md` — commit `d0c13b9`
- `reports/item-1-3-s2-green.md` — commit `6a77bea`

Each carries its `git show --stat`, and the suite result **measured** at that
commit rather than inferred: `git archive <sha> | tar -x -C "$TMPDIR/<sha>"`,
then the suite the commit touches run from inside the export. All three suites
run fine from an exported tree without a real `.git` — they build fixture repos
under a temp dir and locate the script under test through `repo_root` derived
from `$0`.

| Commit | Suite | Exit | Closing line | Scenario lines | FAIL lines |
|---|---|---|---|---|---|
| `45891f8` | `tests/release-test.sh` | 0 | `all release scenarios passed` | 62 | 0 |
| `d0c13b9` | `tests/release-test.sh` | 0 | `all release scenarios passed` | 63 | 0 |
| `6a77bea` | `tests/self-release-test.sh` | 0 | `self-release.sh: ok` | 13 | 0 |

Each commit's newly added scenario printed exactly once in its own run
(`pipefail-stripped release_tags failure publishes nothing`,
`resume hint names the tag already on origin`,
`release tag off ancestry still triggers drift guard`).

What could not be established, and each report says so in a "What this report
does not carry" section: the original dispatch's own `just precommit` output is
gone — not written down, which is the gap itself. The reports claim the narrower
measured thing (the suite is green at that commit; the commit carries only its
test file) rather than reconstructing a gate run and presenting it as a record.

## `just precommit` — foreground, green

```
$ cd /Users/david/code/claude-plugin-dev && just precommit
...
bash tests/doc-sync-test.sh
=== the root README's install/update commands appear in the toolkit README ===
=== CLAUDE.md's Layout list matches toolkit/ ===

doc sync ok (5 shared command blocks, Layout matches toolkit/)
bash tests/citation-test.sh
=== citation gate: self-fixture discriminates tracked from plans/ ===
=== citation gate: this repo ===

citations ok (self-fixture discriminates tracked from plans/, no <script>.sh:<line> citation in tracked files outside plans/ and docs/changelog/)
ok
```

Exit code `0`. All nine suites ran; no intermittent `release-test.sh` or
`version-guard-test.sh` failure appeared, so no standalone re-run was needed.
`format-docs` reflowed the four markdown files this pass wrote or edited (MD013
paragraph normalization, reported `[fixed]`); the pre-existing MD013 warnings in
older `plans/` reports are untouched and unrelated.

## Files changed

- `/Users/david/code/claude-plugin-dev/plans/2026-09-18-deliverable-review-fixes/reports/item-3-5.md`
  (erratum appended)
- `/Users/david/code/claude-plugin-dev/plans/2026-09-18-deliverable-review-fixes/reports/item-1-1-s2-green.md`
  (new)
- `/Users/david/code/claude-plugin-dev/plans/2026-09-18-deliverable-review-fixes/reports/item-1-2-s1-green.md`
  (new)
- `/Users/david/code/claude-plugin-dev/plans/2026-09-18-deliverable-review-fixes/reports/item-1-3-s2-green.md`
  (new)
- `/Users/david/code/claude-plugin-dev/plans/2026-09-18-deliverable-review-fixes/reports/open-findings-fixes.md`
  (new — this file)
- `/Users/david/code/claude-plugin-dev/tests/version-guard-test.sh`
- `/Users/david/code/claude-plugin-dev/tests/release-test.sh`
- `/Users/david/code/claude-plugin-dev/tests/self-release-test.sh`
- `/Users/david/code/claude-plugin-dev/tests/update-plugin-dev-test.sh`
- `/Users/david/code/claude-plugin-dev/tests/citation-test.sh`

## `git status --short`

```
M  .claude/handoff-todo.md
 m memory
 M plans/2026-09-18-deliverable-review-fixes/reports/item-3-5.md
 M tests/citation-test.sh
 M tests/release-test.sh
 M tests/self-release-test.sh
 M tests/update-plugin-dev-test.sh
 M tests/version-guard-test.sh
?? plans/2026-09-18-deliverable-review-fixes/reports/item-1-1-s2-green.md
?? plans/2026-09-18-deliverable-review-fixes/reports/item-1-2-s1-green.md
?? plans/2026-09-18-deliverable-review-fixes/reports/item-1-3-s2-green.md
```

Sandbox dotfile masks omitted. The staged `.claude/handoff-todo.md` and the
dirty `memory` gitlink were there before this pass and were not touched by it:
`git -C memory status --short` shows `M MEMORY.md` plus an untracked
`precommit-intermittent-suite-failure.md`, neither of them written here.
