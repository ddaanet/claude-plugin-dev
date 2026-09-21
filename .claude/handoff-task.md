## Current task

The deliverable-review fix pass in `plans/2026-09-18-deliverable-review-fixes/`
is executed: `/orchestrate` ran all four phases and `tdd-audit` through three
nested opus delegates (main session, then a `general-purpose` delegate invoking
the skill, then the item agents). The audit is `reports/tdd-audit.md`; the
dispatches the run skipped, including the one unjustified omission (Item 1.3/1's
code review), are recorded after the fact in `reports/skipped-dispatches.md`.
`toolkit/release.sh`'s drift-refusal comment was corrected as a follow-up, and
the auditor's recommendations against the execution skill went to edify's inbox
as `brief-orchestrate-delegated-run-findings.md`. Nothing is in flight; what is
left is the remainder in the todo file.

Two calls were made by the main session while my human partner was away and are
theirs to reverse: Phase 3's items ran an additive "defeat the shared refusal
mechanism" sweep on top of each proofed gate, and the changelog entry keeps its
write-time date, `2026-09-20`, where the runbook said `2026-09-18`.
