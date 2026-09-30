# Item 2.1 slice 3 RED — stripping by identity

Suite: `tests/dogfood-launcher-test.sh`, run in the foreground. SUT
`toolkit/bin/claude` is identical to HEAD (`git diff --quiet` exits 0).
`bash -n` and `shellcheck` on the suite are clean.

Harness change: `make_consumer` sets `path_head=""`; `run_claude` exports
`PATH="${path_head:-$shim_dir:$stubdir}:$PATH"`, so a scenario chooses the
entries ahead of the inherited PATH. Earlier scenarios are unchanged.

## Per-test output (against HEAD's SUT)

- `the shim strips its own entry in any spelling` — RED, genuine. PATH head
  `<shim>/:<shim>:<stub>`. The shim drops only the exact spelling, so `<shim>/`
  survives and the shim execs itself until the watchdog kills it at 10 s.
  - `FAIL: the launcher ran past the 10 s watchdog`
  - `FAIL: the shim strips its own entry in any spelling: the stub ran: '<sandbox>/rec/path' is not a regular file`
  - Whole suite took about 11.5 s; no hang.
- `the shim keeps another bin/claude` — passes (0 failures). Proved by mutation.
- `the shim keeps the rest of PATH as spelled` — passes: the stub's recorded
  PATH equals `:<stub>:$PATH` exactly. Proved by mutation.
- All five earlier tests pass.

## Mutation proof

- Test `the shim keeps another bin/claude`: in `path_without`, replaced
  `[[ "$entry" == "$1" ]] && continue` with
  `[[ "$entry" == "$1" || "$entry" == */bin ]] && continue`. Reds:
  `FAIL: the shim keeps another bin/claude: the one ahead of the stub ran: expected 'ran', got '<stub did not record other>'`.
  (The mutation also broke other scenarios; 10 failures in all.) Restored by the
  swapped replacement; `grep -c '\*/bin' toolkit/bin/claude` gives 0 and
  `git diff --quiet toolkit/bin/claude` exits 0.
- Test `the shim keeps the rest of PATH as spelled`: replaced
  `out="$out:$entry"` with `out="${out:+$out:}$entry"`. Reds:
  `FAIL: the shim keeps the rest of PATH as spelled: expected ':<stub>:…', got '<stub>:…'`
  (the leading empty entry lost). Restored by the swapped replacement;
  `grep -c 'out:+' toolkit/bin/claude` gives 0 and `git diff --quiet` exits 0.
  The suite afterwards shows only the two slice-3 failures of the first test.
