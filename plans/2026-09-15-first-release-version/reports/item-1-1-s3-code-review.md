# Item 1.1 slice 3 — code review

Reviewed commit `3fd4d648dd7da0af4308eb12f22772baf69cc848` and, as the item's
closing review, `toolkit/release.sh` whole against Item 1.1's own description.

**Verdict: the implementation is correct.** The empty-listing and exit-status
questions the protocol raised both resolve safely, and I established them by
running rather than reading. Three comment defects were found and fixed, one of
them a rationale the slice dropped that a live test still guards. One test gap
was found by mutation; its fix lands in `tests/release-test.sh`, which is out of
scope here, so it is flagged rather than performed.

## 1. Established by running

### The empty-listing case

`printf '%s\n' ""` emits a single empty line, not zero bytes.
`sed -n '1s/^v//p'` applies `s/^v//` to that line, the substitution fails to
match, and the `p` flag only fires on a *successful* substitution — so nothing
is printed and `latest_tag` becomes the empty string:

```
$ printf '%s\n' "" | sed -n '1s/^v//p' | od -c
0000000
```

So the empty case is benign rather than merely unreached. It is also unreached:
`release_preflight` returns from the `[ -z "$release_tag_list" ]` branch
(`toolkit/release.sh:252-269` at the reviewed commit) before `latest_tag` is
built, so the only way to the `latest_tag` assignment is a non-empty listing.
Both halves hold, and neither leans on the other.

### Exit status under `set -euo pipefail`

```
$ bash -c 'set -euo pipefail; rl=""; lt=$(printf "%s\n" "$rl" | sed -n "1s/^v//p"); echo "status=$? latest_tag=[$lt]"'
status=0 latest_tag=[]
```

`printf` of an in-memory string cannot fail, and `sed -n` with no match exits 0,
so the command substitution is status 0 on every input including the empty one.
Nothing can kill the script at that assignment, and no status is discarded,
because there is no second `git` call to lose one.

This is the point on which the chosen implementation is strictly better than the
`latest_tag=$(release_tags | sed -n '1s/^v//p')` form the interface contract
sketched. Under `pipefail` that pipeline's status is the rightmost non-zero one,
so a failing `release_tags` *would* propagate — but into a bare command
substitution assignment, where errexit kills the script with no message at all,
having printed only git's own stderr. Reusing the already-captured
`release_tag_list` keeps the one
`|| die "could not list this plugin's release tags — nothing was done"` as the
single enforcement point for the listing's status, which is what the slice-2
code review's discipline asks for.

## 2. Mutation probe

Baseline: `bash tests/release-test.sh` green at `HEAD`.

Mutation, chosen to be outside the four the test review probed — none of those
touched *which line* of the listing is taken, only whether the listing is
filtered and how it is sorted:

```sh
latest_tag=$(printf '%s\n' "$release_tag_list" | sed -n '$s/^v//p')
```

That is `1s` → `$s`: take the **oldest** release tag instead of the newest. It
is a plausible slip for exactly this change, since the whole point of the slice
is that the reused listing carries an order and the caller must take one end of
it.

**The suite passed in full under it.** No fixture in `tests/release-test.sh`
holds more than one semver tag — `grep -n 'tag ' tests/release-test.sh` shows
`v1.2.3` created once in `new_sandbox` (`:119`) and every other tag in a fixture
being `vnext`, `v1.2`, `nightly-2026` or a tag on the origin bare repo — so
first line and last line of `release_tag_list` are the same line everywhere, and
the `sed` address is unpinned.

This is adjacent to, but not the same as, the gap the test review recorded in
its §2. That one was about the **sort** (`--sort=-v:refname`) and was deferred
to Item 1.2's "origin newest ≠ lexicographic first" scenario. Item 1.2's
scenario exercises `origin_release_tags`, the *remote* listing, and will not pin
the local `sed` address at all: a `latest_tag` that took the oldest local semver
tag would still pass it. So the deferral does not close this.

**Flagged, not fixed** — `tests/release-test.sh` is out of scope for this
review. The cheap close is to give one existing local-tag scenario a second
semver tag, older than the fixture's `v1.2.3` (e.g.
`git -C "$plugin" tag v1.0.0` in the "non-semver v tag above the release tag
does not read as the latest" fixture) and leave the assertions as they are:
under `$s` the manifest would then be compared against `1.0.0` and the run would
refuse instead of publishing `v1.2.4`. It costs one line and no new scenario.

The mutation was applied in place from a backup and reverted with
`git checkout -- toolkit/release.sh`; `git diff --stat -- toolkit/release.sh`
was empty before the fixes below were written.

## 3. Fixes applied

All three are in `toolkit/release.sh` and none changes behaviour.

### 3.1 The dropped `git describe` argument, restored at the listing

This is the real finding. The comment slice 3 replaced carried two reasons for
`git tag --list` over `git describe`:

> describe returns the nearest tag of ANY name, distance-ordered rather than
> version-ordered, so any unrelated tag on a later commit reads as the last
> release

and, by reference to the block above it, that describe only sees tags reachable
from HEAD. The new comment drops both. The reachability half survived in
`release_preflight`'s first-release block, but the distance-ordering half — the
one specific to `latest_tag` — was left stated nowhere in the script, while
`tests/release-test.sh`'s "a non-v tag nearer than the release tag does not read
as the latest release" (`:810-817`) still guards exactly that behaviour. A live
test with its argument deleted from the code is how a future reader reintroduces
`git describe` here.

Both halves now sit on `release_tags`, which since slice 2 is the single listing
serving both callers, so neither call site has to restate them:

```sh
release_tags() {
    # Local semver release tags, newest first — the order is part of the
    # contract, since a caller naming a release takes the first line. Fixed
    # here rather than at each call site so no caller can forget it.
    #
    # `git tag --list` and not `git describe`, for both callers. describe only
    # sees tags reachable from HEAD, so a release tagged on a since-abandoned
    # branch would read as no tags at all; and it returns the NEAREST tag of
    # ANY name, distance-ordered rather than version-ordered, so an unrelated
    # tag on a later commit would read as the last release.
    git tag --list 'v*' --sort=-v:refname | semver_tags
}
```

The now-duplicated three lines were removed from `release_preflight`'s
first-release comment block. Net: the argument is stated once, at the function
that does the listing, instead of once-and-a-half at two call sites.

### 3.2 The `sed -n '1s…p'` rationale names the form it replaces

The inherited wording — "takes the newest line without exiting early, which
under pipefail would surface as a SIGPIPE" — named no alternative, so "exiting
early" read as a property of `sed` rather than the reason `head -1` was
rejected. It also no longer scanned: with `printf` of a short in-memory string
as the producer there is no long pipeline to break, and the sentence appeared to
be describing a hazard in the code as written. Now it names `head -1` as the
rejected form, which is what the argument is actually about.

### 3.3 The always-true `-n` test, documented rather than removed

`[ -n "$latest_tag" ]` (`:281` at the reviewed commit) is now provably true
whenever it is evaluated: the listing is non-empty (the branch above returned),
its first line matched `^v[0-9]+\.[0-9]+\.[0-9]+$`, so `1s/^v//` succeeds and
prints a non-empty line. Before this slice the test was live, because the
unfiltered listing could contain lines that `s/^v//` would still strip — it is
this slice that killed it.

**Kept, and said so in the comment** rather than deleted. Deleting it saves one
string test on a refusal path and buys nothing, while the invariant that makes
it safe to delete is stated four lines away and could move; a reader who cannot
answer "when is this empty?" is the actual cost, and a sentence answers it. The
comment now ends: "The listing is non-empty here (the branch above returned),
and its first line matched the semver anchor, so latest_tag is always set; the
-n test below is belt and braces."

Not a finding against the slice — flagged here because it is a consequence of it
that a later reader would otherwise have to re-derive.

## 4. Item 1.1 as a whole

Diffed `2df8113..HEAD -- toolkit/release.sh` — the three slices plus their two
code-review commits — against the item's description. Line numbers below are
from the file as it stands after §3's fixes. Every change the item lists is
present:

| item's clause | state |
| --- | --- |
| `semver_tags` filter added | `:206-215`, anchored `^v[0-9]+\.[0-9]+\.[0-9]+$` |
| `release_tags` listing added | `:217-228`, `--sort=-v:refname` into the filter |
| two-part predicate at `:225` replaced | now `[ -z "$release_tag_list" ]` |
| `latest_tag` routed through the filter | reuses `release_tag_list` |
| `marketplace_entry_exists` conjunct dropped | gone from the predicate |
| the comment arguing it is load-bearing dropped | six lines removed, not struck |
| header comment `:11-14` restated | `:11-16`, states the predicate |
| commit instruction added to the bump hint | "to it and commit that edit" |

Nothing the item says stays is gone:

- `marketplace_entry_exists` is still set by `common_preflight` (`:180-186`) and
  still read by `bump_marketplace` to choose create-vs-bump (`:418`) and to word
  its two notes (`:490`, `:518`). Its only lost reader is the detection
  predicate, which is the point of the item.
- `bump_commit_tag`'s initial-release branch (`:328-336`) is byte-identical to
  its pre-item form: tag `HEAD`, no commit, `acted=1`, the "manifest already at
  $V" note.
- `check-version.sh` still runs before the bump refusal (`:234-238`), so
  decision 1's hint path is intact.

Interfaces match the item's declaration:

- `semver_tags()` — stdin to stdout, keeps `^v[0-9]+\.[0-9]+\.[0-9]+$`, absorbs
  exactly grep's status 1 (`|| [ "$?" -eq 1 ]`), so a real grep error (2) still
  propagates. Verified by reading; the anchor is pinned by slice 2's scenario.
- `release_tags()` — no arguments,
  `git tag --list 'v*' --sort=-v:refname | semver_tags`. Under `pipefail` a
  failing `git tag` propagates even though the filter absorbs its own no-match,
  because `pipefail` takes the rightmost non-zero status and the filter's is 0.
- Globals: `first_release` initialised 0 at `:44`, set to 1 only in the
  detection branch; `V` and `tag` set in both branches;
  `local manifest_version latest_tag release_tag_list` correctly does *not*
  localise `V` or `tag`, which `bump_commit_tag` and the top-level flow read.

FR-1, FR-2 and FR-3 are each satisfied by code reachable from
`release_preflight`: the manifest version is published verbatim
(`V= "$manifest_version"`, no bump), detection is by semver tag alone, and the
bump refusal names both the version it would publish and the maintainer's edit —
including, since slice 2's review, the commit that edit needs.

## 5. Discipline checks from the runbook's standing constraints

- **A no-match `grep` exits 1.** One filter, `semver_tags`, absorbs status 1 and
  only status 1, with the reason in its own comment. No other `grep` in the
  script sits under a capture.
- **A listing that can fail must have its status read.**
  `grep -n 'release_tags' toolkit/release.sh` gives the definition and exactly
  one call site, `release_tag_list=$(release_tags) || die …`. Slice 3 removed
  the second `git tag` listing rather than adding one, so the discipline now has
  one enforcement point instead of two. No `[ -z "$(…)" ]` form remains anywhere
  in the file.
- **`git ls-remote` status.** The two uses (`:362`, `:390`) are still bare
  substitutions, so under errexit they die with git's own stderr. Pre-existing,
  untouched by this item, and Item 1.2's subject — not flagged.
- **Whitespace safety.** `printf '%s\n' "$release_tag_list"` is quoted; a git
  refname cannot contain a space, and cannot contain `*`, `?` or `[` either, so
  neither word-splitting nor globbing has anything to act on even if the quotes
  were lost. `report_dirty`'s `-z`/`read -r -d ''` loop is unchanged. No new
  split-on-whitespace was introduced.
- **Clean tree, green gate.** Below.

## 6. Reviewed and not changed

- **The header comment's "no tag matching … exists yet"** will need "and origin
  has none either" once Item 1.2's lost-tags probe lands. It is accurate for the
  code as it stands; amending it now would describe behaviour that does not
  exist. Item 1.2's business.
- **`common_preflight`'s writability comment** (slice 1) and the first-release
  marketplace-writability question it records — a recorded open item, out of
  scope.
- **File length.** `toolkit/release.sh` is 543 lines after the fixes, over the
  400-line guideline; recorded open item, deferred past Phase 1. The natural
  seam, unchanged by this item, is the tag-listing helpers (`semver_tags`,
  `release_tags`, and Item 1.2's `origin_release_tags`) — but they cannot move
  to a sourced file without adding a shipped path, which the outline already
  weighed and rejected for `version-guard.sh`'s copy of the same filter. Noting
  the seam, not splitting.
- **`tests/release-test.sh`** — out of scope; §2's gap is the one flag against
  it.

## 7. State on exit

- `toolkit/release.sh` — modified, comments only, no behaviour change. It is the
  only file changed besides this report.
- `bash -n toolkit/release.sh` — clean.
- `shellcheck toolkit/release.sh` — clean.
- `bash tests/release-test.sh` — all release scenarios passed.
- `just precommit` — green: shellcheck and `bash -n` over the shell scripts,
  `_import-check`'s three stub shapes, `format-docs`, `tests/hook-test.sh`,
  `tests/release-test.sh`, `tests/update-plugin-dev-test.sh`,
  `tests/dist-tree-test.sh`, `tests/docs-test.sh`, `tests/doc-sync-test.sh`.
- The mutation was reverted before any fix was written, and no backup file
  remains.
- Not committed, per the dispatch.
