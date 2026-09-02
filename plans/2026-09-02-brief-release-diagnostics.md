# Brief: release.sh messages carry the diagnosis and the next command

2026-09-02

Turn the operational lore around `release` and `resume-release` — currently held
in ddaanet memory as `claude-plugin-dev-release` — into output the scripts emit
at the moment of failure.

## Decisions

- Every `die` on a path where the tree state is non-obvious, or where a release
  may already be partly public, states what was checked, what is exempt, and the
  exact next command. This generalizes a shape the script already uses in three
  places rather than inventing one: line 54 (`/add-dir` on a marketplace write
  refusal), line 146 (`just resume-release` on version drift), line 274 (resume
  hint after a refused push).
- **`tree_is_clean "."` at line 98.** `die "uncommitted changes"` is bare today,
  which is the whole reason the memory fact exists. It must print the offending
  paths and name the two exemptions — `.claude`, and the gitlore memory mount
  read from `.gitmodules` by submodule name — so the message cannot be read as
  the checker being wrong about a staged handoff frame.
- **The `MARKETPLACE_DIR` clean check at line 137** gets the same treatment, and
  matters more: it fires at the last step, after the commit, tag, push and
  GitHub release are already public, so an unrelated dirty file there strands a
  half-done release. Say that, and name `just resume-release`.
- **The first-release refusal at line 173** states the remedy, not just the
  refusal: set the version in `plugin.json` and re-run with no bump argument.
- **The version-drift die at line 193** states the invariant it is protecting —
  the manifest holds the *last released* version, not the next one.
- **The messages are the documentation.** Anything an agent needs at one of
  these failures goes in the message, not in a memory file. The message ships
  with the vendored tree, reaches every consumer including those with no memory
  store, and cannot drift from the check it guards.

## Constraints

- `die()` prints one line to stderr and exits 1. Multi-line guidance follows the
  existing pattern — a separate `printf ... >&2` immediately before the `die` —
  rather than embedding newlines in `die`'s argument.
- **Do not soften a refusal into something an agent reads as permission to
  bypass.** No "you can run X to skip this". Same rule the version-guard hook's
  deny message follows; see CLAUDE.md, "Hook output is dual-channel".
- Paths printed from the diff must be NUL-delimited (`git diff -z --name-only`)
  and read with `read -r -d ''`. A path with a space is one path.
- `tests/release-test.sh` greps message text in several scenarios. Extending a
  message must keep those matching, or update the assertion deliberately in the
  same change.
- shellcheck-clean, and `just precommit` green.

## Rejected approaches

- **Leaving the lore in ddaanet memory.** It is reachable only from a machine
  that mounts the tier, and only when an index line happens to match the string
  the failure printed. The consumer that hits this is often a plugin repo with
  no memory store at all. The script is present in every one of them.
- **A `docs/` page.** Nothing routes an agent to a document at the moment a
  release dies mid-flight, and the `dist-` tree ships no `docs/`.

## Source facts to absorb

From `memory/ddaanet/claude-plugin-dev-release.md`, which is retired once this
lands:

- `error: uncommitted changes` names real work; only `.claude` and the memory
  mount are exempt; `.claude-plugin` is *not* — git pathspecs match at the path
  separator, so a dirty manifest still refuses. Anything staged under `.claude`
  rides the release commit.
- A release that dies at the marketplace bump has already published the version
  commit, tag, branch push and GitHub release. The recovery is
  `just resume-release`, which is idempotent because every step probes what
  already landed. Never retry from the top.
- The marketplace push is refused by the auto-mode classifier as an external
  repo outside the trusted source-control org until `/add-dir` has been run on
  that repo. Line 54 already carries this conditionally; check whether the
  unconditional case needs it too.
- A consumer whose vendored `plugin-dev/` predates the `.claude` exclusion still
  refuses on a staged frame. Its own `tree_is_clean` is the authority — which is
  an argument for the message naming the exemptions it actually applied, rather
  than a fixed list.
