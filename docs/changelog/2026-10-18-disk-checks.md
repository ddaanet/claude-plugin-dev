# 2026-10-18 — Precommit is cached, and its checks read disk

This repo's `precommit` now runs behind a sentinel from its own
`toolkit/gates.just`: the guard over every non-ignored file but the `memory`
gitlink, then `whitespace` and `format-docs` moved from recipe dependencies into
the body, then `hash-sentinel`, the checks and `record-sentinel`. An unchanged
tree is a cached pass in a fraction of a second, against about three minutes for
the full run.

Wiring it found a hole. The hash reads the working tree, tracked and untracked
files alike, so staging a file moves nothing in it, while five checks picked
their files from the index. A pass recorded while an oversized file was still
untracked stayed cached through its `git add`, and the pre-commit hook let it
commit unchecked. My human partner's call was to fix the checks, not the key: a
suite's result depends on the files on disk.

## Changed

- **`whitespace`** lists `git ls-files -co --exclude-standard`, NUL-delimited. A
  tracked file it fixes is staged as before; an untracked one is fixed in place
  and reported `(untracked, not staged)`, since adding a file is the committer's
  call. `tests/whitespace-test.sh` is new and drives the real recipe against a
  fixture.
- **`line-cap-test.sh`** and **`citation-test.sh`** scan the same listing. Their
  fixtures gain an untracked file that is now reported and an ignored one that
  is not. The line cap skips a symlink by `-L` and a gitlink by `-f`, in place
  of the index modes.
- **`dist-tree-test.sh`** pins the shipped list from the same listing, the
  execute bits of `bin/claude`, `run-bats.sh` and `check-refs.sh` by `[ -x ]`,
  and a gitlink or nested repository as a directory in the listing.
  **`doc-sync-test.sh`** mirrors its listing.
- **`PLUGIN_DEV_GATE_TOOLS`** hashes bash, git, just, jq, shellcheck and the
  rumdl that `format-docs` resolves.

Hashing the index as well was rejected: it moves the key on every `git add`, and
an index-reading check is still not true of a partially staged commit. That
partial staging stays unchecked, cached or not.
