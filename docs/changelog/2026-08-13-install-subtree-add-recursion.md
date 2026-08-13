# 2026-08-13 — `install.sh`'s `subtree add` gets the same recursion scoping as `update-plugin-dev`

Found while reviewing the three briefs sitting in the repo root
(`brief-subtree-squash-leaks-memory-submodule.md`,
`brief-subtree-squash-leaks-toolkit-environment.md`,
`brief-update-plugin-dev-bootstrap-gap.md`). None of them says it, but
together they imply it: v0.5.2 scoped `-c fetch.recurseSubmodules=no` to
`update-plugin-dev`'s `git subtree pull` — one of the toolkit's **two**
subtree call sites. `install.sh`'s initial `git subtree add` performs the
identical raw, unprefixed fetch of this repo's history and was left bare.

The add site wasn't overlooked at v0.5.2 time — it was dismissed, on an
ordering assumption recorded in the test fixture's own comment: "install,
then `/gitlore:add-tier` later", so the initial add has no registered
`memory` submodule to collide with. The briefs' evidence undermines that
order: the consumers hitting the collision (`prohibitions`, `onekeys`,
`gitlore`) are repos that mounted their memory tier first, and any existing
ddaanet-shaped repo adopting the toolkit afterwards runs `install.sh` with
`memory` already registered. The bootstrap-gap brief goes further and
*recommends* "an `install.sh`-style one-shot fetch that doesn't go through
`git subtree pull`'s submodule-recursing fetch at all" as the escape
mechanism — but `subtree add`'s fetch is the same fetch, so the proposed
escape hatch would have died with the same `not our ref`. Unlike the
vendored recipe, `install.sh` runs from a fresh clone of the tag, so this
is the one call site where a fix actually reaches a consumer that doesn't
have it yet.

Reproduced red on a local fixture (`git subtree add` into a consumer with
its own `memory` submodule → `fatal: remote error: upload-pack: not our
ref`), fixed with the same one-fetch scoping, covered by a new end-to-end
scenario in `tests/update-plugin-dev-test.sh` driving the real `install.sh`
(`TOOLKIT_URL` is now env-overridable so the test can point it at a local
fixture repo).

Second find, surfaced by that scenario passing against the *unfixed*
script: the fixture's collision was reachable only by luck of the clock.
Both memory seed repos were a single empty commit with the same fixture
identity and the same message — git commits are fully deterministic, so
whenever setup landed both in the same second they were the *same object*.
The consumer's submodule then already contained the commit the toolkit's
gitlink names, on-demand recursion had nothing to fetch, and the collision
test passed vacuously whatever the recipe did. Distinct seed messages make
the collision deterministically reachable; the existing `update-plugin-dev`
scenario now genuinely exercises its fix on every run, not just on runs
that straddled a second boundary.

Explicitly not addressed here: the squash-time leak of `plugin-dev/memory`
and the toolkit's working environment into consumer trees, and the
documented bootstrap workaround for consumers still below v0.5.2 — both
briefs remain open.

See "Both subtree call sites disable submodule recursion for their fetch"
in [design.md](../design.md).
