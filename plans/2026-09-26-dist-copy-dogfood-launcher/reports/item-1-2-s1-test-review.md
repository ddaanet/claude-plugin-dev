# Item 1.2/1 test review

Verdict: **fixed, still red on assertions.** Three wrong-reason passes found in
the deny test, all fixed in `tests/dogfood-test.sh`; the allow test was sound.
Nothing staged or committed. `bash -n` and `shellcheck` are clean. Suite is at
497 lines.

## Findings

1. **"stdout parses with jq" was not asserted (major).** `jq_out` ran
   `jq -r <field> 2>/dev/null || true`. For a first object followed by trailing
   garbage or a second non-object value, jq prints the first object's field and
   only then errors. The error was swallowed, so every field check passed. Shown
   against the old helper: with stdout
   `{…"hookEventName":"PreToolUse"…} garbage`, it returned `PreToolUse`. Two
   whole objects did fail, but only as a side effect. Fix: an explicit
   `deny stdout is one JSON object` check,
   `jq -s 'length == 1 and (.[0] | type) == "object"'`.
2. **"systemMessage is one line" missed a trailing newline (major).**
   `$(jq_out .systemMessage)` strips trailing newlines, so
   `"dist/plugin denied\n"` counted 0 lines and passed. This is shown against
   the old helper too. The check was also vacuous when the field was missing.
   Fix: test it in jq,
   `.systemMessage | type == "string" and (test("[\r\n]") | not)`.
3. **The contains checks were BRE, and ran on `jq -r` text (minor).** The `.` in
   `SKILL.md` and in a `$TMPDIR` path is a live metachar. A non-string field
   also passed: `additionalContext: ["<root>/skills/demo/SKILL.md"]` prints as
   JSON that contains the path. Fix: `type == "string" and contains($p)` in jq,
   with `$p` bound by `--arg`. That match is literal, and the spaced root is
   passed intact.

Both fixes go through one new helper, `jq_holds <label> <filter> [jq options…]`.
It fails with the filter and the raw stdout. It replaces `jq_out` and the six
`assert_eq`/`assert_contains` field checks, one contract per line.
`run_pre_tool` is now a one-liner over `run_dogfood pre-tool <<<payload`: the
function's stdin is inherited by the command substitution. This removes the
duplicated run body. Two `# shellcheck disable=SC2016` lines mark `$p` as a jq
variable.

## Checked and sound

- **Wrong source mapping.** `<root>/dist/skills/demo/SKILL.md`, the relative
  `skills/demo/SKILL.md` and a `SKILLxmd` spelling each fail the
  additionalContext check. The denied path itself does not contain
  `<root>/skills/…`, so an unmapped echo fails too.
- **A hook that denies everything, or on `tool_name` alone,** fails
  `pre-tool allows a source edit`. The payload is the same Edit, and that test
  requires empty stdout. A hook that emits an explicit `allow` object fails it
  as well.
- **A silent or no-op hook** passes the allow test and fails every deny check,
  so the pair discriminates.

Mutant probe of `jq_holds`, extracted from the suite, over synthetic stdout.
Scratch file: `/tmp/claude/dogfood-build/probe.sh`. Count = failed checks out of
7:

| stdout | failures |
|---|---|
| correct deny object | 0 |
| object + `trailing` | 7 |
| object + `"x"` | 7 |
| two objects | 1 (one-object) |
| context `<root>/dist/skills/…` | 1 |
| context relative | 1 |
| context with `.`→`x`/`_` | 1 |
| systemMessage ending `\n` | 1 |
| context as array | 1 |

## Red run (committed SUT, `pre-tool` answers usage)

```text
=== pre-tool denies an Edit into the copy ===
FAIL: pre-tool denies an Edit into the copy exit code: expected '0', got '2'
FAIL: pre-tool denies an Edit into the copy prints nothing on stderr: expected '', got 'usage: dogfood.sh sync|pre-tool|session-start'
FAIL: deny stdout is one JSON object: length == 1 and (.[0] | type) == "object" is not true over stdout ''
FAIL: deny hookEventName: .hookSpecificOutput.hookEventName == "PreToolUse" is not true over stdout ''
FAIL: deny permissionDecision: .hookSpecificOutput.permissionDecision == "deny" is not true over stdout ''
FAIL: deny reason names the denied path: … is not true over stdout ''
FAIL: deny additionalContext names the source path: … is not true over stdout ''
FAIL: deny systemMessage names the copy: … is not true over stdout ''
FAIL: deny systemMessage is one line: … is not true over stdout ''
=== pre-tool allows a source edit ===
FAIL: pre-tool allows a source edit exit code: expected '0', got '2'
FAIL: pre-tool allows a source edit prints nothing on stderr: expected '', got 'usage: …'
11 failure(s)
```

Every failure is an assertion, and no harness error occurs. The earlier suites
stay green. "systemMessage is one line" is no longer vacuous on empty output: it
requires a string.

For GREEN, note that `pre-tool allows a source edit` stdout-empty already
passes; its red rests on exit code and stderr, as the RED report says.
