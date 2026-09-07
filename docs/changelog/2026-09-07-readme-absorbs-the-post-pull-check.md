# 2026-09-07 — The README absorbs the post-pull check, and memory shrinks

Implements
[the 2026-09-02 brief](../../plans/2026-09-02-brief-readme-absorbs-update-lore.md).
The ddaanet memory entry `claude-plugin-dev` held the vendoring and update lore.
Almost all of it was already in `toolkit/README.md`, checked item by item when
the brief was written: the migration notes and the crossed-range printing, the
pre-dist leaked-environment cleanup, the ref-refusal rules, the
`precommit`/`prerelease` contract down to the literal
`unknown dependency prerelease`, the release commit convention, the
last-released rule, first-release-with-no-bump, and `origin/HEAD` branch
detection. Duplicating them into memory was the original error: two copies of a
fact drift, and only one of them ships.

One item was genuinely missing, and it is the one whose absence is silent. A
toolkit version that requires a consumer-side change — the `prerelease` recipe
was one — makes `just` refuse to compile *any* recipe. Nothing announces that.
The pull succeeds, the migration note prints or does not, and the breakage
surfaces at the next unrelated recipe run, which may be days later and will look
unrelated to the update. So "Updating in a plugin" now ends with `just --list`
as a verification step, stated to stand whether or not a note was printed, plus
the commit shape: the consumer-side fix is its own commit, separate from the
subtree-pull merge, because the merge is toolkit content and the fix is the
plugin's own.

The root `README.md` carries the same step in one sentence, pointing at the
manual for the rest. It has to: it carries the same install and update
instructions, and a change to that flow lands in both files.

With the README owning it, the memory entry drops from 4025 bytes — about 70
under the 4KB recall cap — to under 2KB. What is left is what the README cannot
own. The routing line, because an agent that has not opened
`plugin-dev/README.md` does not know it is there. And the changelog, because
`docs/` is not in the dist tree at all: a pull crossing more than a patch is
worth reading `docs/changelog.md` for, whose pointer lines say outright when a
release is breaking where an optional migration note may not, and it can only be
read from a source checkout.

Two things the brief ruled out of the README stayed out. `edify` not vendoring
the toolkit is a scope boundary of this repo, owned by `design.md` "Limitations"
— a consumer manual is the wrong place for it. And the `git subtree` root-tree
mechanism belongs to
[references/distribution.md](../references/distribution.md); the general lesson
is worth publishing somewhere broader, and a brief for `plugin-craft` carries it
there.
