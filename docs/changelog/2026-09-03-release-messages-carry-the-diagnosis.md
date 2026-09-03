# 2026-09-03 — Release refusals carry the diagnosis and the next command

The operational lore around `release` and `resume-release` was held in a ddaanet
memory file: which paths `error: uncommitted changes` really means, what is
already public when a run dies at the marketplace bump, that the recovery is
`just resume-release` and never a retry from the top. That location is wrong for
it twice over. It is reachable only from a machine that mounts the tier, and
only when an index line happens to match the string the failure printed — while
the consumer hitting the failure is often a plugin repo with no memory store at
all. The script, by contrast, is present in every one of them.

So the facts moved into the messages the script emits at the moment of failure.
Anything an agent or a maintainer needs at one of these refusals is now in the
refusal. It ships with the vendored tree, reaches a consumer that has never
heard of gitlore, and cannot drift from the check it guards.

A `docs/` page was the other candidate and is worse than either: nothing routes
a reader to a document at the moment a release dies mid-flight, and the `dist-`
tree ships no `docs/` to route them to.

## What each refusal now says

**The clean-tree checks.** `die "uncommitted changes"` was bare, which is the
whole reason the memory fact existed — the message was consistent with the
checker being wrong about a staged handoff frame, and that reading cost real
time. `tree_is_clean` split into `clean_pathspecs`, which builds the pathspecs
and the human wording of the same exemptions together, and `report_dirty`, which
prints the offending paths and then the exemptions that did *not* save them. The
two are built in one place so a message can only ever name the exclusions its
own copy of the script applies: a consumer whose vendored `plugin-dev/` predates
one of them must not be told about an exclusion it does not make. The message
also says outright that `.claude-plugin/` is not exempt, because that is the
near-miss reading the shared prefix invites.

**The `MARKETPLACE_DIR` clean check** gets the same report and a heavier
consequence. It can fire on a release that is already public through its GitHub
release — a run that reached `bump_marketplace`, staged the bump, and had the
commit refused leaves exactly that state, which the next run reads as an
unrelated dirty file. So it says what may already be published and names
`just resume-release`.

**The refused marketplace commit** now says it rather than dying on git's own
words: the tag is public, only the entry is behind, the bump is staged and left
there, and the recovery is the printed
`git -C <dir> checkout HEAD -- .claude-plugin/marketplace.json` followed by
`just resume-release`. The checkout is not optional — resume's own pre-flight
refuses a dirty marketplace — so the message says that too.

**The refused marketplace push**, the release's last outward step, was a bare
`set -e` death. It now names what is already public and carries the `/add-dir`
remedy for the case the memory file recorded: Claude Code's auto-mode classifier
refuses that push as an external repo outside the trusted source-control org.
`check_marketplace_writable`'s existing `/add-dir` line covers the file write,
which is a different denial.

**The first-release refusal** states the remedy and not just the refusal: to
publish some version other than the manifest's, set `.version` there first and
re-run with no bump. That edit is the one the version-guard hook refuses from an
agent, which the message says as a fact about who decides, not as a route around
the hook.

**The version-drift refusal** states the invariant it is protecting — the
manifest holds the *last released* version, never the next one — and gives the
revert command verbatim, plus the `git fetch --tags` case where the manifest is
right and the tag is merely absent locally.

No message offers a way to skip a check. That is the same rule the version-guard
hook's deny message follows.

## Whitespace

Paths come from `git diff -z --name-only` read with `read -r -d ''`. A
word-split read reports one spaced path as two, and both halves name a file that
does not exist. A path containing a newline still prints across two lines —
there is no git quoting mode that survives `-z` — and that residual bound is
stated in a comment rather than implied away. A scenario dirties
`a tracked file.txt` and asserts the whole path lands on one reported line.

## Tests

Existing assertions kept matching: the two `die` strings the suite greps are
unchanged, and the new text is printed before them. Added: the offending path
and both exemptions in the plugin-repo refusal; the path and
`just resume-release` in the marketplace one; an `assert_not_contains` proving a
repo with no memory store is not told about a memory exemption; the spaced-path
scenario; a version-drift scenario (marketplace seeded at the hand-bumped
version so `check-version.sh` passes and the tag check is the one that fires); a
refused-marketplace-commit scenario that then runs the printed recovery verbatim
and asserts resume finishes the release.
