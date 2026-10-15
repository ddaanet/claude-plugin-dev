# Slice 0 green: marketplace url source

## git diff toolkit/release.sh

```diff
diff --git a/toolkit/release.sh b/toolkit/release.sh
index 54ce9cf..a5bc0fa 100755
--- a/toolkit/release.sh
+++ b/toolkit/release.sh
@@ -753,14 +753,16 @@ bump_marketplace() {
             '(.plugins[] | select(.name == $n) | .version) = $v' \
             "$marketplace_json" > "$mp_tmp"
     else
-        # Derive owner/repo from origin for the `github` source. Strip a trailing
-        # .git, then everything up to the host separator, leaving `owner/repo`
-        # for both git@host:owner/repo and https://host/owner/repo.
+        # The slug builds the `url` source's https clone url. A `github` source
+        # clones over SSH, which a user without a GitHub SSH key cannot use.
+        # Strip a trailing .git, then everything up to the host separator,
+        # leaving `owner/repo` for both git@host:owner/repo and
+        # https://host/owner/repo.
         repo_slug=$(git remote get-url origin | sed -E 's#\.git$##; s#^.*[:/]([^/]+/[^/]+)$#\1#')
         jq --arg v "$V" --arg repo "$repo_slug" --slurpfile m "$manifest" '
           .plugins += [{
             name: $m[0].name,
-            source: { source: "github", repo: $repo },
+            source: { source: "url", url: ("https://github.com/" + $repo + ".git") },
             description: ($m[0].description // ""),
             version: $v,
             author: ($m[0].author // { name: "" }),
```

## Gates

- `bash -n toolkit/release.sh`: clean
- `shellcheck toolkit/release.sh`: clean
- `bash tests/release-test.sh`: exit 0, 64 scenarios, 0 failures

## Suite final summary

```
=== resume hint names the tag already on origin at 1MB ===

all release scenarios passed
EXIT=0
```
