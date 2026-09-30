# Item 2.2 slice 4 RED — idempotency ignores the matcher

Test added to tests/update-plugin-dev-test.sh, scenario "install.sh: wires into
an existing settings.json without replacing it", after slice 2's re-run block:
- jq rewrites the matcher of the entries carrying the pre-tool and version-guard
  commands to `Bash`.
- Setup assertion `an entry under another matcher counts as present: setup`
  (both commands sit only under `Bash`: "Bash Bash") so the test cannot pass
  vacuously.
- Copy aside to `$sandbox/settings.before`, re-run install, `cmp -s`
  byte-identical
  (`an entry under another matcher counts as present: settings.json changed` on
  failure).

Against the current SUT: passes (suite prints "update-plugin-dev scenarios
passed"), as expected — the behaviour already exists.

## Mutation proof

Test: `an entry under another matcher counts as present` (the cmp assertion).
String pair in toolkit/install.sh `add_hook`:
- from:
  `([.hooks[$event][]? | .hooks[]? | select(.command == $cmd)] | length > 0)`
- to:
  `([.hooks[$event][]? | select(.matcher == null or (.matcher | test("Write|Edit"))) | .hooks[]? | select(.command == $cmd)] | length > 0)`

Mutated run:
`FAIL: an entry under another matcher counts as present: settings.json changed`
— the only failure (1 failure); the setup assertion and all other assertions
held.

Restore: inverse replacement. Proof: grep for `test("Write|Edit")` in
toolkit/install.sh: no hit; `git diff --stat toolkit/install.sh`: empty; suite
green ("update-plugin-dev scenarios passed").
