## Brief: dist branch release support (claude-plugin-dev)

2026-10-15

### Decisions

- Add opt-in dist-branch publishing to the toolkit's release flow (`release.sh`,
  `--resume`). Plugins that don't opt in behave exactly as today.
- Opt-in is a per-plugin allowlist of shipped paths, kept at the repo root and
  outside the shipped tree (suggested name: `dist.include`, one path or
  directory per line).
- On `just release`, after the source commit and `vX.Y.Z` tag:
  1. Build a tree from the release commit containing only the allowlisted paths.
     Use plumbing: a temp `GIT_INDEX_FILE`, `read-tree`, filter, `write-tree`.
  2. `commit-tree` it with the current `dist` tip as parent. The first release
     on dist is a root commit.
  3. Use the commit message `dist vX.Y.Z from <source-sha>`.
  4. Push the `dist` branch and a `dist-vX.Y.Z` tag. That tag naming matches the
     toolkit's own `dist-vX.Y.Z` convention.
- When dist is enabled, the release step that bumps the plugin's entry in
  `$MARKETPLACE_DIR` must also set the entry's source ref to `dist`.
- `dogfood.sh sync` uses the same allowlist when present, so dogfooding loads
  exactly the shipped tree and a path missing from the list shows up locally.
- First consumer: ddaanet/handoff, being renamed to `autodrive-handoff`. gitlore
  and the other plugins can adopt it later.

### Constraints

- The Anthropic plugin directory (claude.ai/directory/manage) validates the
  plugin folder, which is the repo root for these plugins. Rules that matter
  here:
  - A git submodule (gitlink) anywhere in the plugin folder **blocks**
    submission. Handoff's gitlore `memory` submodule is the reason for this
    whole change.
  - `export-ignore` or `export-subst` in any `.gitattributes` makes validation
    stop. So no export-ignore-based filtering, ever.
  - More than 512 files, or any non-image file over 256 KiB, sends the plugin to
    a reviewer. So do symlinks and binaries other than PNG/JPEG/GIF/WebP and
    fonts.
  - The plugin needs a README of at least 40 words, and a LICENSE file or
    `license` in plugin.json.
- Before pushing, the build must refuse a dist tree that contains a gitlink
  (mode 160000) or a symlink, or that lacks `.claude-plugin/plugin.json`.
- Run `claude plugin validate --strict` on the built tree before pushing
  (extract it to a temp dir with `git archive`). A failure aborts with nothing
  pushed.
- `--resume` must detect and finish a half-done dist step (tree built but not
  pushed, branch pushed but tag missing) and stay a no-op when everything
  already landed.
- The directory follows a branch, not a tag: a tracked tag would need a manual
  edit in the portal every release. So `dist` must only move forward: never
  force-push it, one commit per release.

### Rejected approaches

- **`git subtree split`:** it needs the shipped files under one prefix, and
  these plugins ship from the root.
- **Moving the plugin into a subfolder:** the directory applies stricter script
  rules to subfolder plugins. Hook scripts may only use `${CLAUDE_PLUGIN_ROOT}`
  (no other shell variables, command substitutions or calls to other plugin
  files), and non-shell files run by a hook, such as a `.ts` mod, are held.
  Handoff would be held on every version.
- **A denylist:** a new dev file would ship silently.
- **Tracking a `dist-v*` tag in the directory:** that would mean a manual portal
  edit per release.

### Additional context

- Check that marketplace `url` sources accept a `ref` field. Run
  `claude plugin validate` on the marketplace repo after the change.
- After the toolkit release, consumers pick it up with `just update-plugin-dev`.
  Add a migration note saying how to opt in: create the allowlist, then the
  first release creates `dist`.
- Handoff's intended allowlist, for a test fixture: `.claude-plugin/`,
  `skills/`, `hooks/`, `scripts/`, `bin/`, `README.md`, `LICENSE`.
