# Item 1.2 / slice 2 — RED report

Mode: RED. Added one test,
`=== resume hint names the tag already on origin at 1MB ===`, to
`tests/release-test.sh`, extending slice 1's committed `git`-stub idiom.
`toolkit/release.sh` carries no lasting change (a byte-for-byte `git status`
check below confirms).

## Evidence: the assertion failures (not errors)

```
$ cd /Users/david/code/claude-plugin-dev && time bash tests/release-test.sh
...
=== resume hint names the tag already on origin at 1MB ===
FAIL: resume hint names the tag already on origin at 1MB: output did not contain 'origin already has v1.2.3'
  --- output ---
hint: origin has release tags, but none matching v1.2.3.
      run `git fetch --tags`, then run `just release <bump>`.
error: no tag v1.2.3 for plugin.json version 1.2.3
  --------------
FAIL: resume hint names the tag already on origin at 1MB must not advise a fresh release: output contained 'just release'
  --- output ---
hint: origin has release tags, but none matching v1.2.3.
      run `git fetch --tags`, then run `just release <bump>`.
error: no tag v1.2.3 for plugin.json version 1.2.3
  --------------

2 failure(s)

real	0m59.857s
```

Overall suite exit status: 1 (from `bash tests/release-test.sh`). The two
failures are exactly the two discriminating assertions the runbook names ("same
two assertions as slice 1"): the ladder fell through to branch 2 ("origin has
release tags, but none matching") instead of firing branch 1 ("origin already
has v1.2.3" / `git fetch --tags`), so the output contains `just release` (branch
2's remedy) where the assertion demands it be absent. Both are failed
*assertions* on wrong values — not `ImportError`/`AttributeError`-shaped, not a
harness error. The other three assertions in the scenario (exit code `1`, the
`git fetch --tags` substring — present in both branches' text — and the empty
`gh` log) held, as expected: this is exactly N1, the SIGPIPE/pipefail hazard
promoting `printf`'s 141 over `grep`'s 0 in `resume_preflight`'s ladder, routing
to the wrong hint rather than crashing outright.

## Evidence: the post-filter guard passed (fixture clears the bound)

No `FAIL:` line for
`resume hint names the tag already on origin at 1MB fixture clears the post-filter 1MB bound (... bytes)`
in the run above — the guard assertion itself held. Measured directly,
independent of the suite run, using the same generator (matching tag first, then
`seq 4 100003` cycling one two-conversion `printf`, piped through
`cut -f2 | sed 's|^refs/tags/||' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$'` — the
same transform `origin_release_tags` and `semver_tags` apply):

```
$ { printf '%040d\trefs/tags/v1.2.3\n' 0; \
    printf '0000000000000000000000000000000000000000\trefs/tags/v1.2.%s\n' $(seq 4 100003); } \
    | cut -f2 | sed 's|^refs/tags/||' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | wc -c
1088917
```

`1088917 >= 1048576` (1 MB) — comparable to the runbook's own measurement
(100000 tags: 1088895 post-filter bytes), confirming the sizing math rather than
re-deriving a different bound. This is the *post-filter* size, not the stub's
raw row output, per the item's explicit requirement; the test computes it itself
(via the shared `$sandbox/origin-tag-rows.sh` generator, called both by the
`git` stub and by this guard) rather than assuming it from the row count, per
slice 1's test review recommendation.

## What was written

Appended to `tests/release-test.sh`, immediately after slice 1's committed
scenario and before the closing `if (( failures > 0 ))` block:

- A comment explaining the scenario's relation to slice 1 and the SIGPIPE
  mechanism, citing `resume_preflight`'s ladder by symbol and quoted fragment.
- `new_sandbox "1.2.3"`, `lose_tag "$plugin"`, and
  `git -C "$plugin" push -q origin :refs/tags/v1.2.3` — identical to slice 1's
  fixture, including origin's real tag deletion (the test-review fix), so the
  stub is the only possible source of an origin listing.
- `$sandbox/origin-tag-rows.sh` — the row generator, one file so the `git` stub
  and the size guard call the identical script and cannot drift apart. One
  `seq`-backed `printf`: the matching row first
  (`printf '%040d\trefs/tags/v1.2.3\n' 0`), then a single
  `printf '...v1.2.%s\n' $(seq 4 100003)` call that POSIX `printf` cycles over
  its one remaining conversion for each of the 100000 arguments — no real
  `git tag` calls, no shell loop.
- The `git` wrapper on `PATH`, same positional match (`ls-remote`/`--tags`) and
  `exec "$real_git" "$@"` delegation as slice 1, now just invoking the shared
  generator script instead of inlining rows.
- The post-filter size guard: runs the same generator through
  `cut -f2 | sed 's|^refs/tags/||' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$'` and
  asserts the byte count is `>= 1048576`, with the measured value embedded in
  the assertion label.
- The run (`bash plugin-dev/release.sh --resume`) and the same five assertions
  slice 1 uses, renamed to this scenario's label.

No stub parameterization of slice 1's own scenario was needed; slice 1's
scenario is untouched.

## Scope confirmation

```
$ git status --porcelain -- toolkit/release.sh tests/release-test.sh
 M tests/release-test.sh
```

- IN, touched: `tests/release-test.sh` — the single new scenario, appended after
  slice 1's.
- OUT, untouched: `toolkit/release.sh` (no edit, no mutation applied this
  dispatch); slice 1's committed scenario (read, not modified);
  `scripts/self-release.sh`; `tests/self-release-test.sh`;
  `tests/version-guard-test.sh`; `tests/update-plugin-dev-test.sh`; `docs/`;
  `CLAUDE.md`; `README.md`; `toolkit/README.md`; `justfile`.
- `bash -n tests/release-test.sh` and `shellcheck -x tests/release-test.sh`:
  both clean.
- No commit was made — the uncommitted test stays in the tree, per RED mode.

## Next step

GREEN mode restores the herestring fix
(`grep -qxF -- "$tag" <<<"$origin_tag_list"`) at the ladder site in
`resume_preflight`, which should turn both failing assertions green without
touching this test file.
