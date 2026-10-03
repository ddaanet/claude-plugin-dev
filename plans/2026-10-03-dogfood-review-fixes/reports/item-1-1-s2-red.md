# Item 1.1/2 RED — a failed sync at launch is attributed to the shim

Test: tests/dogfood-launcher-test.sh, scenario "a failed sync aborts the
launch". Added one assertion: stderr holds exactly one line matching
`^dogfood:.*not started`. The scenario's existing assertions are kept: exit
status 1 (sync's own), sync's refusal line on stderr, the next claude's argv and
pid records absent. No SUT change (toolkit/bin/claude untouched, no mutation
needed).

Run: `bash tests/dogfood-launcher-test.sh`, 1 failure, on the assertion:

    FAIL: a failed sync aborts the launch: one dogfood: line says claude was not
    started: expected '1', got '0'

All other assertions pass, including the existing ones in the scenario. Nothing
committed; test and this report are uncommitted.
