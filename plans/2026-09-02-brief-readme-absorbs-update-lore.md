# Brief: the README absorbs the post-pull verification step

2026-09-02

> **Landed 2026-09-07.** Implemented in `toolkit/README.md` and `README.md`,
> with the memory entry reduced; kept as the record of what was decided, not as
> work to pick up. The "First install is out of scope" section below was settled
> separately by
> [2026-09-04-design-install-bootstrap-fetches-the-script.md](2026-09-04-design-install-bootstrap-fetches-the-script.md).
> See
> [../docs/changelog/2026-09-07-readme-absorbs-the-post-pull-check.md](../docs/changelog/2026-09-07-readme-absorbs-the-post-pull-check.md).

The vendoring and update lore held in ddaanet memory as `claude-plugin-dev` is
almost entirely already in `toolkit/README.md`. One item is not, and it is the
one whose absence is silent.

## Decisions

- **`toolkit/README.md`'s "Updating in a plugin" gains a verification step:**
  run `just --list` before considering the pull done. A toolkit version that
  requires a consumer-side change — the `prerelease` recipe was one — makes
  `just` refuse to compile *any* recipe, so the breakage is invisible until the
  next unrelated recipe run, which may be days later and will look unrelated.
- **It also states the commit shape:** land the consumer-side fix as its own
  commit, separate from the subtree-pull merge commit. The merge commit is
  toolkit content; the fix is the consumer repo's own.
- **Nothing else is added.** The rest of the memory entry is already there and
  was checked against the file: migration notes and the crossed-range printing,
  the pre-dist leaked-environment cleanup, the ref-refusal rules, the
  `precommit`/`prerelease` contract including the literal
  `unknown dependency prerelease`, the release commit convention, the
  last-released rule, first-release-with-no-bump, and `origin/HEAD` branch
  detection. Duplicating any of it into memory was the original error.
- **The root `README.md` carries the same install and update instructions**, so
  a change to the update flow lands in both files. CLAUDE.md's Layout section
  states this; it is easy to miss because only one of the two ships.

## Constraints

- The README is consumer-facing and ships in the `dist-` tree. It describes what
  a plugin maintainer does, not what this repo's own maintainer does.
- Keep it under the 400-line cap and let `just format-docs` wrap it.

## Rejected approaches

- **A `plugin-craft` skill.** Wrong audience: that plugin gets a marketplace
  row, so its skills ship to anyone who installs it, while this content is about
  one private toolchain — `MARKETPLACE_DIR`, the ddaanet marketplace repo, a
  specific source checkout path. Someone installing plugin-craft to write a hook
  would receive a skill about infrastructure they cannot use.
- **Keeping it in memory.** The README is routed by the human asking to install
  or update the toolkit, with the vendored tree already present. That is the
  moment the fact applies, and the artifact is already open.

## What stays out of the README

- `edify` not vendoring the toolkit, and why. That is a scope boundary of this
  repo, owned by `docs/design.md` "Limitations" — see CLAUDE.md's non-goals. A
  consumer manual is the wrong place for it.
- The `git subtree` root-tree mechanism (a `subtree split` dist ref is needed to
  ship a subdirectory). `docs/references/distribution.md` owns the argument. The
  general lesson is worth publishing somewhere broader, but not here.

## First install is out of scope

How a first install is invoked — today a `git ls-remote`, a `git clone` to a
temp dir, then `bash /tmp/cpd/toolkit/install.sh` — is an open design question.
`toolkit/README.md` cannot reach that moment anyway: the tree it lives in does
not exist yet. Settle the invocation separately; nothing in this brief depends
on the answer.
