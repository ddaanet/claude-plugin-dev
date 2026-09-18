## Open decisions

- C4 establishes a citation convention — name unambiguous line context (the
  enclosing symbol plus a quoted fragment) rather than a line number, with
  citations into frozen dated artifacts exempt and keeping their numbers. It is
  recorded only in C10's dated changelog entry. Whether it also belongs as a
  bullet in `CLAUDE.md`'s Conventions section, where this repo's binding rules
  live, is unmade. A brief proposing the same convention upstream sits at
  `../edify/inbox/brief-cite-line-context-not-line-numbers.md`; dropping it was
  the end of this repo's involvement there.

## Remaining

- `/runbook` over `plans/2026-09-18-deliverable-review-fixes/outline.md`, then
  `/orchestrate`. The outline's Dependencies section is load-bearing for
  dispatch: four items edit `tests/version-guard-test.sh` and four edit
  `tests/self-release-test.sh`, with three line-level overlaps, so items sharing
  a file run sequentially rather than in parallel — and B7 runs last on
  `version-guard-test.sh`, or the assertions B5 and B6 add land in the
  pre-conversion matcher form. `/runbook` also splits Cluster C per file rather
  than emitting one eleven-part dispatch.
- `/gitlore:index-audit` on the root `memory/MEMORY.md`, which is over Claude
  Code's loader cap. Five facts are queued unwritten behind it:
  - mutation-test a refusal's *prose*, not only its decision;
  - to test a property a `set -o` line currently masks, run a `sed`-stripped
    copy of the script with that line removed, as `tests/release-test.sh` does
    for `pipefail`;
  - `git-config-multivalued-read` warns against `git config -z --get-regexp`
    when the key is interpolated, while `shared-claude.md`'s always-on
    whitespace rule names that exact form as a default, with no routing cue
    between them;
  - Claude Code installs a `grep` *shell function* wrapping ugrep, so probing
    grep behaviour by hand measures ugrep and not the `/usr/bin/grep` a script
    actually gets — this produced a wrong EPIPE threshold before it was caught;
  - ralph-loop's completion-promise path can fail to match a `<promise>` tag
    that is byte-identical to the stored promise, so `--max-iterations` is the
    reliable backstop rather than the promise.
- The unreproduced `tests/release-test.sh` failure of 2026-09-17, at `release:
  still refuses a genuinely dirty non-memory path in the marketplace repo`.
  Clean on every full run since; that scenario is where to look if it recurs.
