# 2026-08-14 — Consumers vendor a split `dist-` ref, closing the squash leak

Closes the two briefs that had been sitting in the repo root since 2026-08-12
and 2026-08-13 (`brief-subtree-squash-leaks-memory-submodule.md`,
`brief-subtree-squash-leaks-toolkit-environment.md`), found from the `handoff`
and `gitlore` consumers.

`git subtree` copies the **root tree** of the ref it is given, and this repo's
root is its own working environment. Every consumer that vendored a `vX.Y.Z`
tag therefore received, tracked in its own history: the `memory` gitlink,
`.claude/` (including `settings.json` and the maintainer's `handoff-task.md`),
`.envrc`, `.gitlore/bin/claude`, `.gitignore`, `.gitmodules`, `CLAUDE.md`, this
repo's own `justfile`, `docs/`, `plans/` and `tests/` — 37 paths where 8 were
wanted.

Two beyond what the briefs identified. `CLAUDE.md` ships agent instructions
that load for a consumer's agent working under `plugin-dev/`, telling it it is
in the toolkit repo; and this repo's `justfile` lands as a second justfile
inside the consumer. Both join `.claude/settings.json` in the "changes
behaviour" class rather than the "inert clutter" class.

Fixed by moving the consumer-facing files under `toolkit/` and having
`just release` cut a second tag per release —
`git subtree split --prefix=toolkit`, tagged `dist-vX.Y.Z` — which consumers
vendor instead. `install.sh` and `update-plugin-dev` now accept **only** a
`dist-v*` ref, rather than warning: vendoring anything else reintroduces the
entire leak silently and stays invisible until someone runs
`git submodule status`.

Refusing branch refs is a reversal, not just a tightening. They were
previously permitted with a "prefer a tag for reproducibility" warning, on the
reasoning that reproducibility was the only thing at stake. It is not: a
branch resolves to the same root tree a source tag does, so nothing about
being a branch makes its tree safe to vendor.

That reversal in turn retires the `-c fetch.recurseSubmodules=no` scoping
added in v0.5.2 and extended to `install.sh` in v0.5.4. Its collision needed
the fetched lineage to carry a gitlink at a path the consumer had registered
as a submodule; the dist lineage carries no gitlink, and no other lineage is
vendorable, so the case cannot arise. It was briefly kept as "defence in
depth" — which, for a case unreachable by construction, is a reassuring name
for cruft. The tests' `not our ref` assertions went with it: they could no
longer fail, since the refusal now exits before any fetch. Replaced by
scenarios asserting the refusals themselves, which can.

The migration was expected to produce a wall of conflicts, since the dist
lineage is unrelated to what consumers previously pulled. Checked rather than
assumed, and the expectation was wrong: a fixture consumer carrying all 37
leaked paths, pulled to the dist ref, came out at exactly the 8 shipped files
with `git submodule status` back to exit 0 and no conflicts. So no one-time
re-vendor is needed — a plain `just update-plugin-dev dist-vX.Y.Z` cleans an
existing consumer.

`tests/dist-tree-test.sh` pins the shipped set. It asserts against the
**index**, not against `git subtree split` output: split reads committed
history, so a split-based assertion answers for the previous commit and would
pass on the very run where the leaking file is added. Verified to go red by
staging a stray file into `toolkit/`.

Not addressed here: the bootstrap gap for consumers still below v0.5.2
(`brief-update-plugin-dev-bootstrap-gap.md`). It is narrowed but not closed —
`install.sh` is fixed and reaches a fresh clone, but an already-vendored
consumer below v0.5.2 still executes its own old `update-plugin-dev`, and the
documented `GIT_CONFIG_COUNT` workaround is still unwritten.

See "Consumers vendor a split dist ref" in [design.md](../design.md).
