# Classification — first-release version selection

Source:
[../2026-09-07-brief-first-release-version-selection.md](../2026-09-07-brief-first-release-version-selection.md)

## Item A — first release has no supported way to choose its version

Trigger: the brief's primary gap.

- **Classification:** Moderate. My human partner settled the rules on
  2026-09-15: the initial manifest version is the initial release, detected by
  the absence of a semver `v` tag (see outline.md).
- **Implementation certainty:** High once an option is picked. All three touch
  code that already exists and is tested (`release_preflight`,
  `bump_commit_tag`, `version-guard.sh`, `tests/release-test.sh`,
  `tests/hook-test.sh`).
- **Requirement stability:** Low. The brief lists three mechanisms and
  recommends none, and one of them (a guard that allows the edit) contradicts
  the recorded decision that the maintainer, not an agent, picks the first
  version (changelog 2026-09-03).
- **Behavioral code check:** Yes, whichever option is chosen: a new guard
  branch, a new message branch, or a new argument form.
- **Work type:** Production
- **Artifact destination:** production (`toolkit/`)
- **Evidence:** `release.sh:225-241` (both-conjunct predicate, refusal hint
  already names the manifest edit but not the commit); `version-guard.sh:80-91`
  (message is not aware of the first-release case); `release.sh:130-131`
  (`.claude-plugin/` never exempt from the clean-tree check);
  `docs/references/release-flow.md` "First release publishes the manifest
  version as-is". Recall: no memory covers this domain.

## Item B — README note on `sandbox.excludedCommands` for the marketplace push

Trigger: implicit bundling, the brief's "Additional context".

- **Classification:** Simple
- **Implementation certainty:** High
- **Requirement stability:** Moderate. The claim comes from another agent and
  was checked against CC 2.1.263; neither README covers sandboxing at all yet.
- **Behavioral code check:** No
- **Work type:** Production (documentation)
- **Artifact destination:** investigation (`toolkit/README.md`)
- **Evidence:** `rg` finds no mention of `sandbox`, `excludedCommands` or
  `/add-dir` in either README.
