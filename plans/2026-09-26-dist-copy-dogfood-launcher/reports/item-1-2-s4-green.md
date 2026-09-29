# Item 1.2/4 GREEN

`pre_tool` in `toolkit/dogfood.sh` now compares the payload path by its physical
spelling. A new helper, `physical_path`, walks up to the path's nearest existing
ancestor directory, takes that ancestor's `pwd -P` spelling and re-appends the
non-existent tail. The `case` against `"$root/$copy/"*` and the `rel` /
`additionalContext` source path both use the physical spelling.
`permissionDecisionReason` and the `additionalContext` prose still name the path
as given, so the model sees the spelling it used. The comment above `pre_tool`
states the new behaviour.

## Order made to pass

1. `pre-tool denies a copy path through a symlinked repo`: passes once the
   payload is resolved physically (`new/` absent, so the tail is re-appended).
2. `pre-tool denies a copy path through a symlink to the copy`: passes with the
   same change, since the whole path is resolved and not split at
   `/dist/plugin/`.
3. `pre-tool invoked through the symlink denies a physical path`: already green
   (`root_dir` uses `pwd -P`); it stays green.

## Results

- `bash tests/dogfood-test.sh`: `all dogfood scenarios passed`.
- No `lint` recipe exists here; `just precommit` runs in the commit hook.

## Precommit warnings

Recorded from the commit hook run; none reported to this dispatch beyond a
pass/fail verdict.
