# Item 1.1/3 RED: names with spaces survive

Test added to `tests/dogfood-test.sh` as `=== names with spaces survive ===`.
Fixture: tracked `skills/a b/SKILL.md`; ignored `out dir/x` (`/out dir/` in
`.gitignore`, asserted ignored via `git check-ignore`). Assertions: exit 0;
presence of `dist/plugin/skills/a b/SKILL.md`; absence of `out dir/x` and of
`out dir`. `bash -n` and `shellcheck` clean.

## Against committed sync

Green (NUL-delimited end to end, as expected): `all dogfood scenarios passed`.

## Mutation proof

In `toolkit/dogfood.sh`, replaced `while IFS= read -r -d '' entry; do` with
`while IFS= read -r -d ' ' entry; do` (list split on space, not NUL). Suite red:

```text
=== names with spaces survive ===
FAIL: names with spaces survive: an ignored file under a spaced directory is absent: '.../my consumer/dist/plugin/out dir/x' exists
FAIL: names with spaces survive: the ignored spaced directory is absent: '.../my consumer/dist/plugin/out dir' exists
4 failure(s)
```

(The other two failures come from earlier scenarios, whose ignore lists the
mutation also garbles.) The tracked-file presence (`a b/SKILL.md`) stays green
under this mutation: a tracked path is never in the ignore list, so no plausible
whitespace bug in the list reddens it; it guards only against a sync that drops
or mangles spaced tracked paths (e.g. a `--files-from` split on whitespace).

Restored by applying the swapped replacement:
`git diff --quiet toolkit/dogfood.sh` exits 0; suite green
(`all dogfood scenarios passed`).
