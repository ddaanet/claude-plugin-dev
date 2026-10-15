# 2026-10-15 — A plugin can publish an allowlisted `dist` branch, and created marketplace entries use a `url` source

Two inbox briefs arrived the same day. One came from handoff: the plugin
directory refuses a plugin folder that holds a gitlink, handoff mounts the
gitlore `memory` submodule at its repo root, which is its plugin folder, and
`git subtree split` and a subfolder layout were already ruled out. The other
came from ghmem: `bump_marketplace` created entries as
`{source: "github", repo}`, which clones over SSH. My human partner took every
default the plan proposed, and the two ship as one release.

## What changed

- `bump_marketplace` creates entries with
  `{source: "url", url: "https://github.com/<slug>.git"}`. An existing entry's
  `source` is never rewritten.
- A new shipped script, `toolkit/dist.sh`, reads the `dist.include` allowlist
  and builds the tree of the listed paths from a commit with plumbing. It
  refuses a gitlink, a symlink, a missing manifest and a missing listed path,
  and warns on size, file count, README length and licence.
- `release.sh` of an opted-in plugin validates the tree in the pre-flight,
  publishes `dist` and a `dist-vX.Y.Z` tag in a new `push_dist` step between the
  tag push and the GitHub release, and sets `ref: dist` on the marketplace
  entry.
- `dogfood.sh sync` copies only the listed paths when `dist.include` exists.
- Design: `docs/references/dist-branch.md` is new, with its conclusions in the
  hub. `dogfood-sync.md`, `release-flow.md` and `recovery.md` were rewritten in
  place.

## Differences from the plan, found in implementation

- `release.sh` and `dogfood.sh` refuse when `dist.include` exists and `dist.sh`
  is not vendored beside them, rather than release or sync without the list.
- `push_dist` probes `dist-v$V` locally and on origin before it pushes the
  branch, so a conflicting tag leaves nothing pushed.
- The dist pre-flight is a step of its own after `release_preflight`, which
  returns early on a first release.
- The line rules also refuse `.`, `.git` components, empty components and CR
  line endings.
- A listed symlink takes a file rule in the dogfood copy, while `tree` refuses
  any symlink in its result.
- "Already landed" is read from the dist tip's subject, `dist v$V from <sha>`.

## Not established

Whether the portal accepts `dist` before its first push is untested; the first
release creates the branch before anyone points the directory at it.
`claude plugin validate --strict` passed a marketplace entry with a misspelled
`reff`, so validation is no evidence that `ref` is honoured; the release test
pins the field and the marketplace reference is the evidence.
