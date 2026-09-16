## Open decisions

- Which `/runbook` pipeline steps run besides the decomposition itself. My human partner said to skip `/proof`; the corrector and the simplifier were not addressed. The simplifier has a real target — several `release-test.sh` scenarios are the same shape with different fixture data. Absent a further answer: run the simplifier, skip the corrector, since the proof pass just covered requirements and design alignment item by item with my human partner in the loop.

## Remaining

- Write `plans/2026-09-15-first-release-version/runbook.md`, slicing into red/green cycles. `release.sh` carries five separable changes — the semver filter with both sorts; detection without the marketplace conjunct; the lost-tags origin probe; resume's hint ladder; `common_preflight`'s push-route refusal — and `version-guard.sh` is its own slice. Map each of the outline's test scenarios to the slice it is red for.
- Stop after the runbook. Do not orchestrate.
- Item B from the brief: a README note on `sandbox.excludedCommands` for the marketplace push. A separate change, and it needs checking against current Claude Code first.
- After the toolkit release, drop a note — not an edit — for `plugin-craft:toolkit-release`, whose first-release wording will change.
- Root `memory/MEMORY.md` is over Claude Code's loader cap (the gitlore hook reports it against a 25600-byte budget), so entries past the cutoff never reach a session. Parked deliberately; `/gitlore:index-audit` is the pass that addresses it. Raise it only if asked.
