# Green: remove the .claude/ clean-tree exemption

## Diff summary

- toolkit/release-preflight.sh: clean_specs=(.) and clean_exempt=() in
  clean_pathspecs; the .claude/ paragraph of the comment is deleted and the
  remaining comment says one path is exempt (the gitlore memory submodule,
  unchanged logic). report_dirty prints the exempt header and list only when
  clean_exempt is non-empty (bash 3.2 safe); the .claude-plugin NOT-exempt note
  is removed; header comment reads 'any exemptions that did not save it'.
- scripts/self-release.sh: common_preflight runs git diff --quiet HEAD -- .
  ':(exclude)memory'; the comment drops the .claude/ and .claude-plugin
  sentences and keeps the memory reasoning. Comment near line 211 untouched.

Full diff:

```diff
diff --git a/scripts/self-release.sh b/scripts/self-release.sh
index f5ec520..afb5981 100755
--- a/scripts/self-release.sh
+++ b/scripts/self-release.sh
@@ -46,14 +46,12 @@ ls_remote_sha() {
 }

 common_preflight() {
-    # Same two exclusions toolkit/release.sh's tree_is_clean applies, for the
-    # same reason: `.claude/` holds the agent working environment and the task
-    # frames the handoff skills stage for the next commit, and the `memory`
-    # gitlink rests ahead of HEAD until gitlore's pre-commit hook folds it in.
-    # Written literally -- this repo is one known repo, not a consumer the
-    # script has to discover. The pathspec matches at the path separator, so
-    # `.claude-plugin` is not in scope (nor does one exist here).
-    git diff --quiet HEAD -- . ':(exclude).claude' ':(exclude)memory' \
+    # The `memory` gitlink is excluded, as toolkit/release.sh's tree_is_clean
+    # excludes the gitlore memory submodule: it rests ahead of HEAD until
+    # gitlore's pre-commit hook folds it in on the next commit. Written
+    # literally -- this repo is one known repo, not a consumer the script has
+    # to discover.
+    git diff --quiet HEAD -- . ':(exclude)memory' \
         || die "uncommitted changes"
     branch=$(git symbolic-ref -q --short HEAD) || die "not on a branch"
     if main_branch=$(git symbolic-ref -q --short refs/remotes/origin/HEAD); then
diff --git a/toolkit/release-preflight.sh b/toolkit/release-preflight.sh
index cbf0065..431748f 100644
--- a/toolkit/release-preflight.sh
+++ b/toolkit/release-preflight.sh
@@ -41,19 +41,10 @@ clean_pathspecs() {
     # memory — a consumer whose vendored plugin-dev/ predates one of them would
     # otherwise be told about an exclusion its own copy does not make.
     #
-    # Two paths are exempt, both because an agent session moves them by design
-    # between commits.
+    # One path is exempt, because an agent session moves it by design between
+    # commits.
     #
-    # `.claude/` is the repo's own agent working environment — settings, hooks,
-    # and the task frames the handoff and precompact skills stage for "whatever
-    # commit lands next". None of it is plugin content: a plugin ships
-    # .claude-plugin/ and the component directories beside it. Excluded whole
-    # rather than by filename, because the set of files written there is a
-    # function of which skills the maintainer runs, not of this script. The
-    # pathspec matches at the path separator, so .claude-plugin/ — where a dirty
-    # file must still stop a release — is untouched by it.
-    #
-    # The second is a gitlore-mounted memory submodule: its gitlink sits ahead
+    # It is a gitlore-mounted memory submodule: its gitlink sits ahead
     # of what HEAD records between commits by design — gitlore's own pre-commit
     # hook folds that in on the next commit, not this one.
     #
@@ -68,8 +59,8 @@ clean_pathspecs() {
     # and forgets to commit its moved gitlink should be refused, so
     # `--ignore-submodules=all` is not the shortcut it looks like.
     local dir="$1" mem=""
-    clean_specs=(. ':(exclude).claude')
-    clean_exempt=(".claude/ — agent working state (settings, hooks, staged handoff frames), none of it plugin content")
+    clean_specs=(.)
+    clean_exempt=()
     if [ -f "$dir/.gitmodules" ]; then
         mem=$(git config -f "$dir/.gitmodules" --get submodule.gitlore-memory.path) || mem=""
     fi
@@ -81,7 +72,7 @@ clean_pathspecs() {

 report_dirty() {
     # $1=repo root, $2=what to call it in the message. Prints what made it
-    # dirty, then the exemptions that did not save it. Callers add the
+    # dirty, then any exemptions that did not save it. Callers add the
     # site-specific consequence and next command, then die.
     #
     # -z / read -d '': a path containing a space is one path, and a word-split
@@ -94,12 +85,12 @@ report_dirty() {
     while IFS= read -r -d '' p; do
         printf '        %s\n' "$p" >&2
     done < <(git -C "$dir" diff -z --name-only HEAD -- "${clean_specs[@]}")
-    printf '      exempt from this check, and so not among the paths above:\n' >&2
-    for p in "${clean_exempt[@]}"; do
-        printf '        %s\n' "$p" >&2
-    done
-    printf '      .claude-plugin/ is NOT exempt — git pathspecs match at the path\n' >&2
-    printf '      separator, so a dirty manifest still refuses.\n' >&2
+    if [ "${#clean_exempt[@]}" -gt 0 ]; then
+        printf '      exempt from this check, and so not among the paths above:\n' >&2
+        for p in "${clean_exempt[@]}"; do
+            printf '        %s\n' "$p" >&2
+        done
+    fi
 }

 common_preflight() {
```

## Checks

- bash -n and shellcheck on both files: passed
- release-tree: exit 0, all release tree scenarios passed
- release-tags: exit 0, all release tags scenarios passed
- release-core: exit 0, all release core scenarios passed
- self-release-refusal: exit 0, self-release.sh: ok
- self-release-publish: exit 0, self-release.sh: ok

## precommit

```
=== the shim keeps the rest of PATH as spelled ===
=== a subdirectory launch resolves the root ===
=== a launch from plugin-dev/bin drops the empty entry ===
=== no next claude exits 127 ===

all dogfood launcher path scenarios passed
ok
PRECOMMIT_EXIT=0
```

precommit exit 0; 32 suite lines reported 'passed'.
