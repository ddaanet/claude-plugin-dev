# Item 2.2/2 RED — a re-run is a no-op

Test added to the scenario
`install.sh: wires into an existing settings.json without replacing it` in
tests/update-plugin-dev-test.sh, after the justfile checks: copy settings.json
aside, re-run `bash toolkit/install.sh` with the same env and no ref
(plugin-dev/ is vendored, so none is needed), then assert exit 0, `cmp -s`
byte-identical, and output containing `already installed, nothing to do`.

Against the unmutated SUT the test passes, as expected: slice 1's GREEN already
implements the presence check.

## Mutation proof

Mutation in toolkit/install.sh (`add_hook`), string pair:
`select(.command == $cmd)] | length > 0)` ->
`select(.command == $cmd)] | length > 99)` (presence never detected, so a re-run
appends duplicates).

Suite output, both assertions of this slice red on their own assertion:

    FAIL: a re-run changed settings.json
    FAIL: a re-run reports nothing to do: output did not contain 'already installed, nothing to do'
    2 failure(s)

(The exit-0 assertion stays green under the mutation; it is not discriminating
by design, only a guard on the run itself.)

Restored by the inverse replacement. Proof:
`grep -c 'length > 99' toolkit/install.sh` gives 0;
`git diff --stat toolkit/install.sh` is empty; suite green:
`update-plugin-dev scenarios passed`.
