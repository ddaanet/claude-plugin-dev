# Item 1.2/2 test review

Scope: the uncommitted diff to `tests/dogfood-test.sh` and the RED report.
Nothing staged or committed. `toolkit/dogfood.sh` untouched
(`git diff --quiet toolkit/`).

## Verdict

RED is genuine. One fix applied: the refactored deny assertions now carry the
test's label, so the two deny tests' failures can be told apart.

## Checks

1. **Mechanical.** The suite was run in the foreground against the committed
   SUT. The new `pre-tool denies a NotebookEdit into the copy` fails on 7
   assertions: every `jq_holds` fails over empty stdout. Its exit-code and
   stderr assertions pass, because the committed `pre-tool` reads only
   `.tool_input.file_path`, finds nothing and exits 0. The 1.2/1 tests (Edit
   deny and source allow) and every other scenario pass. Total: `7 failure(s)`.
   `bash -n` and `shellcheck` are clean.
2. **Refactor preserves 1.2/1.** Compared the moved assertions against the
   committed ones with `git diff`. All nine checks are preserved with identical
   filters, `-s` and `--arg` bindings: exit code, empty stderr, one JSON object,
   hookEventName, permissionDecision, the reason naming the denied path,
   additionalContext naming the source, and the two systemMessage checks.
   `run_pre_tool Edit file_path …` builds the same payload as before. The
   source-allow test is unchanged apart from its call.
3. **The payload has no `file_path`.** It is
   `{tool_name:$t,tool_input:{($f):$p}}` with `$f=notebook_path`, so
   `tool_input` holds only that key.
4. **Wrong-reason probes.** Each probe ran on a temp copy of the SUT and suite,
   not on the tree:
   - The path read as `.tool_input.file_path // .tool_input.notebook_path`: all
     scenarios pass.
   - The path read as `.tool_input.notebook_path // .tool_input.file_path`,
     ignoring `tool_name`: all scenarios pass. This is acceptable because it is
     the interface.
   - `notebook_path` read correctly but the source mapped wrongly
     (`$root/${rel#*/}`): both deny tests fail on
     `additionalContext names the source path`. A wrong mapping is caught for
     NotebookEdit.

## Fix applied

- **The deny assertions' labels were not per-test.** `assert_denied` passed
  fixed labels to its `jq_holds` checks, such as `deny hookEventName`. The Edit
  test and the NotebookEdit test therefore printed identical `FAIL:` lines. Only
  the `===` header told them apart, and headers go to stdout while `FAIL:` lines
  go to stderr. The seven labels are now `"$label: …"`, for example
  `pre-tool denies a NotebookEdit into the copy: hookEventName`. This is
  stricter than 1.2/1's committed labels and weakens nothing. The suite was
  re-run: the same 7 failures, now labelled with the test name, and every other
  scenario green.

## Not a defect, noted

- The NotebookEdit payload targets `SKILL.md` rather than a `.ipynb` file. The
  guard is path-based and the fixture has no notebook, so this is fine.
- No test allows a NotebookEdit of a source path. An implementation that denies
  every NotebookEdit would pass this slice. The slice asks only for the deny,
  and the shared path read makes that implementation unnatural. It is out of
  scope; 1.2/3 covers the allow paths for `file_path` only.
