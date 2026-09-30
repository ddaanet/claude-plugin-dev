# Outline: dogfood launcher loads the plugin from a synced copy

## Provenance

- **Derived from:** none — requirements input is
  `plans/2026-09-26-brief-dist-copy-dogfood-launcher.md`
- **Base:** `389e8b02cbbd19e8fa266175e293c5bc36323966`

## Approach

The toolkit ships a `claude` shim. The shim syncs the consumer's plugin tree
into `dist/plugin/`, exports `CLAUDE_CODE_PLUGIN_DIRS=<repo>/dist/plugin`, and
execs the next `claude` on PATH. Agents edit the source tree, which is outside
every loaded root, so edits there never hit the path-safety `ask`.

The copy changes only when someone promotes it on purpose:

- at launch, which includes a `handoff:restart` relaunch through the shim;
- by `just dogfood`, which syncs and nothing else, followed by
  `/reload-plugins`.

Two project hooks, wired by `install.sh`, complete it:

- a `PreToolUse` guard refuses edits aimed at the copy and names the source path
  instead;
- a `SessionStart` check reports a session not running the copy, and a missing
  `jq`.

Every consumer adopts the shim. The four hand-copied `.bin/claude` shims (craft,
cwd-safety, handoff, sandbox-lies) are replaced, and the other consumers gain
it.

Probe evidence is in `reports/research-probes.md`. This outline replaces an
earlier revision built on sync-on-edit hooks. My human partner rejected that
design in review: it cost a sync on every tool call, and it made half-edited
hook scripts live in the session editing them.

## Key decisions

1. **A real copy, not a symlink.** Claude Code resolves each inline root through
   `realpath` before comparing paths, so a symlinked root flags the source
   (research Q1).
2. **Source set: the whole plugin tree minus git-ignored paths.**
   `git ls-files -z -o -i --exclude-standard --directory` lists what to leave
   out. Each entry is anchored with a leading `/` and fed to
   `rsync -a --delete --delete-excluded --from0 --exclude-from=-`, along with
   hard excludes for `.git` and `/dist/plugin/`:
   - `.git` is unanchored, so a nested repo's `.git`, such as the `memory/`
     gitlink's, stays out too.
   - `/dist/plugin/` is the copy itself, excluded so a sync never recurses into
     it even when `dist/` is not ignored. Other build output under `dist/` is
     expected to be git-ignored and drops out through the ignore list.

   Entries are not escaped. An entry containing an rsync pattern character (`*`,
   `?`, `[`, `]`) or a backslash aborts the sync, naming the path: rsync would
   read it as a pattern, and escaping is inconsistent, since a backslash counts
   as an escape only in a pattern that also holds a wildcard (probed on rsync
   3.5.0). `--directory` collapses a wholly ignored directory to one entry, so
   the check sees only top-level ignored names; none of the consumers has one.
   The brief's `--files-from` list is rejected: it neither propagates deletions
   nor survives a tracked file deleted in the worktree (rsync exit 23).
3. **Plugin root = repo root.** `install.sh` refuses a repo without a root
   `.claude-plugin/plugin.json`, and `release.sh` assumes one, so every toolkit
   consumer has the root layout. Nested roots (edify's `plugin/`) are OUT.
4. **Sync only on deliberate promotion.** The triggers are launch through the
   shim and `just dogfood`. The trade-off follows from what Claude Code
   re-reads, and when (`plugin-craft:verifying-plugin-changes`):
   - Skill bodies need `/reload-plugins` anyway.
   - Agent definitions and hook events need a restart, which goes through the
     shim.
   - Only hook-script and `bin/` bodies are read on every call. Syncing those on
     every edit would run half-edited code in the session doing the editing.

   So there is no `PostToolUse` sync, no liveness marker and no lock. A
   concurrent sync that trips over another one fails loudly (decision 8) and
   succeeds on re-run. This also settles two of the brief's open questions:
   - **OQ2, changes made through Bash:** a promotion syncs the whole tree,
     however it changed, so no `Bash` matcher is needed.
   - **OQ4, subagent coverage of `PostToolUse`:** moot, with no `PostToolUse`
     hook.
5. **`toolkit/dogfood.sh`, one script with three subcommands.** Each finds the
   repo root from its own location (`<script dir>/..`), never from
   `CLAUDE_PROJECT_DIR` or the payload `cwd`. A resumed `SessionStart` can carry
   a foreign cwd (`sessionstart-resume-cwd`).
   - `sync` runs decision 2's rsync.
   - `pre-tool` is the copy guard (decision 6).
   - `session-start` is the check (decision 7).
6. **Copy guard: deny, don't rewrite.**
   - **Trigger:** `pre-tool` runs on `Write|Edit|NotebookEdit`.
   - **Path read:** the edited path is
     `.tool_input.file_path // .tool_input.notebook_path`, because
     `NotebookEdit` names its target `notebook_path` (CC 2.1.283 bundle).
   - **Rule:** any such path under `<root>/dist/plugin/` is denied,
     unconditionally. That path is always the copy, so no marker is needed.
   - **Spelling:** the comparison is made on physical paths. `<root>` is
     resolved with `pwd -P`, and the edited path by resolving its nearest
     existing ancestor the same way, as Claude Code's own check does (research
     Q1). A symlinked repo path would otherwise let a copy edit through.
   - **Without `jq`:** `pre-tool` exits 0 with no output, since it cannot read
     the payload. The path-safety `ask` still stops a copy edit, and
     `session-start` has already reported the missing `jq`. (Decision added in
     review.)
   - **Channels:** the deny splits three ways (`plugin-craft:hook-authoring`).
     The verdict goes on `permissionDecisionReason`, the mapped source path on
     `additionalContext`, and one curt line on `systemMessage`.
   - **Rejected:** an `updatedInput` rewrite to the source path. It hides the
     mapping, so the agent keeps aiming at the copy.
7. **`session-start` reports on `systemMessage`, and on `additionalContext` for
   a session not running the copy:**
   - `CLAUDE_CODE_PLUGIN_DIRS` has no entry naming `<root>/dist/plugin`. The
     session was launched past the shim (no direnv, the IDE or desktop app, an
     absolute path to `claude`), or it inherited another repo's value. The test
     splits the variable on `:` and compares each entry whole, both sides
     resolved with `pwd -P`: Claude Code writes the variable back normalized, so
     a raw string match would warn on every session from a symlinked path, and a
     substring match would accept `/other/<root>/dist/plugin`. The same finding
     goes to the agent on `additionalContext`, stated as fact: this session does
     not load `<root>/dist/plugin`, so plugin behaviour observed in it is not
     the promoted copy's.
   - `jq` is missing. This message is a static string, since jq cannot build it.
     It stays user-only; the agent has nothing to do about it.

   There is no adoption check. Every consumer is meant to use the shim, so the
   warning is the nudge until it does. The check is silent when neither
   condition holds. When it speaks, the line opens with an ANSI reset so it is
   not dimmed like routine hook output (`hook-output-channels`).
8. **Sync failure is loud.** A failed sync at launch aborts before exec.
   `just dogfood` exits non-zero with rsync's stderr. The script never redirects
   rsync's stderr, not even to hide the `skipping non-regular file` noise from
   the sandbox (`no-stderr-suppression`). That line is harmless except for
   `.mcp.json` (Risks).
9. **Shim: `toolkit/bin/claude`**, a bash script, put on PATH by the consumer's
   `.envrc` as `PATH_add plugin-dev/bin`.
   - **Root:** it finds the root from its own directory (`<shim dir>/../..`,
     since the shim is `<root>/plugin-dev/bin/claude`). The manifest and ignore
     checks live in `dogfood.sh sync`, which refuses unless
     `<root>/.claude-plugin/plugin.json` exists and `dist/plugin` is git-ignored
     (`git check-ignore`), so `just dogfood` enforces them too.
   - **Before exec:** it runs `dogfood.sh sync`, then exports
     `CLAUDE_CODE_PLUGIN_DIRS=<root>/dist/plugin`, overwriting any inherited
     value, and `unset CDPATH`.
   - **Chaining:** PATH stripping follows sandbox-lies's shim. It drops an entry
     when that entry's `claude` is the shim itself (`-ef`), not when the name
     matches, and passes an explicit `-` to `paste`. It then execs the next
     `claude`, typically gitlore's launcher.
   - **Variable over flag:** using `CLAUDE_CODE_PLUGIN_DIRS` rather than
     `--plugin-dir` makes the variable reach hooks and child processes, which
     decision 7 checks. In 2.1.283 the variable takes a `:`-separated list of
     absolute local paths, which Claude Code normalizes and writes back into its
     own environment.
   - **Subdirectories:** there is no refusal. A launch from a subdirectory loads
     the copy, because the path is absolute, but the root's project hooks do not
     fire there: Claude Code reads project settings from the launch directory
     only (probed on CC 2.1.284, `reports/probe-subdir-hooks.md`). The README
     says to launch from the repo root.
10. **`just dogfood`** is a `release.just` recipe,
    `bash "{{toolkit_prefix}}/dogfood.sh" sync` like its neighbours. It starts
    no `claude`. Its doc comment is one line. It depends on no gate.
11. **`install.sh` wires `.claude/settings.json` only.**
    - **Refactor:** step 3's idempotent jq block becomes a function of (event,
      matcher, command), called for version-guard and for two new entries.
    - **New entries:** `PreToolUse` on `Write|Edit|NotebookEdit` runs
      `pre-tool`, and `SessionStart` (no matcher) runs `session-start`.
    - **Idempotency:** an entry counts as present when an entry under the same
      event carries the same command, whatever its matcher (a missing `matcher`
      included).
    - **Quoting:** the new commands quote the variable,
      `bash "${CLAUDE_PROJECT_DIR}/plugin-dev/dogfood.sh" pre-tool`, so a repo
      path with a space survives the hook shell. version-guard's string is left
      as is, since changing it would make a re-run add a duplicate.
    - **Documented, not edited:** `.envrc`, `.gitignore` (`/dist/plugin/`) and
      the consumer's `clean` recipe, which must spare `dist/plugin/`. These go
      in `toolkit/README.md`.
12. **Migration note `toolkit/migrations/vX.Y.Z.md`.** `update.sh` does not
    re-run `install.sh`, so the note carries the steps. It says:
    - re-run `bash plugin-dev/install.sh`;
    - delete any `.bin/claude`, its `PATH_add .bin`, and any recipe line that
      names it (craft's `precommit` shellchecks `.bin/claude`, so its gate fails
      otherwise);
    - add `PATH_add plugin-dev/bin` after `PATH_add .gitlore/bin` (the last one
      wins, so the shim runs first), then `direnv allow`;
    - ignore `/dist/plugin/`, and make `clean` spare it.

    Breaking the old shims is acceptable (`plugin-dev-no-backcompat`). Name the
    file for the release that ships it, once the bump is chosen: for example
    `v0.9.0.md` for a minor bump from `0.8.0`. `update.sh` prints notes in the
    range (old, new], so a misnamed note is skipped.

## Probed during review — Q3 and the premises

A project `PreToolUse` deny lands before the path-safety `ask`: the denied
Edit's tool result is the hook's reason, and its `additionalContext` reaches the
agent tied to the denied call. The copy loads through `CLAUDE_CODE_PLUGIN_DIRS`,
hooks see the variable, a source edit goes through, and the copy is flagged as
sensitive. The fallback is not needed. Claude Code prefixes the reason with
`PreToolUse:<Tool> hook error:`, so D6's wording is written to read after it.
Evidence and the re-run procedure are in `reports/probe-hooks.md` (CC 2.1.284);
the subdirectory result is in `reports/probe-subdir-hooks.md`.

## Items

Per `/runbook`: tdd = behavioural and test-driven; general = docs and wiring
prose.

1. **tdd**: `dogfood.sh sync`, in new suites `tests/dogfood-sync-test.sh` and
   `tests/dogfood-sync-refusal-test.sh`. The first two cases are red against the
   naive `--files-from` sync:
   - a deletion propagates;
   - a deleted-but-tracked file does not fail the sync;
   - ignored paths stay out;
   - names with spaces survive;
   - an ignored entry holding a pattern character (`*`, `?`, `[`, `]`) or a
     backslash aborts the sync, naming the path;
   - `.git`, a nested repo's `.git` and `dist/plugin/` are excluded, so a sync
     never recurses into the copy;
   - it refuses without a root `.claude-plugin/plugin.json`, and when
     `dist/plugin` is not git-ignored;
   - an rsync failure exits non-zero with its stderr intact.
2. **tdd**: `dogfood.sh pre-tool` and `session-start`, in suites of their own
   (`tests/dogfood-pre-tool-test.sh`, `tests/dogfood-session-start-test.sh`):
   - `pre-tool` emits the three-channel deny JSON with the mapped path, for both
     `file_path` and `notebook_path` payloads;
   - `pre-tool` allows source paths and paths outside the repo;
   - `pre-tool` denies a copy path spelled through a symlink to the repo;
   - `pre-tool` exits 0 silently with no `jq` on PATH;
   - `session-start` is silent when the variable contains the copy, including as
     one entry of several and in a symlinked or trailing-slash spelling;
   - `session-start` warns when the variable is unset, names another repo's
     copy, or holds the copy path only as a substring of a longer entry, on both
     `systemMessage` and `additionalContext`;
   - `session-start` warns about a missing `jq`, using a PATH without it, on
     `systemMessage` only.
3. **tdd**: `toolkit/bin/claude`, in a new suite
   `tests/dogfood-launcher-test.sh`, with a stub `claude` further down PATH. It
   checks:
   - the exact exec argv;
   - `CLAUDE_CODE_PLUGIN_DIRS` overwrites an inherited value;
   - own-entry stripping, including a trailing-slash spelling;
   - a launch from a subdirectory still resolves the root and execs;
   - aborts, without exec, when `sync` fails;
   - exit 127 when no next `claude` is found.
4. **tdd**: the `install.sh` wiring, extending
   `tests/update-plugin-dev-test.sh`'s scenario "install.sh: wires into an
   existing settings.json without replacing it", which already owns install.sh's
   settings assertions. Cases:
   - the two entries are added once;
   - a re-run is a no-op;
   - existing settings are preserved;
   - an entry with no `matcher` is still handled;
   - the new commands carry the quoted `"${CLAUDE_PROJECT_DIR}"`.

   The suite is already 406 lines, over the soft 400 cap, and already holds
   install.sh scenarios beside update.sh's. The cases are added compactly;
   moving install.sh's scenarios into a suite of their own is a separate
   cleanup, not this job's.
5. **general**: the `release.just` `dogfood` recipe and shipped-tree
   bookkeeping:
   - `_import-check` still passes, and pins `dogfood` the way it pins
     `resume-release`: `--dry-run dogfood` reaches `dogfood.sh" sync` and runs
     no stub gate, and its closing recap line names `dogfood`;
   - `tests/dist-tree-test.sh`'s list gets `dogfood.sh` and `bin/claude`. The
     migration note needs no list entry, since the test already admits any
     `migrations/vX.Y.Z.md`;
   - `justfile`'s `precommit` shellchecks the new scripts, runs `bash -n` on the
     new suites, and runs them;
   - CLAUDE.md's Layout and Quality gate name the new files and suites, and its
     list of `docs/references/` nodes gains `dogfood`.
6. **general**: docs and the migration note:
   - `toolkit/migrations/vX.Y.Z.md`, with decision 12's content, named for the
     planned bump;
   - a `toolkit/README.md` dogfood section covering `.envrc`, `.gitignore`,
     `clean`, `just dogfood`, `/reload-plugins` versus a restart, and the
     `SessionStart` warnings, plus the instruction to launch from the repo root,
     since project hooks do not fire from a subdirectory
     (`reports/probe-subdir-hooks.md`), and the `.mcp.json` caveat (Risks);
   - `toolkit/README.md`'s Contents gains `dogfood.sh` and `bin/claude`, and its
     Requirements gains `rsync`;
   - the root `README.md`'s "What a consumer plugin gets" gains the shim and
     `just dogfood`. The dogfood section stays out of the two install/update
     sections, whose command blocks `tests/doc-sync-test.sh` requires in both
     READMEs;
   - a Requirements bullet and a decision group in `docs/design.md`;
   - a new node, `docs/references/dogfood.md`, holding the arguments above,
     including why sync-on-edit was rejected, and the two probe results with
     their CC version;
   - a changelog entry.

## Scope

IN:

- `dogfood.sh`, the shim, the `install.sh` wiring and the `dogfood` recipe
  (items 1–5);
- tests and shipped-tree bookkeeping (items 1–5);
- docs and the migration note (item 6, decision 12).

The Q3, premise and subdirectory probes ran during review; their reports are
inputs, not deliverables.

OUT:

- **Nested plugin roots, and edify.** edify decides its own port;
  `edify-release-flow` says it vendors nothing.
- **Editing consumer repos.** They stay read-only and migrate by the note when
  they next update.
- **Removing gitlore's `GITLORE_AUTO_CLAUDE_PLUGIN_DIR`**, which adds
  `--plugin-dir .` and would reload the repo root on top of the copy. That
  change belongs to gitlore and is handed over as the brief
  `gitlore/inbox/2026-09-29-brief-remove-auto-plugin-dir.md`. The shim does not
  work around it. Among the consumers only gitlore's own `.envrc` sets the
  variable, and the brief sequences its removal with gitlore adopting the shim,
  so no consumer need run both.
- **Editing consumers' `.envrc`, `.gitignore` or `clean` from `install.sh`.**
- **Hot-reloading skills, agents or hook events.**
- **Cutting the toolkit release.** That is a separate, user-triggered
  `just release`.

## Risks

- **Claude Code drift.** A future version might stop resolving roots through
  `realpath`, change how `CLAUDE_CODE_PLUGIN_DIRS` is parsed, or flag paths
  differently. The procedure in `reports/probe-hooks.md` is the regression check
  to re-run; its results were taken on CC 2.1.284.
- **macOS rsync is unprobed.** The research ran rsync 3.4.1 on Linux. Recent
  macOS ships `openrsync` as `/usr/bin/rsync`, and older versions ship rsync
  2.6.9. Whether either accepts `--from0`, `--exclude-from=-` and
  `--delete-excluded` together is not established. The first check is the suite
  run on a macOS consumer. If it fails, the README names a Homebrew rsync as a
  requirement, and `sync` fails loudly with that message.
- **Benign rsync exits read as failures.** A file vanishing mid-sync makes rsync
  exit 24, and two concurrent syncs can collide. Both are reported (decision 8)
  and repaired by a re-run. They are accepted as rare false alarms rather than
  matched and hidden.
- **The copy lags the source by design.** A session tests what was last
  promoted, not the working tree. The README says so, and a Read through a copy
  path returns promoted content.
- **A sandboxed sync cannot read `.mcp.json`.** The command sandbox masks a set
  of dotfiles in the project root (`sandbox-effects`), and `.mcp.json` is the
  one plugin component among them. Probed with rsync 3.4.1: a char-device mask
  prints `skipping non-regular file`, exits 0, and leaves the copy's existing
  `.mcp.json` untouched, so a changed MCP config goes stale silently. The
  zero-byte mask shape, unprobed, would copy an empty file. This bites only a
  `just dogfood` run through the agent's sandboxed Bash; the shim runs in the
  user's shell. No consumer tracks a `.mcp.json` today. The README says that a
  plugin which does must run `just dogfood` from the user's own shell.
- **Subdirectory launches run without the hooks.** Claude Code reads project
  settings from the launch directory only (`reports/probe-subdir-hooks.md`), so
  such a session has neither the copy guard nor the `SessionStart` warning. A
  copy edit still meets the path-safety `ask`. Accepted, with no refusal
  (decision 9); the README says to launch from the root.
- **Promotion is repo-wide.** Hook-script and `bin/` bodies are read on every
  call, so a launch or `just dogfood` in one session changes what every other
  live session in the same repo runs.
- **Children inherit the variable.** A `claude` started from a dogfood session's
  Bash (a probe, an eval) loads this repo's copy too, unless it goes through a
  shim that overwrites it. Its own `session-start` reports the mismatch when it
  runs in another consumer.
- **Only tool edits to the copy are guarded.** A Bash write into `dist/plugin/`
  passes the guard and the path-safety check alike, and the next sync overwrites
  or deletes it.
- **The copy carries non-plugin content.** Directories such as `plugin-dev/` and
  the `memory/` gitlink's files land in `dist/plugin/`. Claude Code loads only
  the plugin component directories, so this costs bytes, not behaviour. The Q2
  timings already include it.
