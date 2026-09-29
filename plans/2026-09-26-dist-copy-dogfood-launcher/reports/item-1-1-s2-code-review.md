# Item 1.1/2 code review — no implementation diff

Slice 1.1/2 changed only `tests/dogfood-test.sh`. `toolkit/dogfood.sh` is
byte-identical to 1.1/1's reviewed state: `git diff --quiet` held after every
mutation restore, in RED and in test review. The code review's scope is the
implementation files, and there is nothing in scope to review, so no
`edify:corrector` was dispatched.

Carried forward, and not a defect: the test review observed that `--delete` is
redundant beside `--delete-excluded`, which implies it (rsync 3.5.0). It is kept
because outline decision 2 names the flag set verbatim. The redundancy also
costs nothing on an rsync where the implication might not hold.
