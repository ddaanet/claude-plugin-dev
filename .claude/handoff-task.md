## Current task

The dist-ref restructure closing the subtree squash leak is complete and the
gate is green: `toolkit/` is the shipped boundary, and `just release` cuts a
`dist-vX.Y.Z` split tag alongside `vX.Y.Z`.

The next thread is cutting the first toolkit release that exercises that
dist-tag path in `just release` for real — it has only ever run against
fixtures — then propagating the dist tag into the eight sibling consumers,
each of which sheds its leaked `plugin-dev/` paths on that pull.
