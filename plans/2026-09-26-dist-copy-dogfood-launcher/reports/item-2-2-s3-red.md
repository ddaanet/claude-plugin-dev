# Item 2.2/3 RED: a pre-existing SessionStart entry survives

Test: tests/update-plugin-dev-test.sh, scenario "install.sh: wires into an
existing settings.json without replacing it". Fixture gains
`SessionStart: [{hooks: [echo consumer-start]}]` (PreToolUse entry and
permissions kept). After the first install, two assertions:

- `a pre-existing SessionStart entry survives`: exactly one
  `echo consumer-start` hook.
- `the session-start hook sits beside the consumer's SessionStart entry`:
  exactly one session-start command in the SessionStart array.

## Result against current SUT

Passes (expected: the behaviour is already in `add_hook`). Slice 1 and 2
assertions still hold with the richer fixture; suite prints "update-plugin-dev
scenarios passed".

## Mutation proof

Mutation in toolkit/install.sh (`add_hook`, one occurrence):
`.hooks[$event] += [` -> `.hooks[$event] = [`.

Suite output under mutation, 3 failures:

- `a pre-existing SessionStart entry survives: expected '1', got '0'` (this
  slice's assertion, on its own)
- `install.sh kept the consumer's own matcher-less hook: expected '1', got '0'`
  (slice 1's, same cause)
- `install.sh added the version-guard hook: expected '1', got '0'` (earlier
  assertion, same cause)

The "sits beside" assertion stayed green under this mutation (the replacing
array still holds the new command); it guards only the positive half and is not
discriminating by itself.

Restore: inverse replacement. Grep for the mutation text: no hit (0).
`git diff --stat toolkit/install.sh`: empty. Suite green afterwards.
