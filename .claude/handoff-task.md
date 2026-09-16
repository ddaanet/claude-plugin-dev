## Current task

Designing how a plugin's first release chooses its version (brief `plans/2026-09-07-brief-first-release-version-selection.md`, triaged Moderate via /edify:design). The `/proof` pass over `plans/2026-09-15-first-release-version/outline.md` is finished: 16 items, 1 approved and 15 revised, all verdicts applied. Four of them changed the design — `--sort=-v:refname` on the origin tag listing, a second branch in resume's hint ladder, splitting listing-failure from listing-emptiness in the version-guard, and Open question 3 flipping from an accepted bound to a `common_preflight` refusal. All three open questions are now settled, so that section is titled Decisions.

The outline was then compressed from 498 to 376 lines to clear the 400-line docs cap without splitting it or marking it `cap-ok`: recurring shell gotchas hoisted into one Shell constraints section, test scenarios reduced to one bullet each, rejected alternatives to a sentence. `just precommit` is green.

Next is the runbook, whose one irreducible job is slicing — the outline enumerates roughly 27 test scenarios as a flat list with no mapping to implementation slices, and bundling two changes into one slice destroys the red-phase proof.
