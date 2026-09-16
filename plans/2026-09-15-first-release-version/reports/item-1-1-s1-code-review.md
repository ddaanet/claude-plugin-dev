# Item 1.1 slice 1 — code review

Reviewed: `toolkit/release.sh` at `74c4733f0fd63aa2fde5978cae88ef8feee8346f`,
and the file as it now stands. Verdict: the implementation is correct and
matches the slice. One stale comment fixed. One accepted behavioural consequence
flagged, not changed. No refactoring seam worth naming yet.

## 1. The change itself

`toolkit/release.sh:218` is now `if [ -z "$(git tag --list 'v*')" ]; then` — the
`marketplace_entry_exists` conjunct is gone, and so is the comment arguing both
halves were load-bearing. Correct for FR-2's "the marketplace entry plays no
part" half, and correct as the narrowest change: no `semver_tags`, no
`release_tags`, `latest_tag` (`:243`) still filters inline, header comment
(`:11-14`) untouched. Those are slices 2 and 3 and their absence is not a
finding.

`marketplace_entry_exists` is still assigned in `common_preflight` (`:173`,
`:175`) and still read by `bump_marketplace` at `:376`, `:448` and `:476` to
choose between creating and bumping the entry. No dead variable, no dangling
reference. `bump_commit_tag`'s `first_release` branch (`:286-294`) is unchanged,
as scoped.

Grepped `toolkit/release.sh` for surviving references to the two-part predicate:
none. (`release.just:25` states rules 1/3/4 and never the predicate; that file
is Phase 3.)

### Shell constraints

Nothing in the diff adds a `grep`, an `ls-remote` or a pipeline, so the
no-match-exits-1 and exit-128 constraints have no new surface here. The
surviving predicate is a quoted command substitution inside `[ -z … ]`;
`git tag --list` with no match exits 0 with empty stdout, so `set -e` is not in
play, and the quoting means a tag name containing whitespace cannot split.
`shellcheck toolkit/release.sh` and `bash -n` are clean.

### The refusal sits before every side effect

FR-3 requires the bump refusal to leave nothing behind. `release_preflight` runs
from `:488`, after `common_preflight` and before `bump_commit_tag`, so the `die`
at `:228` precedes the manifest rewrite, the commit, the tag, both pushes, the
GitHub release and the marketplace bump. The only thing that has run by then
inside the plugin repo is `check-version.sh`, which writes nothing;
`check_marketplace_writable` creates and removes one temp file in the
marketplace directory. The suite's four added assertions on that scenario
(manifest, `HEAD`, origin `main`, `market_version`) pin it.

### The hint

`:221-227` now reads "set .version in `.claude-plugin/plugin.json` to it and
commit that edit, then re-run with no bump argument". Accurate:
`.claude-plugin/` is explicitly *not* exempt from the clean-tree check —
`clean_pathspecs` excludes only `.claude` and the gitlore submodule
(`:100-108`), and `report_dirty` says so outright at `:130-131`. So an
uncommitted manifest edit would be refused by `common_preflight` before this
hint's advice could take effect, and naming the commit is what makes the
instruction complete. It still offers no bypass and still says the edit is the
maintainer's.

## 2. Tests genuinely bind the change

Ran the suite as committed: all scenarios pass. Then reverted the predicate in
place to the old two-part form, re-ran, and restored from `HEAD`:

- **14 failures**, all in the two new scenarios, all assertion failures.
- `entry-agrees-no-tags`: the old predicate falls through to the ordinary bump
  path — manifest and marketplace to `1.2.4`, a commit made, no `v1.2.3` tag.
- `entry-agrees-no-tags-bump`: exit 0 instead of 1, `v1.2.4` tagged, `gh`
  called, manifest/origin/marketplace all advanced.
- The three `commit that edit` assertions stayed **green** under this mutation,
  which is correct — that assertion binds the hint, not the predicate, and the
  RED report already showed it failing against the pre-slice hint.

`git diff -- toolkit/release.sh` confirmed empty after restoring; the file was
then re-edited only for the fix in section 3.

## 3. Fix applied

**`common_preflight`'s comment at `:159-163` was made false by this slice.** It
read "A release always bumps to a version the marketplace doesn't have yet, so
the write is never a no-op". That premise no longer holds: a first release with
an existing marketplace entry has passed `check-version.sh`, which refuses
unless the entry equals the manifest (`check-version.sh:53-57`), and a first
release publishes the manifest version as-is — so `bump_marketplace`'s `cmp -s`
at `:401` short-circuits and nothing is written. That is exactly the state slice
1's first new scenario creates, and the scenario's "marketplace HEAD unmoved"
assertion depends on it.

Rewrote the comment to name the exception, why it arises, and why the check runs
anyway (which branch applies is only settled in `release_preflight`, which runs
after `common_preflight`). Comment-only; no behaviour change, no test touched.
`shellcheck`, `bash -n`, `tests/release-test.sh` and `just precommit` all re-run
green afterwards.

## 4. Flagged, not changed

**A first release with an agreeing entry is gated on a marketplace writability
it will not use.** `common_preflight:167` runs `check_marketplace_writable` for
every `release`, and that state needs no marketplace write. On a read-only or
sandboxed `MARKETPLACE_DIR` the release is refused with advice (`/add-dir`,
`dangerouslyDisableSandbox`) about a write that would never happen. Not a
correctness bug — it fails closed, and the recovery it names works — but it is a
false refusal that did not exist before this slice.

Deliberately not fixed: conditioning the check on `first_release` means moving
it after `release_preflight`, which is a behaviour change outside slice 1's IN
scope and would need its own scenario. The new comment records the state so the
next reader is not surprised by it. Worth a decision when Item 1.2 is already
editing `release_preflight`'s head, or worth leaving as an accepted bound.

**The lost-tags hole is open at this commit.** The comment removed here argued
that no-tags-alone misreads a repo whose tags were lost or never fetched as
never-released, and republishes a version already out there. That is true, and
at `HEAD` nothing covers it — Item 1.2's `origin_release_tags` probe is what
closes it. Expected and correct for the slice ordering (nothing ships until
Phase 4's self-release), recorded here only so the gap is not mistaken for an
oversight if the plan stalls between 1.1 and 1.2.

## 5. Refactoring

No seam worth naming. `toolkit/release.sh` is 514 lines after this review's
comment edit, over the 400-line soft cap, and the plan takes it to roughly 580.
The natural split line would be preflight-and-validation versus publish-steps —
`common_preflight`/`release_preflight`/`resume_preflight` on one side,
`bump_commit_tag` through `bump_marketplace` on the other — but the two halves
share `$V`, `$tag`, `$branch`, `$first_release`, `$marketplace_entry_exists`,
`$plugin_name`, `$marketplace_json` and `$marketplace_dir` as globals set in one
and read in the other, so a split means either a parameter-passing rewrite or a
sourced file with an implicit global contract. Each is a larger change than
anything Phase 1 contemplates, and the file is also a shipped artifact
(`tests/dist-tree-test.sh`, the CLAUDE.md Layout list), so a split adds a
shipped path. Leaving it whole and deciding after Phase 1 lands, as the dispatch
says, is the right call — most of the line count is argued comment rather than
logic, which is the class of overage the cap is explicitly soft about.

## 6. State on exit

- `toolkit/release.sh` — modified, comment only (section 3). Not committed.
- `plans/…/reports/item-1-1-s1-green.md` — modified in the working tree at the
  time this review started, a `rumdl` reflow of the committed text (line breaks
  only, no words). Left as found; not this review's change.
- `git diff --stat` shows no other file touched. The mutation probe was fully
  reverted.
- `bash tests/release-test.sh` — all scenarios pass.
- `just precommit` — green: `bash -n` and `shellcheck` on the shell scripts,
  `_import-check`, `tests/hook-test.sh`, `tests/release-test.sh`,
  `tests/update-plugin-dev-test.sh`, `tests/dist-tree-test.sh`,
  `tests/docs-test.sh`, `tests/doc-sync-test.sh`, `format-docs`.
