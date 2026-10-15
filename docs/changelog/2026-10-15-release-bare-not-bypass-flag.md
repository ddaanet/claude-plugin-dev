# 2026-10-15 — The release recipes are issued bare, not with the bypass flag

A brief from a `sandbox-lies` session that cut a plugin's first release found
that `check_marketplace_writable` told the reader to rerun the Bash call with
`dangerouslyDisableSandbox`. Under Claude Code auto mode the classifier denied
that call as a safety bypass, before anything started. The same recipe issued
alone in the call, with `"just release *"` in `sandbox.excludedCommands`, ran to
completion.

## What changed

- The `check_marketplace_writable` refusal in `toolkit/release.sh` now names the
  route that passes: `"just release *"` and `"just resume-release *"` in
  `sandbox.excludedCommands`, the recipe issued bare, and the `/add-dir` advice
  kept. It no longer names the bypass flag.
- `resume-release` reaches the same refusal at the marketplace bump, so the
  message names both entries. How `excludedCommands` matches a pattern was not
  verified here; both entries are spelled out rather than a pattern covering
  both.
- `tests/release-test.sh` asserts the exclusion route and the `resume-release`
  entry, and asserts the flag is absent.
- `toolkit/README.md` gains a Conventions bullet on issuing the recipes bare.

## Not done here

The `plugin-craft:toolkit-release` skill needs the same sentence; it lives in
another repository and is flagged, not edited. No design doc stated the old
advice, so none changed.
