# Item 1.2/6 GREEN: pre-tool follows a symlink at the leaf

## Growth order

One change made all three slice tests pass, in `pre_tool`: when the physical
path exists and its leaf is a symlink, resolve it with `readlink -fn`, captured
with the `&& printf x` / `${var%x}` shield.

1. `pre-tool follows a symlink at the leaf into the copy`: pass.
2. `pre-tool follows a chain of leaf symlinks into the copy`: pass.
3. `pre-tool allows a leaf symlink out of the copy`: pass.

A dangling leaf link is skipped by the `-e` test, so it stays unfollowed (the
stated residual). `physical_path` and `session_start` are unchanged. The comment
above `pre_tool` was rewritten to state the new behaviour and the dangling-link
residual.

## Results

- `bash tests/dogfood-test.sh`: all scenarios passed.
- `shellcheck toolkit/dogfood.sh`: clean.
- `just precommit` runs in the commit hook; warnings, if any, are in the commit
  log.
