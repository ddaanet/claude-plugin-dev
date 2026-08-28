## Brief: the subtree squash leaks the toolkit's whole working environment, not just `memory`

2026-08-13

Companion to `brief-subtree-squash-leaks-memory-submodule.md` (2026-08-12,
found from the `handoff` consumer). That brief's root cause is correct and is
not restated here. This one adds a wider surface it missed, corrects two of
its severity claims against a reproducible fixture, and names a gap in the
reachability of the v0.5.2 fix.

Found upgrading the `gitlore` consumer from v0.5.0 straight to v0.5.3.

### Decisions

- **The gitlink is not the only thing the squash carries over.** After
  `just update-plugin-dev v0.5.3`, the consumer's tree contains the toolkit's
  own working environment, all of it tracked in the consumer's history:

  ```
  plugin-dev/.claude/settings.json
  plugin-dev/.claude/handoff-task.md
  plugin-dev/.claude/handoff-todo.md
  plugin-dev/.claude/gitlore-hook-setup
  plugin-dev/.envrc
  plugin-dev/.gitignore
  plugin-dev/.gitlore/bin/claude
  ```

  `handoff-task.md` is a task snapshot describing whatever the toolkit
  maintainer was mid-way through; it is now committed in every consumer that
  pulls this tag. A fix scoped to `memory` alone leaves all of this behind.

- **`plugin-dev/.claude/settings.json` is the one with teeth.** Claude Code
  reads `.claude/settings.json` from directories it works in, so a consumer's
  agent operating under `plugin-dev/` picks up the toolkit's settings — hooks
  included. The other files are inert clutter; this one changes behaviour.

- **A consumer below v0.5.2 cannot reach the v0.5.2 fix through the recipe.**
  The fix (`-c fetch.recurseSubmodules=no`, scoped to the subtree pull) lives
  in `release.just`, and it is the consumer's *currently vendored* copy that
  executes the upgrade pull. So the pull that would deliver the fix is the one
  that still fails. Crossing the boundary needs the flag supplied from
  outside, once per consumer:

  ```sh
  GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=fetch.recurseSubmodules \
    GIT_CONFIG_VALUE_0=no just update-plugin-dev v0.5.3
  ```

  Verified: the bare recipe died with `fatal: remote error: upload-pack: not
  our ref …` / `Errors during submodule fetch: gitlore-memory`; the same
  command with those three variables set completed. Worth a line in the
  release notes or README, since every consumer still on <0.5.2 hits it.

### Constraints

- Corrections to the companion brief's blast-radius claims, measured on git
  2.47.3 against the fixture below — both matter because they point at
  different fixes:
  - **`git submodule update --init --recursive` does fail**, confirming that
    brief. Note the message differs from `submodule status`'s, so grepping for
    one will not find the other: `fatal: No url found for submodule path
    'vendored/memory' in .gitmodules`.
  - **A fresh `git clone --recurse-submodules` does *not* fail.** It exits 0,
    populates every registered submodule correctly, and leaves the
    unregistered gitlink as an empty directory. Clone enumerates `.gitmodules`
    rather than index gitlinks. The resulting clone then fatals on the *next*
    unscoped `git submodule status` — so the damage is real but lands one step
    later than "breaks a fresh clone" implies.
- Path-scoped calls are unaffected either way: `git submodule status memory`
  and `git submodule update --init -- memory` both succeed. A consumer whose
  own tooling always scopes its submodule calls sees nothing wrong until a
  human runs a bare `git submodule status`.

### Rejected approaches

- **Registering `plugin-dev/memory` in the consumer's root `.gitmodules`.**
  Silences the error by making the toolkit's private memory a real submodule
  of every consumer, which is the opposite of the intent.
- **Consumer-side `git rm --cached plugin-dev/memory`.** This is what `gitlore`
  and `handoff` each did, and it works, but the next `update-plugin-dev`
  re-adds the paths from the tagged tree — so it is a workaround that every
  consumer pays for again on every upgrade, not a fix.

### Additional context

Self-contained fixture reproducing all three behaviours with no network and
no toolkit involved — an unregistered gitlink alongside a registered one:

```sh
set -e
cd "$(mktemp -d)"
git init -q -b main inner && (cd inner && git config user.email e@x \
  && git config user.name E && echo hi > f && git add f && git commit -qm init)
INNER=$(git -C inner rev-parse HEAD)
git init -q -b main parent && cd parent
git config user.email e@x && git config user.name E
echo root > r && git add r
git -c protocol.file.allow=always submodule add -q ../inner registered
git update-index --add --cacheinfo "160000,$INNER,vendored/memory"
git commit -qm "registered + unregistered gitlink"

git submodule status                                      # fatal, exit 128
git -c protocol.file.allow=always submodule update --init --recursive
                                                          # fatal, exit 128
cd .. && git -c protocol.file.allow=always clone -q --recurse-submodules \
  parent fresh                                            # exit 0
ls -A fresh/registered      # populated -> the clone did recurse
ls -A fresh/vendored/memory # empty     -> unregistered gitlink skipped
```

The consumer that surfaced this is `gitlore`, vendored at v0.5.3 via
`Squashed 'plugin-dev/' changes from d0b3a03..3de1862`. `gitlore` mounts its
own top-level `memory` submodule, which is what makes the fetch-time collision
and the squash-time leak both reachable in the same repo.
