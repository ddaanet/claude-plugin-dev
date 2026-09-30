# Item 3.1 report

## What changed

- `toolkit/release.just`: new recipe `dogfood`, body
  `bash "{{toolkit_prefix}}/dogfood.sh" sync`, no gate dependency, one-line doc
  comment. The header's `Requirements:` line gains `rsync`. `toolkit_prefix` is
  used the same way as in the neighbouring recipes.
- `justfile` `_import-check`: after the `resume-release` block,
  `--dry-run dogfood` must contain `dogfood.sh" sync` and must not contain
  `stub-precommit`. The recap reads
  `release.just import: ok (plain + widened + missing gate, resume-release, dogfood)`.
- No existing test pinned the recipe list or the recap string, so no test
  changed.

## Mutation gate

Each mutation was applied in place by exact-string replace and undone by the
inverse replace.

- Recipe deleted (name and body): `just _import-check` exits 1 with only
  `error: Recipe _import-check failed with exit code 1`. `--dry-run dogfood`
  fails on the missing recipe inside `out=$(...)` under `set -e`, which is the
  same silent shape as the existing `resume-release` block.
- `dogfood: precommit`: exits 1 with `error: dogfood ran the commit gate`
  followed by `error: Recipe _import-check failed with exit code 1`.
- After restore:
  `release.just import: ok (plain + widened + missing gate, resume-release, dogfood)`,
  exit 0.
