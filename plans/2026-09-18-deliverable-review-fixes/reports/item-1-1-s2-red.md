# Item 1.1 / slice 2 — RED report

Mode: RED. Test written:
`pipefail-stripped release_tags failure publishes nothing`, appended to the
`=== the origin probes fail closed with pipefail stripped ===` harness in
`tests/release-test.sh`, immediately after slice 1's
`pipefail-stripped release_tags failure refuses` scenario, before the
`if (( failures > 0 ))` tally.

Baseline note: unlike slice 1, item 1.1's production Change already landed in
`toolkit/release.sh` (commits `b68cede`, `4d9bc80`), so this dispatch's red
evidence is the item's own mutation, not a fail-before-fix. No lasting change
was made to `toolkit/release.sh`: it was mutated in place, tested, and restored
byte-for-byte, verified with `git diff --quiet`.

## What the test does

- `new_sandbox "1.2.3"` then `make_virgin "1.2.3"` (the harness's own helper,
  already used by other first-release scenarios): strips the fixture down to no
  `v*` tag locally or on origin, manifest and marketplace entry both at `1.2.3`.
- Reuses slice 1's `git` wrapper idiom on `PATH` — fails only `git tag --list`,
  delegates every other call (`exec`s the real binary resolved via
  `command -v git` at fixture-build time).
- Copies `toolkit/release.sh` into the fixture with the `pipefail` line
  rewritten to `set -eu`, same as slice 1.
- Runs `release-nopipefail-tags.sh` with **no** bump argument (a first release
  refuses an explicit bump before reaching `bump_commit_tag`, which would refuse
  for a reason unrelated to this defect).
- Captures the plugin's local and the bare origin's tag sets
  (`git tag --list | sort`) before the run, and asserts each equals its "before"
  snapshot afterward — a full-set comparison, not a named refutation of one tag,
  since which tag the defect would create is itself under test. Also asserts
  `$(cat "$GH_LOG")` is empty.

### Why `make_virgin`, not slice 1's already-released fixture

Slice 1's fixture (`new_sandbox "1.2.3"` alone, real tags on origin) was tried
first and does **not** exercise the hazard this slice targets: with origin
holding a real `v1.2.3`, `origin_release_tags` (untouched by the stub — it uses
`git ls-remote`, not `git tag --list`) still finds it, so `release_preflight`'s
lost-tags branch fires and refuses either way, under both the current fixed code
and the mutation. The "publishes nothing" assertions passed spuriously against
the mutated tree on that fixture — a vacuous red, reported below for the record,
then replaced.

Reusing that spurious-red output would have been the wrong evidence, so the
fixture was changed to `make_virgin "1.2.3"` before proceeding to the committed
test text. With no tag anywhere, `origin_release_tags` legitimately returns
empty, `verifiably_unpublished=1`, and the mutated `release_tags`'s swallowed
`git tag --list` failure reaches `first_release=1` — exactly the branch the
item's mutation note names ("`bump_commit_tag` tags `HEAD` — publishing the
manifest version of a plugin whose release history it could not read").

## Baseline green run (current, fixed `toolkit/release.sh`, unmutated)

```
cd /Users/david/code/claude-plugin-dev && bash tests/release-test.sh
```

Tail:

```
=== the origin probes fail closed with pipefail stripped ===
=== pipefail-stripped release_tags failure refuses ===
=== pipefail-stripped release_tags failure publishes nothing ===

all release scenarios passed
```

(Also run once against the earlier, rejected fixture reusing slice 1's
already-released `new_sandbox "1.2.3"` state — that version also closed green,
but was replaced because it could not detect the mutation; see above.)

## Mutation applied

`toolkit/release.sh` was copied to `$TMPDIR/item-1-1-s2/release.sh.bak`, then
`release_tags`'s body was replaced with the pre-slice-1 pipe:

```diff
-    local listing
-    listing=$(git tag --list 'v*' --sort=-v:refname) || return 1
-    printf '%s\n' "$listing" | semver_tags
+    git tag --list 'v*' --sort=-v:refname | semver_tags
```

(Comments and every other line untouched.)

## Failing assertion output under the mutation (verbatim)

```
cd /Users/david/code/claude-plugin-dev && bash tests/release-test.sh
```

```
=== the origin probes fail closed with pipefail stripped ===
=== pipefail-stripped release_tags failure refuses ===
FAIL: pipefail-stripped release_tags failure refuses names release_preflight's die: output did not contain 'could not list this plugin's release tags'
  --- output ---
git: fatal: stub git failing tag --list
hint: origin already has release tags for this plugin — the newest is
      v1.2.3, missing from this clone. Run `git fetch --tags` to catch up,
      then run the same command again.
error: local release tags are missing — refusing to guess whether v1.2.3 was published
  --------------
FAIL: pipefail-stripped release_tags failure refuses did not take the lost-tags branch: output contained 'git fetch --tags'
  --- output ---
git: fatal: stub git failing tag --list
hint: origin already has release tags for this plugin — the newest is
      v1.2.3, missing from this clone. Run `git fetch --tags` to catch up,
      then run the same command again.
error: local release tags are missing — refusing to guess whether v1.2.3 was published
  --------------
=== pipefail-stripped release_tags failure publishes nothing ===
FAIL: pipefail-stripped release_tags failure publishes nothing local tag set unchanged: expected '', got 'v1.2.3'
FAIL: pipefail-stripped release_tags failure publishes nothing origin tag set unchanged: expected '', got 'v1.2.3'
FAIL: pipefail-stripped release_tags failure publishes nothing gh log empty: expected '', got 'release view v1.2.3
release create v1.2.3 --title Release 1.2.3 --generate-notes'

5 failure(s)
EXIT=1
```

(The first two `FAIL:` lines are slice 1's own test, unmodified by this dispatch
— they are already known to red under this mutation per `item-1-1-s1-red.md`,
and are shown here only because the same run prints them. Slice 2's own three
assertions are the last three `FAIL:` lines: all three are genuine value
mismatches — `expected ''` — not an `ImportError`, an `AttributeError`, or a
shell error. The mutated `release_tags` silently absorbed the stubbed
`git tag --list` failure, the virgin fixture's empty origin listing then read as
"genuinely never released," `first_release=1` fired, and the script tagged
`HEAD`, pushed the tag, and called `gh release create v1.2.3` — publishing on
unverified information, exactly the hazard the item's mutation note names.)

## Restore confirmation

```
cd /Users/david/code/claude-plugin-dev && cp "$TMPDIR/item-1-1-s2/release.sh.bak" toolkit/release.sh && git diff --quiet -- toolkit/release.sh && echo "RESTORED: git diff --quiet clean (exit 0)"
```

```
RESTORED: git diff --quiet clean (exit 0)
```

## Post-restore green run (closing line)

```
cd /Users/david/code/claude-plugin-dev && bash tests/release-test.sh
```

```
=== the origin probes fail closed with pipefail stripped ===
=== pipefail-stripped release_tags failure refuses ===
=== pipefail-stripped release_tags failure publishes nothing ===

all release scenarios passed
```

## Scope confirmation

- IN, touched: `tests/release-test.sh` — one new scenario block, slice 1's test
  left untouched.
- `toolkit/release.sh`: mutated in place for the red proof, then restored
  byte-for-byte (`git diff --quiet` exit 0, confirmed above). No lasting change.
- Nothing committed. The new test remains uncommitted in the tree, as required
  for a RED dispatch. `git status --short` shows only `tests/release-test.sh`
  modified beyond the pre-existing, dispatch-external entries
  (`.claude/handoff-*.md`, the `memory` gitlink, and the sandbox mask
  dotfiles/`.mcp.json`/`.idea`/`.vscode`/`.claude/{agents,commands,hooks,…}`),
  none of which this dispatch touched.
