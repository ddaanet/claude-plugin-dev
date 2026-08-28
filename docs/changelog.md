# claude-plugin-dev Changelog

How the design got to its current shape. Each entry is a write-time record of
one change: what moved, and the reasoning available at the time. Entries are
never revised — a dated record is correct forever precisely because it is dated.
The living design is [design.md](design.md); when a decision there is
overturned, it is rewritten in place and the reversal gets an entry here.

Newest first.

- [2026-08-28 — A refused push resumes; the release commit is never amended](changelog/2026-08-28-refused-push-resumes-never-amends.md) — why no `refresh_release_commit` amend step exists, and the hint `push_branch` now prints instead
- [2026-08-28 — The marketplace writability probe keeps mktemp's own words](changelog/2026-08-28-writability-probe-keeps-mktemps-words.md) — the probe discarded `mktemp`'s stderr and then asserted a sandbox cause it never established; also comments why the release-only check must not be `common_preflight`'s last line
- [2026-08-28 — A refused release commit rolls the manifest back](changelog/2026-08-28-refused-commit-rolls-back.md) — a consumer's `pre-commit` hook refusing the release commit left the bump staged and uncommitted, which then blocked both a re-run and `resume-release` on `uncommitted changes`
- [2026-08-14 — Consumers vendor a split `dist-` ref](changelog/2026-08-14-dist-ref-stops-squash-leak.md) — `subtree` copies a ref's whole root tree, so consumers were receiving this repo's working environment; shipped files moved under `toolkit/` and releases cut a `dist-vX.Y.Z` split tag
- [2026-08-13 — `install.sh` subtree add recursion scoping](changelog/2026-08-13-install-subtree-add-recursion.md) — v0.5.2 fixed one of two subtree call sites; `install.sh`'s add hit the same collision, and the test covering the fix could pass vacuously on same-second seed commits
- [2026-08-11 — First release publishes the manifest version](changelog/2026-08-11-first-release-manifest-verbatim.md) — a never-released plugin has no version to bump from, so `just release` ships the version `plugin.json` already holds (v0.5.3)
- [2026-08-11 — `update-plugin-dev` submodule collision](changelog/2026-08-11-subtree-submodule-collision.md) — a consumer's own `memory` submodule at the same path broke `git subtree pull`'s on-demand submodule fetch (v0.5.2)
- [2026-07-29 — `resume-release`](changelog/2026-07-29-resume-release.md) — the release tail became an idempotent block both `release` and a recovery path run (v0.5.0)
- [2026-07-27 — `check-version.sh`](changelog/2026-07-27-check-version.md) — detects a release that tagged and pushed but never bumped the marketplace (v0.4.1, v0.4.2)
- [2026-07-23 — `prerelease` gate](changelog/2026-07-23-prerelease-gate.md) — `release` binds to a consumer-defined gate; breaking, every consumer adds a recipe (v0.4.0)
- [2026-07-01 — Non-interactive release](changelog/2026-07-01-non-interactive-release.md) — dropped the confirmation prompt and `--yes`; the outer permission gate already asks (v0.3.0)
- [2026-06-11 — Marketplace entry creation](changelog/2026-06-11-marketplace-entry-creation.md) — first publication creates the entry instead of aborting; the bump commit became idempotent (v0.2.1)
- [2026-04-29 — `VERSION` file and marketplace bump](changelog/2026-04-29-version-file-and-marketplace-bump.md) — the toolkit can identify itself inside a subtree, and `release` treats tag + marketplace as one release (v0.2.0)
- [2026-04-27 — Initial extraction](changelog/2026-04-27-initial-extraction.md) — toolkit broken out of handoff and gitmoji, the two release recipes unified (v0.1.0)
