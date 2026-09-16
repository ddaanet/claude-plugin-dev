Attack the design for faults or missed requirements.

The artifact under review is the design outline
/Users/david/code/claude-plugin-dev/plans/2026-09-15-first-release-version/outline.md,
not the diff's other files. It plans a change to a shell release toolkit that
consumer Claude Code plugins vendor via git subtree. Read, in this order: the
repo's CLAUDE.md, the source brief
plans/2026-09-07-brief-first-release-version-selection.md, the outline, and the
prior review plans/2026-09-15-first-release-version/reports/outline-review.md
(its fixes are already applied; do not re-report them).

The four Rules at the top of the outline were settled by the maintainer. Do not
argue for different rules. Attack whether the planned changes implement them and
where they break under real conditions.

Verify against the current code, do not trust the outline's claims:
toolkit/release.sh, toolkit/version-guard.sh, toolkit/check-version.sh,
toolkit/release.just, tests/release-test.sh, tests/hook-test.sh, and the docs
under docs/. Check every file:line citation resolves to what the outline says it
does. Run git commands in a scratch repo under a temporary directory to confirm
any claimed git behaviour (tag sort order, ls-remote exit codes and pattern
matching) you doubt.

Probe in particular:

1. Detection by semver-tag absence alone. Every way a released plugin can
   present no local `^v[0-9]+\.[0-9]+\.[0-9]+$` tag (shallow clone, fresh clone
   without tags, tags under another prefix, fetch config, CI checkout) and
   whether the planned origin probe catches it before any side effect — tag
   creation, branch push, GitHub release, marketplace commit.
2. The origin probe's exit-code branching under `set -euo pipefail`, remotes
   that are not named origin, auth failures, and a probe that passes but a later
   push that fails. What state a failure at each step leaves, and whether
   `just resume-release` recovers it or loops.
3. Open question 1 (marketplace entry disagreeing with the manifest on an
   initial release) and Open question 2 (hook wording when the tag listing
   fails): is the default sound, and is there a state neither option handles?
4. version-guard.sh: any path where the new tag listing turns a deny into an
   allow or emits stderr/non-JSON; whether the initial-release message can be
   read by an agent as permission or a workaround; GIT_* environment leakage;
   CLAUDE_PROJECT_DIR inside an enclosing repo; paths with spaces.
5. The tag filter duplicated between release.sh and version-guard.sh: can the
   two copies diverge in a way the planned tests would not catch?
6. Tests: for each scenario claimed red, would it actually fail against
   unchanged code for the stated reason? Missing scenarios for the failure modes
   above.
7. Requirements in the brief the outline drops or contradicts, docs the change
   leaves stale, and consumers or release states the "no migration note"
   conclusion misses.

Report each finding with: severity (critical/major/minor), the outline section
it attacks, the code citation that grounds it, a concrete failure scenario
(inputs and repo state leading to the wrong outcome), and the change to the
outline that would fix it. Mark anything you could not verify as unverified.
Omit praise and restatement of what the outline gets right.
