# Item 1.3, slice 1 — RED

Scope: `tests/release-test.sh` only. `toolkit/release.sh` untouched, nothing
committed.

## Scenario code

Inserted between the `no-origin` scenario (ends `:851` pre-edit) and
`non-semver v tags are not releases` — the outline's own ordering puts "Diverged
push route" between "Origin absent" and "Only non-semver v tags", and a prior
slice had to be relocated for landing out of that order.

```sh
echo "=== release: common_preflight refuses a diverged push route ==="
# `git config --get` exits 1 when the key is unset; a GREEN implementation
# must read that status and treat it as "not diverged", not fail closed on
# every unset key — none of the three keys below is set in a healthy fixture,
# so a naive implementation that failed on ANY non-zero status would also
# break the happy-path scenario above, not just this one. Residual bound:
# this loop does not by itself tell "absorbs status 1 only" from "absorbs
# every non-zero status" — a GREEN that swallows a real git-config error
# (status >=2, e.g. a corrupt config file) would still pass every assertion
# here; see the report for what would pin that distinction.
#
# `other`'s path carries a space deliberately: `pushurl` stores a filesystem
# path as its value, and the value is asserted verbatim against `$out` —
# `assert_contains`'s BRE read of that value must not choke on the space.
for setting in pushurl pushRemote pushDefault; do
    new_sandbox "1.2.3"
    other="$sandbox/other repo.git"
    git init -q --bare -b main "$other"
    case "$setting" in
        pushurl)
            git -C "$plugin" config remote.origin.pushurl "$other"
            key="remote.origin.pushurl"
            value="$other"
            ;;
        pushRemote)
            # pushRemote and pushDefault take a remote *name*, not a path —
            # the redirect target must exist as a named remote first.
            git -C "$plugin" remote add other "$other"
            git -C "$plugin" config branch.main.pushRemote other
            key="branch.main.pushRemote"
            value="other"
            ;;
        pushDefault)
            git -C "$plugin" remote add other "$other"
            git -C "$plugin" config remote.pushDefault other
            key="remote.pushDefault"
            value="other"
            ;;
    esac
    run_in "$plugin" bash plugin-dev/release.sh patch
    assert_eq "$rc" "1" "diverged-push-route ($setting) exit code"
    assert_contains "$out" "$key" "diverged-push-route ($setting) names the setting"
    assert_contains "$out" "$value" "diverged-push-route ($setting) names the value"
    assert_eq "$(git -C "$plugin" rev-parse --verify -q refs/tags/v1.2.4 >/dev/null && echo yes || echo no)" \
        "no" "diverged-push-route ($setting) created no v1.2.4 tag"
    assert_eq "$(cat "$GH_LOG")" "" "diverged-push-route ($setting) must not call gh"
    assert_eq "$(market_version)" "1.2.3" "diverged-push-route ($setting) marketplace untouched"
done
```

Fresh `new_sandbox "1.2.3"` per setting, per the runbook. `pushurl` sets the
config directly to the second bare repo's path; `pushRemote`/`pushDefault` first
`git remote add other <path>`, then point the setting at the name `other`.

## Verbatim RED output, all three settings

Full run: `bash tests/release-test.sh`, exit 1, 15 failures total (all in this
block — everything before and after it is green, confirming this is an addition,
not a regression against the existing 44-ish scenarios).

```
=== release: common_preflight refuses a diverged push route ===
FAIL: diverged-push-route (pushurl) exit code: expected '1', got '0'
FAIL: diverged-push-route (pushurl) names the setting: output did not contain 'remote.origin.pushurl'
  --- output ---
check-version: in sync (1.2.3)
[main 105a5b7] release: 1.2.4
 1 file changed, 1 insertion(+), 1 deletion(-)
manifest + tag: v1.2.4 created locally
To /tmp/claude-1000/tmp.ruEKaGkaDK/other repo.git
 * [new branch]      main -> main
branch main: pushed
To /tmp/claude-1000/tmp.ruEKaGkaDK/other repo.git
 * [new tag]         v1.2.4 -> v1.2.4
github tag v1.2.4: pushed
github release v1.2.4: created
[main 7d8bb56] release: fixture 1.2.4
 1 file changed, 1 insertion(+), 1 deletion(-)
To /tmp/claude-1000/tmp.ruEKaGkaDK/marketplace-origin.git
   9a731f5..7d8bb56  main -> main
marketplace: bumped to 1.2.4
Release v1.2.4 complete
  --------------
FAIL: diverged-push-route (pushurl) created no v1.2.4 tag: expected 'no', got 'yes'
FAIL: diverged-push-route (pushurl) must not call gh: expected '', got 'release view v1.2.4
release create v1.2.4 --title Release 1.2.4 --generate-notes'
FAIL: diverged-push-route (pushurl) marketplace untouched: expected '1.2.3', got '1.2.4'
FAIL: diverged-push-route (pushRemote) exit code: expected '1', got '0'
FAIL: diverged-push-route (pushRemote) names the setting: output did not contain 'branch.main.pushRemote'
  --- output ---
check-version: in sync (1.2.3)
[main f529389] release: 1.2.4
 1 file changed, 1 insertion(+), 1 deletion(-)
manifest + tag: v1.2.4 created locally
To /tmp/claude-1000/tmp.dTr1m9ejAv/other repo.git
 * [new branch]      main -> main
branch main: pushed
To /tmp/claude-1000/tmp.dTr1m9ejAv/plugin-origin.git
 * [new tag]         v1.2.4 -> v1.2.4
github tag v1.2.4: pushed
github release v1.2.4: created
[main 96ad5f6] release: fixture 1.2.4
 1 file changed, 1 insertion(+), 1 deletion(-)
To /tmp/claude-1000/tmp.dTr1m9ejAv/marketplace-origin.git
   2619185..96ad5f6  main -> main
marketplace: bumped to 1.2.4
Release v1.2.4 complete
  --------------
FAIL: diverged-push-route (pushRemote) created no v1.2.4 tag: expected 'no', got 'yes'
FAIL: diverged-push-route (pushRemote) must not call gh: expected '', got 'release view v1.2.4
release create v1.2.4 --title Release 1.2.4 --generate-notes'
FAIL: diverged-push-route (pushRemote) marketplace untouched: expected '1.2.3', got '1.2.4'
FAIL: diverged-push-route (pushDefault) exit code: expected '1', got '0'
FAIL: diverged-push-route (pushDefault) names the setting: output did not contain 'remote.pushDefault'
  --- output ---
check-version: in sync (1.2.3)
[main d7c460c] release: 1.2.4
 1 file changed, 1 insertion(+), 1 deletion(-)
manifest + tag: v1.2.4 created locally
To /tmp/claude-1000/tmp.PWbr31SCMA/other repo.git
 * [new branch]      main -> main
branch main: pushed
To /tmp/claude-1000/tmp.PWbr31SCMA/plugin-origin.git
 * [new tag]         v1.2.4 -> v1.2.4
github tag v1.2.4: pushed
github release v1.2.4: created
[main 5e212c6] release: fixture 1.2.4
 1 file changed, 1 insertion(+), 1 deletion(-)
To /tmp/claude-1000/tmp.PWbr31SCMA/marketplace-origin.git
   93a94eb..5e212c6  main -> main
marketplace: bumped to 1.2.4
Release v1.2.4 complete
  --------------
FAIL: diverged-push-route (pushDefault) created no v1.2.4 tag: expected 'no', got 'yes'
FAIL: diverged-push-route (pushDefault) must not call gh: expected '', got 'release view v1.2.4
release create v1.2.4 --title Release 1.2.4 --generate-notes'
FAIL: diverged-push-route (pushDefault) marketplace untouched: expected '1.2.3', got '1.2.4'
```

15 failures, 5 per setting (of 6 assertions each) — see "assertions already
passing" below for the 6th.

The output also shows the fixture is doing what it claims: for `pushRemote` and
`pushDefault`, the branch push (a bare `git push`, no explicit remote on the
command line) lands on `other repo.git`, while the tag push (which `release.sh`
issues as `git push origin <tag>`, an explicit remote) still lands on
`plugin-origin.git` — `pushRemote`/`pushDefault` only redirect an unqualified
push. For `pushurl`, both pushes redirect, since that setting overrides the URL
used for `origin` itself. This is real, observed divergence — the bug the item
describes is reachable today, not theoretical.

## Assertions already passing today — and what they guard

Five of six assertions per setting are genuinely red, as shown above. The
**"names the value" assertion is not independently red today**: `$out` already
contains the redirect target (`.../other repo.git`, or the substring `other`
inside that same path) because `release.sh`'s own `git push` prints `To <url>` —
an artifact of the side effect happening at all, not of any refusal message. So
this check currently passes by accident, for a reason that will stop being true
once GREEN lands: `common_preflight` must refuse **before any side effect**, so
post-GREEN there is no push and thus no `To ...` line — the only way `$out` can
contain the value at that point is if the refusal message itself names it, which
is exactly what the assertion is meant to pin. I did not weaken or drop it; it
is correct to keep, and it will start doing real work the moment side effects
stop leaking the value into the transcript for free.

The exit-code, no-v1.2.4-tag, gh-empty, and marketplace-untouched assertions are
cleanly red for the reason the item states: none of the three settings is
consulted today, so `release.sh` runs straight through to a real publish.

## Spaced-path result

`other="$sandbox/other repo.git"` was used for all three settings (one fixture
path, reused, rather than singling one out — it costs nothing and covers all
three forms). The `pushurl` case's `value` is that full path, asserted verbatim;
the RED output above shows `$out` containing
`/tmp/claude-1000/tmp.ruEKaGkaDK/other repo.git` (space intact) and the
assertion against it behaved as expected (passed, for the accidental reason
above — not a whitespace failure). No splitting occurred anywhere in the fixture
setup (`git init --bare`, `git config`, `git remote add` all took the quoted
`"$other"` correctly) or in the assertion read (`assert_contains` takes the
whole `$2` as one `grep` argument, not word-split).

## BRE judgement

`assert_contains` calls `grep -q --` with no `-F`, so the needle is read as a
POSIX BRE. The `pushurl` value is a `mktemp -d` path with a high-entropy random
suffix (e.g. `tmp.ruEKaGkaDK`) plus the literal `/other repo.git` — none of
`* [ ] ^ $ \` appear in it, so no BRE metacharacter is present to misinterpret.
The `.` characters in `pushurl` and `.git` are BRE "any character" wildcards,
not literals, but a wildcard match is *weaker* than what's needed here, not
spurious: in a substring-containment check (`grep -q`, no anchors) a wildcard
can only make the match succeed on more strings, never produce a false negative,
and the string being searched is `$out` itself (which contains the exact path
verbatim) — there is no third string in play for a `.` to accidentally match
instead. The other two values (`branch.main.pushRemote`, `remote.pushDefault`,
and the literal `other`) are plain identifiers with the same `.`-as-wildcard
property and no other metacharacters. I left all of them unescaped, matching the
suite's existing convention across the other ~90 assertions — this is not the
case where it breaks.

## State on exit

- `toolkit/release.sh` — untouched (`git diff --stat` shows only
  `tests/release-test.sh`).
- Nothing committed; working tree has exactly one modified file.
- `bash -n tests/release-test.sh` and `shellcheck tests/release-test.sh` both
  clean.
- Scenario placed between the existing `no-origin` and `non-semver v tags`
  scenarios, per the outline's ordering.
- Slice 2 (`--resume`) not written — out of scope for this dispatch.

## Guidance for the GREEN implementer

- Absorb status 1 only from each `git config --get`, same discipline as
  `semver_tags`:
  `value=$(git config --get "$key") || { [ "$?" -eq 1 ] || die ...; }` — and
  recall the `item-1-2-s6-code-review.md` §2 finding: `set -e` stays active for
  commands *inside* a `cmd || { … }` group, so a command inside that brace group
  that can itself fail (not just the exit-status check) needs its own guard, not
  an assumption that the `||` suspended errexit for the block.
- A robust read would be `git config -z --get-regexp` to avoid any
  whitespace-splitting risk on a multi-line or newline-containing value; this
  slice's fixtures don't need it (a single `--get` per key is exact and the
  space-only case is covered), but it's the safer form if the GREEN
  implementation ends up reading multiple keys at once.
- The refusal must land in `common_preflight`, before `tree_is_clean`/etc., and
  in both `release` and `resume` modes (slice 2, not written here).
