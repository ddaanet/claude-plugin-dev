# 2026-08-28 — The memory submodule's path is read, not assumed

Found auditing gitlore's vendored `plugin-dev/` copy, reported by
`brief-release-sh-two-nits-from-gitlore-audit.md` as its second nit and ranked
last of six in `brief-audit.md` — correctly, because it was latent. All nine
repositories mount the store at `memory`, so no consumer could reach it.

`common_preflight`'s clean-tree check excluded the literal path `memory` at both
its call sites, the plugin repo and `MARKETPLACE_DIR`. The exclusion itself is
right: a gitlore memory store's gitlink sits ahead of what HEAD records between
commits by design. But `memory` is only gitlore's default mount point — the path
is an argument to gitlore's `install.sh` — so a consumer who mounted the store
elsewhere would get `uncommitted changes` on every release, with nothing in the
message naming the submodule, the pathspec, or why the default matters.

Now a `tree_is_clean` helper reads the path from the repo's `.gitmodules`, keyed
on the submodule name `gitlore-memory`. Keyed on the name and not the url
because git absolutises a relative url on the way into `.git/config`, so a url
match is only reliable against `.gitmodules` anyway, and the name is the half
gitlore fixes while the user picks the path. A repo with no `.gitmodules`, or
none carrying that submodule, is checked with no pathspec — which is what the
literal pathspec meant there before.

The alternative weighed and rejected was `git diff --ignore-submodules=all`,
which drops the parse for a two-line diff. It exempts every submodule, so a
consumer vendoring a code submodule and forgetting to commit its moved gitlink
would release unwarned. That no consumer carries one today is what would keep
the regression invisible until one did. Recorded in design.md under "The
clean-tree check excludes gitlore's memory submodule, and only that", which is
also the first time the exclusion is documented anywhere but a code comment.

The test fixture now mounts with `--name gitlore-memory` rather than letting the
name default to the path, which is what gitlore actually does and what the new
lookup keys on. Three scenarios were added: the store at a non-default path in
the plugin repo and in the marketplace repo, both confirmed red against the
unfixed script with the exact `uncommitted changes` refusal from each call site;
and a resting submodule that is *not* the store, which must still refuse. That
third one was green before the change — it is the guard on the narrowness, not
evidence of the fix.

The non-default path in the first scenario contains a space. Confirmed to bite:
quoting the pathspec as `":(exclude)"$mem` instead of `":(exclude)$mem"` fails
that scenario and no other.
