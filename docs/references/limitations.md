# Limitations

What the toolkit does not do, or does only at a known cost, and why each is
accepted. The hub, [../design.md](../design.md), lists each as one line; the
argument is here.

## Hybrid Python+plugin repos (e.g. edify) are out of scope

Their release recipes need PyPI publish, dry-run, rollback, and version bumping
via `uv version` — different shape entirely. Wrapping edify-style flows into the
unified recipe would either require conditionals that obscure the main path, or
break edify outright. Edify keeps its bespoke recipe.

## `release` is not atomic, but it is recoverable

The tag push, `gh release create` and marketplace push are outward-facing and
cannot be rolled back, so any failure after the version commit leaves the plugin
tagged at the new version with a stale marketplace entry. That remains true. Its
consequence no longer is: `just resume-release` completes the release from
wherever it stopped. Recovery only ever moves forward to the version already
committed — rolling a release back is still out of scope.

## No automated propagation

When the toolkit ships a new tag, each consumer plugin must run
`just update-plugin-dev dist-vX.Y.Z` individually. Adopting changes is a
deliberate per-consumer decision — by design, but worth being explicit about.

## Subtree pull requires the toolkit URL be reachable

Fully offline development of consumers works, but updates need network.

## The version-guard hook fires only in consumers that ran `install.sh`

A consumer that vendored the toolkit but skipped installing the hook is
unprotected. Mitigation: `install.sh` does both in one step.

## Toolkit updates may require a consumer justfile edit

Adopting a new toolkit tag is not always a pure `git subtree pull` — the
`prerelease` gate landed as a required consumer-side recipe. Releases with such
a step ship a `migrations/vX.Y.Z.md` note that `update.sh` prints after the
pull; the upgrade itself never edits consumer files.

## The shipped scripts carry a high comment volume, accepted rather than unnoticed

Roughly half of `release.sh` and the sibling files it sources is comment-only,
much of it write-time record rather than contract. The `dist-` tree ships no
design doc or changelog, so a consumer reading the script has none to reach for,
and the record stays where the reader is. The cost is real: a comment that
retells an incident ages with the code around it and has to be rewritten when
the code moves.

## A dogfood session launched from a subdirectory runs without its project hooks

Claude Code reads project settings from the launch directory only, so the copy
loads but the copy guard, the `SessionStart` check and the version-guard do not
fire, and nothing reports it. The shim does not refuse; the manual says to
launch from the repo root.

## The dogfood sync is unprobed against macOS rsync

Whether `openrsync` or rsync 2.6.9 accepts the flags the sync combines is not
established.

## Solo-author workflow assumed

The toolkit is built around one maintainer's plugins. Multi-contributor
scenarios (e.g. forks proposing changes back to the toolkit) work mechanically
but haven't been ergonomics-tested.

## A gate's input list is partly unchecked

A check reading outside the list narrows the cache silently; only the manual's
rule and its procedure for proving a list stand against it. A pathspec matching
nothing is refused.

## The reference check reads Markdown links and nothing else

A backticked path, a `${CLAUDE_PLUGIN_ROOT}/` form in a command, and a path in a
script are not checked, so a rename that strands one of them passes. A root
`/path` target is skipped rather than guessed at. The parser is a line scanner,
not a CommonMark one. An indented code block is read as prose, since a list
item's continuation looks the same, so an example link in one is checked; fence
it. A backtick that never closes hides the rest of its paragraph, so a link
there is missed. The argument is in
[check-refs.md](check-refs.md).

## No standardised hook library yet

The toolkit doesn't prescribe shellcheck, trailing-whitespace,
end-of-file-fixer, etc. for consumer plugins — each consumer defines its own
`precommit` recipe. May change if patterns converge across enough consumers.
