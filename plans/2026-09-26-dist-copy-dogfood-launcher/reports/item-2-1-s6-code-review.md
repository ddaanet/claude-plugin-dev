# Item 2.1/6 code review (self-review note, no diff)

Scope: the four-line guard in `toolkit/bin/claude`, which is a one-guard
implementation reviewed in session.

- **The lookup and the exec see the same PATH.** `command -v` runs after
  `export PATH=…`, so it searches the PATH the `exec` will use. The shim's own
  entries are already dropped, so the lookup cannot find the shim.
- **No function or alias can shadow the lookup.** The script defines no function
  named `claude`, and a non-interactive bash expands no aliases.
- **Residual: a non-executable `claude` file.** Where the only `claude` left on
  PATH is not executable, bash's `command -v` can still name it, because it
  falls back to a non-executable match. The `exec` then fails with bash's own
  `Permission denied` and exit 126, which is a loud failure and correct enough.
  No test pins this case.
- The test review's mutation table already shows the discriminating mutant: the
  line printed with a fall-through to `exec` reds.

No changes.
