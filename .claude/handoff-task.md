## Current task

One thread, not mid-flight.

The docs and memory work is settled: `docs/changelog/` stays inside `just
format-docs` with the historical reflow grandfathered, and the
`claude-plugin-dev` memory is split into a vendoring entry and a release entry,
both now under the 4096-byte recall cap that the single 7.5KB file was
truncating at 54%.

What remains is the consequence of that split. Two briefs in `plans/` supersede
both memory entries by moving each fact to an artifact that already ships — the
release lore becomes diagnostic output `release.sh` emits at the failure, and
the vendoring lore folds into `toolkit/README.md`, which the human's own
install or update request routes an agent to. Neither brief is implemented, and
the memory entries retire only when they land.

Also live: how a first install should be invoked, which is the one moment
`toolkit/README.md` cannot reach because the tree it lives in does not exist
yet.
