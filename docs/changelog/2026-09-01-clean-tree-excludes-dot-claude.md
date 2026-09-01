# 2026-09-01 — The clean-tree check exempts `.claude/`

The `handoff` and `precompact` skills write a task frame to
`.claude/handoff-task.md` and `.claude/handoff-todo.md` and stage it for whatever
commit lands next. A release is a commit that lands next — but `common_preflight`
runs its clean-tree check *before* making that commit, so the staged frame read
as uncommitted work and the release died on `error: uncommitted changes`. The
message names neither the frame nor the skill that left it, so the symptom is
plausible-looking and misleading: it invites a hunt for real work that isn't
there. The standing remedy was to land the frame in a commit of its own before
starting a release, which is discipline standing in for a gate.

`tree_is_clean` now excludes `.claude` alongside the memory gitlink it already
excluded, in the plugin repo and in `MARKETPLACE_DIR` alike.

Nothing under `.claude/` is plugin content — a plugin ships `.claude-plugin/` and
the component directories beside it, while `.claude/` is what the maintainer's
own sessions read — so a release that does not stop for it skips over nothing it
publishes. Whatever is staged there rides the release commit, which is what the
frame was staged for in the first place.

Excluded whole rather than by filename. Which files appear under `.claude/` is a
function of which skills the maintainer runs — the two handoff frames today,
`gitlore-memory-message` and `settings.local.json` beside them — and an
enumeration inside the toolkit would track a list it does not own. That is a
different judgement from the memory exclusion's deliberate narrowness, and the
reason differs too: there the risk was exempting *other* people's submodules,
here the excluded directory is fixed and never released. The cost accepted is
that an edit to `.claude/settings.json` — the version-guard wiring — no longer
stops a release. It stays in the tree either way, reaches no consumer, and the
next commit picks it up.

`.claude-plugin/` shares the excluded prefix and holds the manifest the whole
release turns on. Git pathspecs match at the path separator, so `:(exclude).claude`
leaves it alone. Verified directly in a scratch repo before writing the pathspec,
and then pinned by a scenario that dirties the manifest *with a frame staged at
the same time* — the decoy has to be dirty in the same run as the exemption, or
it only proves that a clean thing stays clean.

Three scenarios added, the first two confirmed red against the unfixed script
with the exact refusal from each call site: a staged frame in the plugin repo, a
staged frame in the marketplace repo, and the `.claude-plugin` decoy. The
plugin-repo one also asserts that HEAD after the release is the release commit
*and* that it names the frame — both halves, because a refused release leaves
HEAD at the frame's own commit, which names the frame trivially. Asserting only
the second would have passed in the red run.

This repo's own self-release recipe in the root `justfile` had the same gap and a
wider one: its check carried no exclusions at all, so a resting memory gitlink
also refused it. It now excludes `.claude` and `memory` as literal pathspecs. No
`.gitmodules` lookup there — it runs against one known repo, so discovery would
answer a question with no second answer, and the recipe is deliberately bespoke
rather than consumer-shaped.
