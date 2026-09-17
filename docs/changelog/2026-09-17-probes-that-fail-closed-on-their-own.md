# 2026-09-17 — Probes that fail closed on their own, and a pointer a consumer cannot follow

Two small things the same day's
[self-release work](2026-09-17-self-release-gets-a-resume.md) left named and
open.

`release.sh`'s three `git ls-remote origin <ref> | cut -f1` captures now go
through one `ls_remote_sha` helper that captures the line whole and trims it
with `${line%%$'\t'*}`. The pipe was never wrong — `set -o pipefail` makes the
pipeline carry ls-remote's status, so a failed probe kills the run rather than
being read as an answer. What it was, was load-bearing on a `set -o` line
somewhere else in the file. `cut` succeeds on the empty input a failed
`ls-remote` hands it, so without pipefail each capture returns the empty string,
and the empty string is what every caller reads as "origin does not have this
ref" — the answer that licenses the act. `push_tag` is the one that matters:
absence is what lets it push, so the misread would walk straight past the "
refusing to move a published tag" refusal, which exists precisely because a
mismatch there means something no recovery should paper over.

Removing the dependency was the easy half. Encoding it was the question, since
the behaviour is identical while pipefail is in force and a test asserting
today's behaviour would have passed before the change. So the suite now runs a
`sed`-stripped copy of `release.sh` with `set -eu` in place of
`set -euo pipefail`, against an unreachable origin, and asserts the probe
reports *its own* failure and refuses before attempting the push. Against the
pre-change code that scenario fails: the probe comes back empty and the run
proceeds to `git push`. It is a test of the invariant rather than of the output,
which is what makes it worth having.

The other thing: `release.sh` carried a `(decision 3, outline.md)` citation in a
comment. `toolkit/` is the dist boundary, so that comment ships — a consumer
vendors the file and reads a pointer to a document in a repository they do not
have and a directory (`plans/`) that holds prospective content and gets cleared.
The comment's next six lines already make the argument in full, so the citation
is simply gone. The one remaining doc pointer under `toolkit/release.sh` names
`docs/references/recovery.md`, now qualified as "the toolkit repo's" the way
`install.sh` already qualified its own.
