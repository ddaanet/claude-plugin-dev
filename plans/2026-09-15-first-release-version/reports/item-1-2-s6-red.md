# Item 1.2, slice 6 — RED report

## Scenario code

Added to `tests/release-test.sh`, immediately before the closing
`if (( failures > 0 ))` block (the suite's last scenario):

```sh
echo "=== release: an initial release whose entry disagrees with the manifest is still refused ==="
new_sandbox "1.2.3"       # entry recorded at 1.2.3...
make_virgin "0.1.0"       # ...but the plugin has never been tagged, locally or on origin: the
                          # lost-tags probe (above) finds nothing either way, so this state is
                          # verifiably unpublished — decision 1's hint, not resume, is the one
                          # that must fire here.
run_in "$plugin" bash plugin-dev/release.sh
assert_eq "$rc" "1" "initial-entry-disagrees exit code"
assert_contains "$out" "0.1.0" "initial-entry-disagrees names the manifest version"
assert_contains "$out" "1.2.3" "initial-entry-disagrees names the marketplace entry version"
assert_contains "$out" "no release is recorded at" \
    "initial-entry-disagrees says neither version has a recorded release"
assert_contains "$out" "correct the marketplace entry" \
    "initial-entry-disagrees points at the marketplace entry as the one to correct"
assert_contains "$out" "set .version in .claude-plugin/plugin.json" \
    "initial-entry-disagrees offers editing the manifest instead, if 1.2.3 is the intended version"
assert_not_contains "$out" "just resume-release" \
    "initial-entry-disagrees must not offer resume — nothing was ever released to resume"
assert_eq "$(git -C "$plugin" tag --list 'v*')" "" "initial-entry-disagrees created no tag"
assert_eq "$(cat "$GH_LOG")" "" "initial-entry-disagrees must not call gh"
```

`new_sandbox "1.2.3"` seeds a marketplace entry at `1.2.3` (matching the fixture
plugin's initial manifest and its `v1.2.3` tag). `make_virgin "0.1.0"` then
strips `v1.2.3` both locally and on origin and rewrites the manifest to `0.1.0`,
so the plugin reaches `release_preflight` with **no semver tag anywhere** — the
lost-tags guard's own origin probe (Item 1.2 slices 1-5) finds nothing on origin
either, so by the time `check-version.sh` runs the plugin is verifiably
unpublished. `check-version.sh` then fails on `0.1.0` (manifest) vs `1.2.3`
(entry) — the disagreement decision 1 is about.

## Verbatim RED output (this scenario only)

```
=== release: an initial release whose entry disagrees with the manifest is still refused ===
FAIL: initial-entry-disagrees says neither version has a recorded release: output did not contain 'no release is recorded at'
  --- output ---
check-version: version drift — plugin.json=0.1.0 marketplace.json=1.2.3
  bump both to the same value before release.
hint: `just resume-release` completes a release that landed partially.
error: fix the version drift above before releasing
  --------------
FAIL: initial-entry-disagrees points at the marketplace entry as the one to correct: output did not contain 'correct the marketplace entry'
  --- output ---
check-version: version drift — plugin.json=0.1.0 marketplace.json=1.2.3
  bump both to the same value before release.
hint: `just resume-release` completes a release that landed partially.
error: fix the version drift above before releasing
  --------------
FAIL: initial-entry-disagrees offers editing the manifest instead, if 1.2.3 is the intended version: output did not contain 'set .version in .claude-plugin/plugin.json'
  --- output ---
check-version: version drift — plugin.json=0.1.0 marketplace.json=1.2.3
  bump both to the same value before release.
hint: `just resume-release` completes a release that landed partially.
error: fix the version drift above before releasing
  --------------
FAIL: initial-entry-disagrees must not offer resume — nothing was ever released to resume: output contained 'just resume-release'
  --- output ---
check-version: version drift — plugin.json=0.1.0 marketplace.json=1.2.3
  bump both to the same value before release.
hint: `just resume-release` completes a release that landed partially.
error: fix the version drift above before releasing
  --------------

4 failure(s)
```

Full-suite run: exit 1, `4 failure(s)`, all four listed above and no others.
Every other `echo "==="` scenario in the file printed with no `FAIL:` line under
it (checked against the full captured log, all 46 pre-existing scenarios plus
this one).

## Per-assertion status

| # | Assertion | Status today | Why |
|---|---|---|---|
| 1 | exit 1 | **passes** | `check-version.sh`'s existing drift refusal already exits 1 — decision 1 keeps the refusal, only changes its wording, so this was never going to be red on its own. |
| 2a | names `0.1.0` | **passes** | `check-version.sh`'s own drift line already prints `plugin.json=0.1.0`. |
| 2b | names `1.2.3` | **passes** | Same line prints `marketplace.json=1.2.3`. |
| 3 | "no release is recorded at" | **red** | Wording that does not exist yet. |
| 4 | "correct the marketplace entry" | **red** | Wording that does not exist yet. |
| 5 | "set .version in .claude-plugin/plugin.json" | **red** | This exact phrase already exists in `release.sh` (the first-release bump-refusal hint at `:336`), but that branch only fires when `bump_arg` is set; this scenario runs with no argument, so it is unreached and the phrase does not appear in this scenario's output today. Reusing it is deliberate — same remedy phrased the same way, one convention instead of two. |
| 6 | not "just resume-release" | **red** | Today's `release_preflight` prints this hint unconditionally on a `check-version.sh` failure (`release.sh:319-320` in the current file) — that is the whole point of the slice. |
| 7 | no local tag created | **passes** | `make_virgin` already leaves no local `v*` tag, and the run dies in preflight before any tagging. |
| 8 | `$GH_LOG` empty | **passes** | The run dies before `push_branch`/`create_github_release`; `gh` is never invoked either way. |

Four of eight already pass today for reasons unrelated to decision 1 (they pin
invariants the GREEN implementation must preserve, not ones it must newly
establish); assertions 3, 4, 5, 6 are the discriminating ones, matching the
dispatch's "Red: today the hint offers resume."

## Substring choice and rationale for 3, 4, 5

- **3 — `no release is recorded at`**: taken verbatim from the dispatch's own
  suggested phrase. It states the fact decision 1 is grounded on (the origin
  probe already ran and found nothing at either version) without committing to a
  full sentence — the GREEN implementer can write "no release is recorded at
  either 0.1.0 or 1.2.3" or reorder the clause and still satisfy this.
- **4 — `correct the marketplace entry`**: names the specific remedy decision 1
  settles on (point at the entry, not the manifest, as the default fix —
  `bump_marketplace` would overwrite the entry with the manifest version on a
  successful first release anyway, so the entry is the "wrong" one). Checked
  this string does not appear anywhere else in `release.sh` today
  (`grep -n "marketplace entry"` — the only hits are the file header comment and
  `bump_marketplace`'s own refused-commit hint, which never fires on this path
  since preflight dies first), so it cannot pass by accident once the new hint
  exists elsewhere in the file.
- **5 — `set .version in .claude-plugin/plugin.json`**: reused byte-for-byte
  from the existing first-release bump-refusal hint (`release.sh:336`), which
  already states "to publish some other version instead, set .version in %s"
  with `%s` = `.claude-plugin/plugin.json`. Decision 1's hint needs the
  identical remedy ("if 1.2.3 was the intended version, edit the manifest
  instead"), so reusing the phrase is the smaller diff and keeps one wording for
  "the manifest is the maintainer's edit" instead of two. Confirmed this exact
  string appears nowhere else in `release.sh` outside that one `bump_arg`-gated
  branch, and that branch is unreachable on a no-argument run, so it is
  genuinely absent from this scenario's output today.

## BRE note

Per the standing convention (92 existing assertions use unescaped version
strings against `assert_contains`'s BRE grep), the two version-string assertions
(`0.1.0`, `1.2.3`) are left unescaped. Checked directly: neither string is a
substring of the other under `.`-as-wildcard (`0.1.0` needs a 4th character `0`
where `1.2.3` has `2`, and vice versa), and no other digit produced by this
run's output (`0.1.0`, `1.2.3`) can cross-match the other by one wildcard
substitution — confirmed by inspection, no other version-shaped string appears
in this scenario's actual output besides the two intended ones.

## Amended by the test review

The test review (`item-1-2-s6-test-review.md`) changed this scenario, so the
code and counts above describe the RED phase rather than the file as it now
stands. What moved:

- The scenario was relocated from the end of the suite to directly after the
  `entry-agrees-no-tags-bump` scenario, joining the first-release-with-entry
  group, and a new green characterization guard
  (`version drift on a plugin that HAS been released still offers resume`)
  follows it. Nothing in the suite previously caught an implementation that
  replaced the resume hint unconditionally — proven by mutation.
- Assertions 2a/2b now run against the output with `check-version.sh`'s own
  lines stripped, so they test the hint rather than passing on
  `check-version.sh`'s drift line. Both are red as a result: the discriminating
  count is 6, not 4, and the suite now reports `6 failure(s)`.
- Four state assertions were added (marketplace entry unchanged, manifest
  unchanged, no commit, origin `main` unadvanced). All pass today.

## State on exit

- `toolkit/release.sh` — **untouched**. `git status --short toolkit/release.sh`
  is empty.
- `tests/release-test.sh` — the only file modified: one new scenario appended at
  the end, no existing scenario touched.
- Nothing committed.
- Environment: `$TMPDIR` was unset in the dispatch shell, confirmed before
  running; used `/tmp/claude-1000/scratch` explicitly. Nothing left in the repo
  root.
