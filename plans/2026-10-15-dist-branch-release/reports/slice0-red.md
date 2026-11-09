# Slice 0 red report

## Diff
```diff
diff --git a/tests/release-test.sh b/tests/release-test.sh
index 357697b..b2380a2 100644
--- a/tests/release-test.sh
+++ b/tests/release-test.sh
@@ -249,6 +249,9 @@ assert_eq "$(git -C "$plugin" ls-remote origin refs/tags/v1.2.4 | wc -l | tr -d
     "1" "tag pushed to origin"
 assert_contains "$(cat "$GH_LOG")" "release create v1.2.4" "gh release created"
 assert_eq "$(market_version)" "1.2.4" "marketplace bumped"
+assert_eq "$(jq -c '.plugins[] | select(.name=="fixture") | .source' \
+    "$marketplace/.claude-plugin/marketplace.json")" \
+    '{"source":"github","repo":"o/fixture"}' "existing entry source untouched by bump"
 assert_eq "$(git -C "$marketplace" log -1 --format=%s)" "release: fixture 1.2.4" "marketplace commit"

 echo "=== release: first publication creates the marketplace entry ==="
@@ -259,13 +262,16 @@ assert_contains "$out" "marketplace: entry created at 1.3.0" "first-publication
 entry="$(jq -c '.plugins[] | select(.name=="fixture")' \
     "$marketplace/.claude-plugin/marketplace.json")"
 assert_eq "$(printf '%s' "$entry" | jq -r .version)" "1.3.0" "created entry version"
-assert_eq "$(printf '%s' "$entry" | jq -r .source.source)" "github" "created entry source type"
 assert_eq "$(printf '%s' "$entry" | jq -r .license)" "MIT" "created entry license from manifest"
 assert_eq "$(printf '%s' "$entry" | jq -r .description)" "test fixture" "created entry description"
-# The repo slug is derived from origin, which is a local path in the fixture:
-# it must be a non-empty owner/repo pair, not the whole path.
-assert_eq "$(printf '%s' "$entry" | jq -r '.source.repo | split("/") | length')" \
-    "2" "created entry repo slug shape"
+# The source is a url source whose url is built from the owner/repo slug
+# derived from origin. Origin is a local path in the fixture, so the slug is
+# its last two components: the sandbox dir and "plugin-origin". The expected
+# value is spelled from that fixture fact, not derived with the script's sed.
+expected_source="$(jq -cn --arg u "https://github.com/$(basename "$sandbox")/plugin-origin.git" \
+    '{source: "url", url: $u}')"
+assert_eq "$(printf '%s' "$entry" | jq -c .source)" "$expected_source" \
+    "created entry source is a url source"

 echo "=== resume: completes a release whose push was rejected ==="
 new_sandbox "1.2.3"
```

## Failing assertion (verbatim)
```
FAIL: created entry source is a url source: expected '{"source":"url","url":"https://github.com/tmp.txbnUnKzvZ/plugin-origin.git"}', got '{"source":"github","repo":"tmp.txbnUnKzvZ/plugin-origin"}'
```

## Totals
Run against unchanged toolkit/release.sh: exit 1, "1 failure(s)" (the
created-entry pin, a failed assertion, no crash); all other assertions passed,
including the new happy-path source regression guard.

## Review

Verdict: APPROVE

1. Red re-run against unchanged toolkit/release.sh: `bash tests/release-test.sh`
   exits 1 with "1 failure(s)". The only line is
   ```
   FAIL: created entry source is a url source: expected '{"source":"url","url":"https://github.com/<tmp>/plugin-origin.git"}', got '{"source":"github","repo":"<tmp>/plugin-origin"}'
   ```
   It is a failed assertion, not a crash, and no other assertion failed.
2. The expected value is not tautological. It is built from the fixture
   (`basename "$sandbox"` plus the literal `plugin-origin`) with `jq -cn`, not
   from the script's sed. It compares the whole compact `.source` object, so a
   wrong key, extra key, missing `.git` or a `github` shape all fail.
3. The happy-path guard checks the existing entry's `.source` after the bump,
   against the `{"source":"github","repo":"o/fixture"}` fixture (line 139).
   Mutation in a scratch copy: the existing-entry jq in `bump_marketplace` also
   rewrote `.source`. The suite then failed
   `existing entry source untouched by bump` with got
   `{"source":"url","url":"x"}`. That mutation also tripped the "marketplace
   HEAD unmoved" assertion in entry-agrees-no-tags, so the guard discriminates.
4. Green by hand in a scratch copy in $TMPDIR: line 763 became
   ```
   source: { source: "url", url: ("https://github.com/" + $repo +
   ".git") }
   ```
   The full suite then had 0 FAIL and exited 0. The real repo's release.sh was
   not touched.
5. The contract is covered. The creation shape is pinned whole, and
   existing-entry non-modification is pinned. The slug derivation and
   `repository` fallback are unchanged and untouched by the tests, which matches
   the plan. One residual: the old "repo slug shape" check is subsumed by the
   full-url equality, so removing it loses nothing. No changes requested.
