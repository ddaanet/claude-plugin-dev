# Item 1.2/3 test review

Scope: the uncommitted diff to `tests/dogfood-test.sh` and the RED report.
Nothing is staged or committed. `toolkit/dogfood.sh` was mutated only
transiently and has been restored: `git diff --quiet toolkit/dogfood.sh` is
clean, and a grep for each mutation's text finds nothing.

## Verdict

The tests are sound. No committed-SUT red is possible for this slice because
1.2/1's prefix was already correct. The RED report's mutation proof holds, and
my own four mutations confirm it: each named test reds on its own stdout
assertion. I applied two minor fixes. The suite is green after them.

## Checks

1. **Mechanical.** I ran the suite in the foreground against the committed SUT.
   All scenarios pass, including the three new cases. `bash -n` and `shellcheck`
   are clean. Each mutation below is an exact-string replacement, and I grepped
   to confirm it landed before running. I restored each one with the swapped
   replacement, never with git or a copy.
   - **A: root taken from `CLAUDE_PROJECT_DIR`** (in `pre_tool`,
     `root="${CLAUDE_PROJECT_DIR:-$(root_dir)}"`). This is a different fault
     class from the RED report's M3. `pre-tool allows a path outside the repo`
     fails on `prints nothing on stdout` (it got the deny object). Both deny
     tests also fail, on all 7 of their jq checks (15 failures in total). The
     outside path catches this fault because it sits under `$sandbox/elsewhere`,
     which is `run_dogfood`'s `CLAUDE_PROJECT_DIR`.
   - **A2: unanchored, no leading slash** (`*"$copy/"*`). Only
     `pre-tool allows a path outside the repo … prints nothing on stdout` fails
     (1 failure).
   - **B: a literal `"$root/dist/"*` guard**, with `copy` left as is, so the
     deny messages do not change. `pre-tool allows a sibling of the copy` fails
     on stdout, and so does `a prefix-sharing sibling`, which is expected
     because `dist/plugin-old` is also under `dist/` (2 failures). The deny
     tests stay green.
   - **C: a prefix-strip test with no separator**
     (`[[ "${path#"$root/$copy"}" != "$path" ]] || exit 0` in place of the
     `case`). Only
     `pre-tool allows a prefix-sharing sibling … prints nothing on stdout` fails
     (1 failure).
   - **After restore:** the suite prints `all dogfood scenarios passed`.
2. **Wrong-reason hunting.**
   - **Same payload path as the deny tests.** All three cases go through
     `run_pre_tool Edit file_path …`, the helper both deny tests use. Their
     fixture is built the same way (`make_consumer`, `sync`, `pwd -P` root), so
     each negative is paired with a positive that differs only in the path. If
     the payload were malformed, jq would fail under the script's errexit, and
     that would red `exit code` and `prints nothing on stderr`. It could not
     produce a quiet allow.
   - **Anchoring is exercised.** The outside path
     `$sandbox/elsewhere/dist/plugin/x` contains `/dist/plugin/` and does not
     share the `<root>` prefix. A2 and the RED report's M3 both show a substring
     match denying it.
   - **The observable is the right one.** Empty stdout is exactly what the deny
     emits when it fires, so this is not a proxy. Exit 0 does not discriminate
     (a deny also exits 0), but the contract requires it.
   - **Each case's result is its own.** The loop's `assert_eq` records failures
     without exiting, so one failing case cannot hide another. The `label:path`
     split is `${x#*:}` and `${x%%:*}`, and the labels contain no colon, so a
     colon in `$TMPDIR` would survive in the path.
   - **Holds up against 1.2/4.** Every path's nearest existing ancestor
     (`$sandbox/elsewhere`, `<root>/dist`) is already physical. Resolving
     physically will not change their verdicts.

## Issues

### Minor

1. **Loop variable named `case`.**
   - Location: `tests/dogfood-test.sh`, the
     `pre-tool allows a path outside the copy` loop.
   - Problem: `case` is a bash reserved word. It is legal as a `for` name, but
     `${case#*:}` reads like the start of a `case … esac` construct.
   - **Status:** FIXED. It is now `pair`.
2. **The comment omits a load-bearing property of the fixture.**
   - Location: the comment above the same scenario.
   - Problem: mutation A shows the outside path also catches a root taken from
     `CLAUDE_PROJECT_DIR`. It does so only because the path sits under
     `run_dogfood`'s decoy directory. Nothing stops a later edit from moving it
     elsewhere under `$sandbox` and silently losing that.
   - **Status:** FIXED. One sentence is added to the comment.

## Fixes Applied

- `tests/dogfood-test.sh`: renamed the loop variable `case` to `pair`, and
  extended the scenario comment with the `CLAUDE_PROJECT_DIR` property. After
  both fixes, `bash -n`, `shellcheck` and the suite are green. The suite's own
  result is `all dogfood scenarios passed`.

## Noted, not a finding

- `tests/dogfood-test.sh` is now 532 lines, against the runbook's 300–400
  projection and the 400-line cap. It was already past 400 before this slice.
  The Phase 1 rule says the executor reports the count at the end of Phase 1 and
  the split goes back to the planner, so I did not act on it here.
- The allow cases cover `Edit`/`file_path` only. A NotebookEdit allow is still
  unpinned, as the 1.2/2 review noted. It is out of this slice's scope.
