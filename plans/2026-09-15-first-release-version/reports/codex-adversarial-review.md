# Codex Adversarial Review

Target: branch diff against HEAD~1 Verdict: needs-attention

Do not ship yet: the lost-tags guard misses release history and can inspect the
wrong destination; recovery advice can misdiagnose an already-public release.
Scratch Git probes and runtime tests were blocked by the read-only filesystem.

Findings:
- [high] [major] Exact-version absence does not establish absence of release
  history
  (/Users/david/code/claude-plugin-dev/plans/2026-09-15-first-release-version/outline.md:65-75)
  Attacks release.sh / lost-tags guard. Consider a --no-tags clone whose origin
  has v1.2.3, with a committed manifest and marketplace entry both manually
  advanced to 1.3.0. The proposed probe checks only v1.3.0 and proceeds when
  absent. The planned initial branch then bypasses the
  manifest-versus-latest-tag invariant at toolkit/release.sh:250-264 and
  publishes the hand-written version through :297 and :500-503. Fetching the
  existing tags would instead expose the drift and refuse. All proposed
  lost-tags tests keep origin's tag equal to the manifest, so they miss this
  case. Outcome inferred from code; runtime reproduction unverified.
  Recommendation: Probe origin's complete release-tag namespace and apply the
  settled anchored filter. If any matching remote tag exists while none exists
  locally, refuse and require fetching tags before reevaluating. Add a
  different-remote-version fixture asserting no local tag, branch push, GitHub
  release, or marketplace change.
- [high] [major] The probe and publication can target different repositories
  (/Users/david/code/claude-plugin-dev/plans/2026-09-15-first-release-version/outline.md:69-80)
  Attacks release.sh / origin probe. toolkit/release.sh:327 queries origin, :342
  executes unqualified git push, and :355-365 queries origin before pushing its
  tag. The outline does not validate push routing. With origin's fetch URL
  pointing to a tagless mirror and its push URL pointing to the published
  repository, the new probe can pass despite an existing destination tag. The
  script creates a conflicting local tag and can advance the destination branch
  before the tag push fails. Resume retains that local tag (:279-288) and
  repeats the failure. branch.pushRemote introduces another destination mismatch
  for the branch. Git routing behavior and this reproduction remain unverified
  because scratch-repo creation was blocked. Recommendation: Define and validate
  the publication destination before tagging. Either reject divergent fetch/push
  URLs and branch push routing with an actionable error, or probe the actual
  destinations and use explicit matching pushes. Add split-destination and
  resume fixtures.
- [high] [major] Missing tags can conceal a recoverable published release
  (/Users/david/code/claude-plugin-dev/plans/2026-09-15-first-release-version/outline.md:262-271)
  Attacks Open question 1 and preflight ordering. Suppose v1.2.4 and its GitHub
  release reached origin, the marketplace update failed at 1.2.3, and recovery
  uses a clone without tags. check-version.sh:53-57 refuses before the proposed
  origin probe; the new default tells the maintainer to reconcile either version
  manually. Yet the correct recovery is fetching the existing tag and resuming.
  Following the manifest-reconciliation option can commit 1.2.3 over an
  already-public 1.2.4 release. resume_preflight (:279-288) also cannot
  recognize the remote tag and redirects to release. Neither the default nor
  blindly skipping the comparison identifies this third state. Recommendation:
  Check remote release history before issuing initial-release drift advice. When
  the manifest's tag exists remotely, prescribe fetching tags and then
  resume-release; reserve manual reconciliation for verified unpublished state.
  Test a published tag with a stale marketplace and no local tags.
- [medium] [minor] The retained resume test contradicts the planned behavior
  (/Users/david/code/claude-plugin-dev/plans/2026-09-15-first-release-version/outline.md:177-178)
  Attacks Tests. The outline says tests/release-test.sh:367 keeps the
  tagged-repo hint. Its fixture actually deletes its only local tag at :363;
  only origin retains v1.2.3. Therefore release_tags is empty, and the planned
  resume_preflight change must emit the no-argument hint, failing the retained
  assertion. This is a fixture error, not a regression in the implementation.
  Recommendation: Reclassify the existing fixture as missing-local-tags
  recovery. Create a separate fixture retaining an older local semver tag while
  lacking the manifest's tag to exercise the steady-state hint.

Next steps:
- Revise the probe, destination validation, recovery ordering, and contradictory
  fixture.
- Run scratch Git probes and the added failure/recovery scenarios in a writable
  environment.
