## Brief: `bump_marketplace` writes a `github` source that clones over SSH

2026-10-14 — from a session in `ghmem`

### Decisions

- My human partner asks for `bump_marketplace` to write a new marketplace
  entry's source as
  `{"source": "url", "url": "https://github.com/<owner>/<repo>.git"}` instead of
  `{"source": "github", "repo": "<owner>/<repo>"}`. The call to convert was made
  for ghmem's entry by hand; fixing it at the source is the follow-up. Which
  form the toolkit emits for other cases is yours to check.

### Constraints

- The `github` source clones over SSH with no https fallback. A user without a
  GitHub SSH key cannot install the plugin. Every sibling entry in
  `claude-plugins` is already
  `{"source": "url", "url": "https://github.com/ddaanet/<name>.git"}`, except
  entries using `git-subdir`, which also carry an https `url`.
- A plugin carrying a gitlore `memory` submodule is cloned with
  `--recurse-submodules`, so the clone transport of the parent and of its
  submodules should agree (ghmem's `.gitmodules` was moved to https for the same
  reason).
- Do not rewrite existing entries: `bump_marketplace` updates version and
  metadata of entries already present, and a migration of old `github` entries
  is a separate decision.

### Where

- `toolkit/release.sh`, in `bump_marketplace`, the jq program around line 763:
  `source: { source: "github", repo: $repo }`. `repo_slug` is derived from
  `git remote get-url origin` at line 759; the url form needs the same slug plus
  `https://github.com/` and `.git`.
- Only the entry-creation path matters. The first release of ghmem printed
  `marketplace: entry created at 0.1.0` and wrote the `github` form.

### Additional context

- Observed on the first release of ghmem (v0.1.0). The marketplace commit
  `🔖 ghmem 0.1.0` landed with the `github` source; a hand fix followed in
  `claude-plugins` the same day.
- The release script also printed `gitlore skipped: hooks dir is stale` while
  committing in the marketplace repo. That is unrelated to this brief.
- This needs a test: a first release into a fixture marketplace asserting the
  created entry's `source` object. Check whether the existing release tests
  already pin the `github` form and must change with it.
- Release flow after the fix: the usual `dist-vX.Y.Z` tag, then
  `just update-plugin-dev dist-vX.Y.Z` in consumers; ghmem needs no action
  beyond that since its entry is already converted.
