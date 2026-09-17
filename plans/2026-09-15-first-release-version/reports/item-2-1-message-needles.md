# Item 2.1 — the three wording needles

Extracted from the slice-1 test review, which is where the analysis was done. It
is its own node because it constrains every later change to the initial-release
message, not just slice 1: slice 2 asserts `$proposed` appears nowhere after the
opening line, and the slice-1 code review rewrote the message outright against
these same constraints.

The assertions are literal, against the extracted `permissionDecisionReason`.
The message must contain `never been released` and `will publish`, and must not
contain `last released version` **anywhere**, including inside a negation.

Asked of each of the three needles: can ordinary English satisfy or defeat it by
accident, in either a correct or an incorrect message?

- **`never been released`** (positive). Multi-word phrase with spaces, so there
  is no `other`/`another`-style substring hazard. It cannot appear in a
  plausible steady-state message: today's says "the last released version", and
  no rephrasing of "this is the version you last shipped" reaches "never been
  released". False-pass risk: negligible. False-**red** risk is real but
  acceptable: a correct initial-release message phrased "this plugin has no
  releases yet" would fail. That is the runbook fixing the phrase, and the GREEN
  author must use it.
- **`will publish`** (positive). Same shape, same conclusion, but tighter: it
  forbids "the first release publishes …" and "publishing happens at release
  time". Again a constraint on the GREEN author rather than a hazard. Worth
  flagging to the GREEN dispatch explicitly, since it is the needle most likely
  to be missed by a message that is otherwise correct.
- **`last released version`** (negative). Two directions checked.
  - *Defeated by rephrasing* (false pass): yes, in principle — a message that
    kept the steady-state *claim* but wrote "the version of the last release"
    would satisfy the negative needle. This is mitigated, not by the needle, but
    by the two positive needles beside it: a message containing both "never been
    released" and "will publish" has already committed to the initial-release
    semantics, so the negative is belt-and-braces rather than the primary check.
  - *Satisfied by a correct message* (false red): also real. A correct
    initial-release wording could plausibly say "there is no last released
    version", and that would fail this assertion. **This is a live constraint on
    the GREEN implementation, not a fault in the test**, and it is verbatim from
    the runbook ("does not contain `last released version`"), so it was left
    exactly as written — changing it would change the red. The GREEN author must
    avoid the phrase entirely, including in a negated sentence.

No needle was changed. All three assertions run against the extracted
`permissionDecisionReason`
(`jq -r '.hookSpecificOutput.permissionDecisionReason'`), never against
`$guard_out` whole, so an unrelated JSON field cannot satisfy one.
