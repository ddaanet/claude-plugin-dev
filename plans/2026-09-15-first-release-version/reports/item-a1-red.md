# Item A1 — RED

Scope: `tests/release-test.sh` only. `toolkit/release.sh` untouched. No commit.
Suite run: `TMPDIR=/tmp/claude-1000 bash tests/release-test.sh` from repo root —
4 failures, all in the new scenario; every other scenario in the file passes,
before and after it.

## Scenario added

`=== resume: a malformed marketplace.json refuses before anything is public ===`
(`tests/release-test.sh`, appended just before the pass/fail summary at the end
of the file).

Modeled on the "resume: no-op on a healthy repo" fixture (`:520` in the pre-edit
file): `new_sandbox "1.2.3"`, a normal `patch` release to completion, then
`: > "$GH_LOG"` to isolate what the `--resume` call itself does. Between setup
and resume, `marketplace.json` is truncated to `{"plugins":[` and the truncation
is **committed** in the marketplace repo (not merely written) — committing is
load-bearing: an uncommitted corruption would be caught by `tree_is_clean` in
`common_preflight` (`release.sh:248`) for an unrelated reason (a dirty
marketplace tree) before ever reaching the entry-check jq call this item is
about, and that refusal already exists today. Committing puts the marketplace
tree back at "clean" while its content still fails to parse, which is the actual
state A1 is about.

```bash
new_sandbox "1.2.3"
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "0" "setup release exit code"
: > "$GH_LOG"
printf '{"plugins":[' > "$marketplace/.claude-plugin/marketplace.json"
git -C "$marketplace" add -A
git -C "$marketplace" commit -qm "corrupt marketplace.json"
market_before="$(cat "$marketplace/.claude-plugin/marketplace.json")"
plugin_origin_tags_before="$(git -C "$plugin-origin.git" tag --list)"
market_origin_head_before="$(git -C "$marketplace-origin.git" rev-parse main)"
run_in "$plugin" bash plugin-dev/release.sh --resume
assert_eq "$rc" "1" "malformed-marketplace resume exit code"
assert_contains "$out" "could not read" "malformed-marketplace resume names the failure mode"
assert_contains "$out" "marketplace.json" "malformed-marketplace resume names the file"
assert_eq "$(cat "$GH_LOG")" "" "malformed-marketplace resume must not call gh"
assert_eq "$(cat "$marketplace/.claude-plugin/marketplace.json")" "$market_before" \
    "malformed-marketplace resume left marketplace.json exactly as it found it"
assert_eq "$(git -C "$plugin-origin.git" tag --list)" "$plugin_origin_tags_before" \
    "malformed-marketplace resume pushed no new plugin tag"
assert_eq "$(git -C "$marketplace-origin.git" rev-parse main)" "$market_origin_head_before" \
    "malformed-marketplace resume pushed nothing to the marketplace origin"
```

## Why the flow reaches `create_github_release` today

Traced against `toolkit/release.sh` and confirmed by running `jq -e` and the two
plain `jq` calls in `bump_marketplace` against a copy of the truncated fixture
(jq 1.7, this environment): every one of the three invocations exits **5** on
the parse error, same as the team lead's measurement for the `-e` form.

1. `common_preflight`'s entry check (`release.sh:235`) — `jq -e ... any(...)` —
   exits 5. The `if` only distinguishes zero from non-zero, so this reads
   identically to "no entry": `marketplace_entry_exists=0`, and the `origin`
   remote check that follows succeeds (the fixture has one), so
   `common_preflight` does not die here.
2. `tree_is_clean "$MARKETPLACE_DIR"` (`release.sh:248`) passes, because the
   corruption was committed — this is exactly what the committed-not-staged
   fixture choice buys.
3. Mode is `resume`, so `resume_preflight` runs instead of `release_preflight` —
   it only checks that `refs/tags/v1.2.4` exists locally (it does, from the
   setup release) and never reads `marketplace.json`.
4. `push_branch`, `push_tag`, `create_github_release` all run as no-ops against
   already-published state, but `create_github_release` still calls
   `gh release view v1.2.4` — one call, logged to `$GH_LOG`.
5. `bump_marketplace` takes the entry-creation branch (`release.sh:673-688`,
   since `marketplace_entry_exists=0` from step 1) and runs
   `jq --slurpfile m ... "$marketplace_json"`, which fails to parse and — not
   wrapped in `|| die`, executing directly under `set -e` — aborts the whole
   script with jq's own exit status and stderr text, not a `die`-formatted
   message.

## Red output (verbatim)

```
=== resume: a malformed marketplace.json refuses before anything is public ===
FAIL: malformed-marketplace resume exit code: expected '1', got '5'
FAIL: malformed-marketplace resume names the failure mode: output did not contain 'could not read'
  --- output ---
jq: parse error: Unfinished JSON term at EOF at line 1, column 12
branch main: already pushed
github tag v1.2.4: already pushed
github release v1.2.4: already created
jq: parse error: Unfinished JSON term at EOF at line 1, column 12
  --------------
FAIL: malformed-marketplace resume names the file: output did not contain 'marketplace.json'
  --- output ---
jq: parse error: Unfinished JSON term at EOF at line 1, column 12
branch main: already pushed
github tag v1.2.4: already pushed
github release v1.2.4: already created
jq: parse error: Unfinished JSON term at EOF at line 1, column 12
  --------------
FAIL: malformed-marketplace resume must not call gh: expected '', got 'release view v1.2.4'
```

The `$GH_LOG` assertion the brief called out —
`malformed-marketplace resume must not call gh` — fails today exactly as
expected: `github release v1.2.4: already created` in `$out` and
`release view v1.2.4` in `$GH_LOG` are both `create_github_release`'s doing,
reached before the script dies. It fails alongside three others, not alone: the
exit code is jq's raw 5 rather than `die`'s 1, and the raw
`jq: parse error: ...` text carries neither `could not read` nor the literal
string `marketplace.json` (the path jq was given is
`$sandbox/marketplace/.claude-plugin/marketplace.json`, which does contain that
substring — but jq never printed the path at all, only its own parse
diagnostic). All four are the same underlying defect surfacing on different
assertions; none is a fixture or setup error. The three assertions before
`$GH_LOG` in the file (`market_before` unchanged, plugin origin tags unchanged,
marketplace origin HEAD unchanged) already pass today — the current code's
failure happens before any of those three states could move, which is consistent
with the trace above (the abort in step 5 happens before `bump_marketplace` ever
writes to `$marketplace_json` or pushes anywhere).

## Pre-existing scenarios

Every scenario before and after the new one passed in the same run (58 prior
`===` headers, all green; final tally 4 failures total, all in the new
scenario). `bash -n tests/release-test.sh` is clean.

## Existing malformed-`marketplace.json` coverage — none found

Grepped `tests/release-test.sh` and `tests/hook-test.sh` for `malformed`,
`parse error`, `could not read`, `truncat`, `corrupt`. Only hit:
`tests/update-plugin-dev-test.sh:383-394`, which exercises a malformed
`settings.json` in `install.sh` — an unrelated script and an unrelated file.
`tests/hook-test.sh` touches `marketplace.json` only for `check-version.sh`'s
missing-file and version-drift scenarios (`:438-483`), never a parse failure. No
scenario in either file already exercises a malformed `marketplace.json`, so
there is no interaction for GREEN to worry about disturbing.

## Environment note

`jq -e`'s exit-5 behavior on a parse error was re-measured directly in this
sandbox (`/tmp/claude-1000`, since `/tmp` itself is read-only here) against jq
1.7, for both the boolean-check form and the two plain `jq` forms
`bump_marketplace` uses — all three: exit 5, matching the team lead's brief.

`just format-docs` run over this report; no changes needed beyond what was
already written at ≤80 columns.
