# Item 1.2 / slice 1 — RED report

Mode: RED. Wrote only the slice's test,
`=== resume hint names the tag already on origin ===`, into
`tests/release-test.sh`. No test file was edited beyond this one addition;
`toolkit/release.sh` carries no lasting change.

## Slice 1 is the control — no red is expected against unchanged code

Item 1.2's defect (N1) is a SIGPIPE-vs-`pipefail` race in `resume_preflight`'s
hint ladder: `printf '%s\n' "$origin_tag_list" | grep -qxF -- "$tag"` can take
SIGPIPE on `printf` when `grep` matches early and exits, and `set -o pipefail`
promotes that 141 over `grep`'s 0 — but only at a listing large enough that
`printf` has not finished writing before `grep -qxF` exits on its early match.
At a handful of synthetic tags, as slice 1 uses, `printf` always finishes first,
so the ladder's branch 1 fires correctly and the test is expected to pass
against today's `toolkit/release.sh`, by construction. It did. Slice 2, not this
dispatch, sizes the post-filter `$origin_tag_list` to >=1 MB and is where the
discrimination lives.

## The test as written

Added at the end of `tests/release-test.sh`, after the two pipefail-stripped
Item 1.1 scenarios:

```sh
echo "=== resume hint names the tag already on origin ==="
new_sandbox "1.2.3"
git -C "$plugin" tag -d v1.2.3 >/dev/null
git_wrapper_dir="$sandbox/git-wrapper"
mkdir -p "$git_wrapper_dir"
real_git="$(command -v git)"
cat > "$git_wrapper_dir/git" <<STUB
#!/bin/sh
if [ "\$1" = "ls-remote" ] && [ "\$2" = "--tags" ]; then
    printf '%040d\trefs/tags/v1.2.3\n' 0
    seq 2 6 | while IFS= read -r n; do
        printf '%040d\trefs/tags/v1.2.%s\n' "\$n" "\$n"
    done
    exit 0
fi
exec "$real_git" "\$@"
STUB
chmod +x "$git_wrapper_dir/git"
saved_path="$PATH"
export PATH="$git_wrapper_dir:$PATH"
run_in "$plugin" bash plugin-dev/release.sh --resume
export PATH="$saved_path"
assert_eq "$rc" "1" "resume hint names the tag already on origin exit code"
assert_contains "$out" "origin already has v1.2.3" \
    "resume hint names the tag already on origin"
assert_contains "$out" "git fetch --tags" \
    "resume hint names the tag already on origin remedy"
assert_not_contains "$out" "just release" \
    "resume hint names the tag already on origin must not advise a fresh release"
assert_eq "$(cat "$GH_LOG")" "" "resume hint names the tag already on origin must not call gh"
```

The fixture: a `git` wrapper on `PATH`, matched positionally on
`ls-remote`/`--tags` and delegating every other call to the real binary — the
same stub idiom `version-guard-test.sh`'s `guard_stub127_dir` and this file's
own pipefail-stripped `tag --list` scenarios already use. It replaces
`origin_release_tags`'s `git ls-remote --tags --sort=-v:refname origin` read
with six synthetic `<oid><TAB>refs/tags/vX.Y.Z` rows, one `seq`-backed loop, the
matching tag (`v1.2.3`) first — no real `git tag` calls, per the runbook's cost
warning. The local `v1.2.3` tag is deleted first
(`git -C "$plugin" tag -d v1.2.3`), which is what makes
`git rev-parse -q --verify "refs/tags/$tag"` fail in `resume_preflight` and
enters the ladder — the lost-tags refusal path the item's slice text requires as
part of the fixture.

## Run output (green)

```
$ cd /Users/david/code/claude-plugin-dev && bash tests/release-test.sh
...
=== the origin probes fail closed with pipefail stripped ===
=== pipefail-stripped release_tags failure refuses ===
=== pipefail-stripped release_tags failure publishes nothing ===
=== resume hint names the tag already on origin ===

all release scenarios passed
```

No `FAIL:` lines. All five assertions in the new scenario passed on the first
run, against unchanged `toolkit/release.sh`.

## Evidence the green is for the right reason

Proved by a temporary, byte-for-byte-reverted mutation to `toolkit/release.sh`
rather than by inspection alone.

1. Confirmed the tree was clean before mutating:

   ```
   $ git diff --quiet -- toolkit/release.sh && echo "clean before mutation"
   clean before mutation
   ```

2. Changed the ladder's membership test to search for a string that can never
   appear in the stub's output, so branch 1 cannot fire even though the fixture
   still reaches the ladder with a non-empty `$origin_tag_list`:

   ```diff
   -        if printf '%s\n' "$origin_tag_list" | grep -qxF -- "$tag"; then
   +        if printf '%s\n' "$origin_tag_list" | grep -qxF -- "TEMP-MUTATION-NO-MATCH-$tag"; then
   ```

3. Re-ran the suite. The new scenario failed exactly as expected — the ladder
   fell through to branch 2 ("origin has release tags, but none matching"),
   proving the fixture does reach the ladder (branch 1 would otherwise never
   have been live to break) and that the test does notice when branch 1 is not
   the one that fires:

   ```
   === resume hint names the tag already on origin ===
   FAIL: resume hint names the tag already on origin: output did not contain 'origin already has v1.2.3'
     --- output ---
   hint: origin has release tags, but none matching v1.2.3.
         run `git fetch --tags`, then run `just release <bump>`.
   error: no tag v1.2.3 for plugin.json version 1.2.3
     --------------
   FAIL: resume hint names the tag already on origin must not advise a fresh release: output contained 'just release'
     --- output ---
   hint: origin has release tags, but none matching v1.2.3.
         run `git fetch --tags`, then run `just release <bump>`.
   error: no tag v1.2.3 for plugin.json version 1.2.3
     --------------
   ```

   (The same mutation also broke three pre-existing branch-1 assertions —
   `no-tag resume hint names resume-release`,
   `origin-outranks-local resume hint names resume-release`, and
   `origin-newer-tag resume hint names resume-release` — independent
   corroboration that the mutated line is the one those scenarios, and this new
   one, all depend on.)

4. Reverted the mutation and confirmed the restore was exact:

   ```
   $ git diff --quiet -- toolkit/release.sh && echo "RESTORED: toolkit/release.sh byte-for-byte clean" || echo "DIRTY"
   RESTORED: toolkit/release.sh byte-for-byte clean
   ```

5. Re-ran the suite once more against the restored file — green again, closing
   line `all release scenarios passed` — and confirmed via
   `git status --porcelain -- toolkit/release.sh tests/release-test.sh` that
   only `tests/release-test.sh` is modified in the working tree:

   ```
    M tests/release-test.sh
   ```

## Explicit statement

Slice 1 is the control. It produced no red against unchanged code, by
construction — the SIGPIPE/`pipefail` hazard that Item 1.2 fixes only manifests
at a listing large enough that `printf` has not finished writing before
`grep -qxF` exits early, which a handful of synthetic tags never reaches. This
dispatch confirms the fixture is well-formed (reaches the ladder, exercises the
lost-tags refusal path) and that branch 1 is observably the branch that fires,
via the temporary-mutation proof above — not by manufacturing a red.

## Scope confirmation

- IN, touched: `tests/release-test.sh` — the single new scenario and its `git`
  stub, appended after the Item 1.1 pipefail-stripped scenarios.
- OUT, untouched (no lasting change): `toolkit/release.sh` (temporary mutation
  applied and reverted, confirmed via `git diff --quiet`); slice 2's >=1 MB
  test; `scripts/self-release.sh`; `tests/self-release-test.sh`;
  `tests/version-guard-test.sh`; `tests/update-plugin-dev-test.sh`; `docs/`;
  `CLAUDE.md`; `README.md`; `toolkit/README.md`; `justfile`.
- No commit was made — the uncommitted test stays in the tree, per RED mode.
