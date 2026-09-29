# Research: probes behind the dogfood-launcher outline

2026-09-26. Probes run from this repo against rsync 3.4.1 (Linux) and the Claude
Code 2.1.283 bundle.

## Q1 — does a symlinked `--plugin-dir` escape the check? No

Claude Code flags a path as under an inline plugin root with a function
(minified `BRo`) that takes every `--plugin-dir` and `--plugin-dir-no-mcp`
entry, joins it to the cwd, and converts both the roots and the edited path with
`QS` before an is-under test. `QS` walks up to the nearest existing ancestor and
calls `nm`, which is `fs.realpathSync.native`. A `dist/plugin` symlink therefore
resolves to the source tree, and the source is flagged exactly as if it were
loaded directly. **A real copy is required.** This comes from reading the
bundle, not from a launch. The execution probe (outline item 1) observes it once
as a side effect.

## Constraint — the brief's suggested source set fails twice

`git ls-files -z -co --exclude-standard | rsync -a --delete --from0 --files-from=- src/ dst/`,
with and without `-r`, on a fixture:

- **Deletions do not propagate.** After `rm a/y; rm -r b`, both `dst/a/y` and
  `dst/b/z` remained.
- **A deleted tracked file breaks every sync.** `ls-files -c` still lists a path
  that was deleted from the worktree but is still in the index, so rsync exits
  23 with `link_stat … No such file or directory` until the deletion is
  committed. In the hook that is a false stale-copy alarm on every call.

## Chosen source set — whole tree minus git-ignored paths

```sh
git ls-files -z -o -i --exclude-standard --directory \
  | <escape rsync wildcards [ ] * ? \ ; anchor with leading /> \
  | rsync -a --delete --delete-excluded --from0 \
      --exclude=.git --exclude=/dist/plugin/ --exclude-from=- ./ dist/plugin/
```

Fixture results:

- Ignored dirs and patterns (`junk/`, `*.log`, `/we*`) are excluded.
- A tracked file matching an ignore pattern (`git add -f "a/we[ir]d*"`) is kept,
  because `-o -i` lists only untracked ignored paths.
- Names with spaces and glob characters survive.
- `rm a/y; rm -r b` propagates, a new untracked file is copied, and rsync exits
  0.

The fixture used GNU `sed -z` for the escaping step. macOS sed has no `-z`, so
the shipped script needs a portable escaper.

## Q2 — cost of a no-op sync, for matching `Bash`

Five no-op runs of the chosen command, averaged. The time includes
`git ls-files`.

| repo | files | size | no-op ms |
|------|------:|-----:|---------:|
| craft | 139 | 892K | 68 |
| cwd-safety | 156 | 1.1M | 60 |
| edify (repo root) | 649 | 6.0M | 72 |
| handoff | 368 | 3.7M | 108 |

At about 0.1 s per Bash call, the brief's default applies and the matcher
includes `Bash`. Each repo also printed `skipping non-regular file ".mcp.json"`:
that is the sandbox's char-device mask (`sandbox-effects`), and rsync still
exits 0.

## Not probed here — Q3, Q4

Whether a project `PreToolUse` deny lands before the path-safety `ask` (Q3), and
whether project `PostToolUse` hooks fire for subagent tool calls (Q4), both need
an unsandboxed nested `claude` launch. Neither answer changes the architecture;
each has a fallback in the outline. Both are probed as the first execution item.
