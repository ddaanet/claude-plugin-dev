# Item A1 — GREEN

Scope: `toolkit/release.sh` and `tests/release-test.sh`. Fix at `release.sh:235`
(now `:235-249` with the added comment).

## Step 1 — a second red assertion, before touching production code

Added a `release`-mode scenario mirroring the existing `--resume` one:
`=== release: a malformed marketplace.json refuses before anything is public ===`,
using the same committed-corruption fixture, but via `new_sandbox "1.2.3"`
(which already tags and publishes v1.2.3, so `release_preflight` is reachable
without a setup release first) and `release.sh patch` directly, instead of
`--resume`.

Ran `TMPDIR=/tmp/claude-1000 bash tests/release-test.sh` against unchanged
`toolkit/release.sh`. The new scenario failed on 2 of its 7 assertions — the
message checks, exactly as predicted:

```
=== release: a malformed marketplace.json refuses before anything is public ===
FAIL: malformed-marketplace release names the failure mode: output did not contain 'could not read'
  --- output ---
jq: parse error: Unfinished JSON term at EOF at line 1, column 12
jq: parse error: Unfinished JSON term at EOF at line 1, column 12
hint: `just resume-release` completes a release that landed partially.
error: fix the version drift above before releasing
  --------------
FAIL: malformed-marketplace release names the file: output did not contain 'marketplace.json'
  --- output ---
jq: parse error: Unfinished JSON term at EOF at line 1, column 12
jq: parse error: Unfinished JSON term at EOF at line 1, column 12
hint: `just resume-release` completes a release that landed partially.
error: fix the version drift above before releasing
  --------------
```

One difference from the brief's prediction: the exit-code assertion
(`expected '1', got ...`) already passed today, because `common_preflight`'s
misread survives untouched (marketplace_entry_exists=0, no die), and
`release_preflight`'s `check-version.sh` call fails downstream, its non-zero
status caught by `|| { ... }`, which lands on the always-run
`die "fix the version drift above before releasing"` at `release.sh:437` —
itself an ordinary `die`, hence exit 1. Only the *message* is wrong today, not
the *code*. The other 5 assertions (no gh call, marketplace unchanged, no local
tag, no plugin tag pushed, marketplace origin untouched) already passed today
too, since nothing destructive runs before that die. Together with the
pre-existing 4 resume-mode failures, the full run showed 6 failures total, all
in the two new scenarios; every other scenario passed before and after.

## Step 2 — the fix

`release.sh:235` (now the `if`/`elif`/`else` at `:235-249`):

```bash
if jq -e --arg n "$plugin_name" 'any(.plugins[]; .name == $n)' "$marketplace_json" >/dev/null; then
    marketplace_entry_exists=1
elif [ "$?" -ne 1 ]; then
    die "could not read $marketplace_json — nothing was done"
else
    marketplace_entry_exists=0
    git remote get-url origin >/dev/null 2>&1 \
        || die "'$plugin_name' has no entry in $marketplace_json and no 'origin' remote to derive one from"
fi
```

Added a comment above it (matching the surrounding density) recording: `jq -e`
returns 1 for a clean no-match and non-1 (5, measured jq 1.7) for a parse error;
the old two-branch `if` read both alike; in `--resume` mode nothing downstream
reads the file until `bump_marketplace`, since `release_preflight` never runs on
resume (`release.sh:780-785`), so the misread survived `common_preflight`
untouched and the run reached `create_github_release` — a GitHub release made
public — before `bump_marketplace`'s own jq call aborted the script raw instead
of via `die`. No bypass or skip offered in the message.

## Step 3 — verify

- Full suite green: `TMPDIR=/tmp/claude-1000 bash tests/release-test.sh` — all
  scenarios passed, including both new ones.
- `just precommit`: first invocation hit 1 transient failure inside
  `update-plugin-dev-test.sh` (unrelated to this change — this box is
  memory-constrained per standing guidance); a clean re-run passed fully, ending
  `ok`, with `git status --short` showing only the two intended files modified
  plus the pre-existing untracked RED report both before and after.
- Mutation 1 (revert `elif` to the old two-branch `if`): reverted, ran the suite
  — both new scenarios' message assertions failed again (6 failures total,
  matching the original RED run exactly), confirming the new assertions catch
  the regression. Restored the fix (diffed byte-identical against a saved copy)
  and re-ran green.
- Mutation 2 (mutate the `die` message prose to
  `"marketplace.json is unreadable — nothing was done"`, keeping the `elif`
  logic intact): ran the suite — 2 failures, one per scenario, both
  `... names the failure mode: output did not contain 'could not read'`,
  confirming the suite pins the exact wording, not just the branch taken.
  Restored the exact fix text and re-ran green.

## Step 4 — commit

Staged `toolkit/release.sh`, `tests/release-test.sh`, and this report only (no
`git add -A`). `just format-docs` run before staging this report.

Commit: (recorded below after committing)
