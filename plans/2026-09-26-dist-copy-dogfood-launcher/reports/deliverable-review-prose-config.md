# Deliverable review, Layer 1: prose and configuration

- **Scope:** `git diff fd16ae65f4b244f1098b94b7ee848f5a7f74c8f2..HEAD`, limited
  to these files: `toolkit/README.md`, `README.md`,
  `toolkit/migrations/v0.9.0.md`, `docs/design.md`,
  `docs/references/dogfood.md`, `docs/references/distribution.md`,
  `docs/changelog.md`, `docs/changelog/2026-09-30-dogfood-launcher.md`,
  `CLAUDE.md` and `justfile`.
- **Checked against:**
  - the shipped code: `toolkit/dogfood.sh`, `toolkit/bin/claude`,
    `toolkit/install.sh`, `toolkit/release.just`, `toolkit/update.sh` and
    `toolkit/version-guard.sh`;
  - the probe reports: `research-probes.md`, `probe-hooks.md` and
    `probe-subdir-hooks.md`;
  - outline Items 5–6, D12, Scope and Risks, and runbook Phase 3;
  - the recall artifact's memory files, plus `craft:design-doc-writing` and
    `plugin-craft:verifying-plugin-changes`;
  - the consumer repos (handoff, craft, cwd-safety, sandbox-lies, gitlore and
    others), which were read and not edited.
- **Prior reviews:** I read `review-docs.md`, `review-code.md` and
  `/tmp/claude/dogfood-build/orchestrator-3-report.md`. Nothing they fixed is
  repeated here.
- **Dogfood run:** I ran the migration end to end on a scratch clone of handoff
  under `$TMPDIR`. The clone's `plugin-dev/` was overlaid with `toolkit/`, and
  nothing was committed. I followed steps 1–4 as written, launched through the
  shim with a stub `claude`, and ran `session-start` and `pre-tool` against the
  result.

## Findings

### Critical

None.

### Major

None.

### Minor

1. **`toolkit/migrations/v0.9.0.md:26-28` — accuracy and usability: step 2's
   justfile instruction does not fit the consumers it is written for.**
   - **What it says:** "Delete … any `justfile` line naming `.bin/claude`."
   - **handoff:** its `precommit` line is
     `shellcheck -x .bin/* bin/* scripts/*.sh tests/*.bats`. The line names
     `.bin/*`, not `.bin/claude`, so read literally the instruction does not
     apply to it.
   - **What breaks:** once `git rm .bin/claude` has removed the directory, the
     unmatched glob reaches shellcheck as a literal. Reproduced in the scratch
     clone, where it failed with
     `.bin/*: openBinaryFile: does not exist (No such file or directory)`.
   - **Why deleting the line is wrong too:** a reader who does treat the line as
     "naming" the shim and deletes it, as told, silently drops shellcheck
     coverage of `bin/`, `scripts/` and `tests/`.
   - **sandbox-lies:** its justfile has the same shape:
     `tracked '*.sh' '*.bash' '*.bats' '.bin/*'`.
   - **Mitigation:** the step's `grep -n '\.bin' .envrc justfile` does surface
     both lines, so the failure is loud rather than silent.
   - **Suggested wording:** remove the `.bin` reference from any justfile line
     that names it, and delete the line only when that reference is all it
     checks.

2. **`toolkit/migrations/v0.9.0.md` (whole note) and `toolkit/README.md:204-209`
   — completeness: rsync is never named as a new prerequisite, and no fallback
   is documented for when the sync fails.**
   - **Why it matters:** after step 3, every `claude` typed in the repo goes
     through the shim, and the shim aborts the launch on any sync failure. So on
     a machine without rsync, the plain `claude` command stops working in that
     repo. The same holds wherever rsync rejects the flags; the macOS check is
     already known to be pending.
   - **What the note says:** it never mentions rsync. Only the manual's
     Requirements line does.
   - **What no doc says:** how to start a session while the sync is broken, for
     example the next `claude` by absolute path. A session started that way then
     gets the `SessionStart` warning, which is correct.
   - **Why this is not a new macOS report:** the macOS behaviour itself is the
     known pending step. What is new is the consequence: a broken sync makes
     `claude` unlaunchable by name, and the docs give no way out.

3. **`toolkit/README.md:61-131` and `README.md:47-102` — usability: a fresh
   install is never pointed at the dogfood Setup.**
   - **What install does:** "Installing in a plugin" now wires the
     `SessionStart` check, but it ends at "Commit" with no pointer to
     `## Dogfooding` → Setup. `install.sh`'s own "Next steps" output does not
     mention it either.
   - **What the user then meets:** a freshly installed consumer gets the "does
     not load …/dist/plugin" warning on every session. Following its remedy
     literally, by launching through `plugin-dev/bin/claude`, then fails with
     `dist/plugin/ is not git-ignored; sync refused` until `.gitignore` and
     `.envrc` are set up.
   - **Effect:** each failure is loud, but the reader is sent through two of
     them to find a section the install flow could have named.
   - **Suggested fix:** one sentence after "Commit" pointing at the Setup
     subsection. It must sit outside the fenced blocks that `doc-sync-test.sh`
     compares.

4. **`toolkit/README.md:227-234` — completeness: the "what goes live when" list
   leaves out some plugin component kinds.**
   - **What the list covers:** hook scripts and `bin/`, skill bodies, agents and
     hook events.
   - **What is missing:** `commands/`, MCP server config (`.mcp.json`) and
     output styles.
   - **Why it matters:** `cc-agent-discovery` records command definitions as
     cached per session. So a maintainer editing a command cannot tell from the
     manual whether `/reload-plugins` is enough or a relaunch is needed.
   - **Suggested fix:** name the class. If it is unverified, say so, the way
     `verifying-plugin-changes` scopes its own `/reload-plugins` claim to skill
     bodies.

5. **`docs/design.md:14-34` (Motivation) and `README.md:12-23` (Why it exists) —
   completeness: neither states the problem the launcher solves.**
   - **The hub:** it still frames the toolkit as "Two problems stacked" (drift
     and the missing guardrail), followed by "Both problems want the same
     answer". The launcher appears only as a fourth item in "The toolkit
     captures" and in a Requirements bullet.
   - **What is missing from both:** the problem itself. A session that loads the
     plugin from its working tree prompts on every agent edit and runs
     half-edited hooks, and four drifted hand-copied shims were already trying
     to work around that.
   - **Where it lives now:** only in the node and the changelog entry.
   - **Why it matters:** the hub is where `craft:design-doc-writing` puts the
     *why*.
   - **Suggested fix:** one line in each.

6. **`docs/references/dogfood.md:103-105` — accuracy: the probe set is described
   as "four consumers", but one of the four is not a consumer.**
   - **The claim:** "a no-op sync measured 60 to 108 ms across four consumers".
   - **The source:** `research-probes.md`'s Q2 table covers craft, cwd-safety,
     edify (repo root) and handoff.
   - **Why edify does not count:** it is not a toolkit consumer. The outline's
     Scope says "edify … vendors nothing", and the node's own "The plugin root
     is the repo root" section rules it out of scope.
   - **Suggested fix:** "across four repositories". The changelog entry
     (`docs/changelog/2026-09-30-dogfood-launcher.md:66`) is unaffected, because
     it gives the range without saying "consumers".

7. **`toolkit/README.md:244-248` — consistency: the manual states an unprobed
   case as fact.**
   - **The manual:** a sandboxed sync "keeps the copy's old one, or copies an
     empty file".
   - **The node and the outline:** the node (`dogfood.md:338-339`) and the
     outline's Risks both mark the zero-byte mask shape as unprobed ("would copy
     an empty file").
   - **What has been observed:** only the char-device case, in
     `research-probes.md`.
   - **Effect:** the advice that follows (promote from your own shell) is right
     either way. Only the factual claim outruns its evidence.

## Checked and clean

- **Shipped behaviour against the docs.** Each of the following matches
  `dogfood.sh`, `bin/claude`, `install.sh` and `release.just`, as described in
  the manual, the node, the hub and the CLAUDE.md Layout bullets:
  - the source set: the ignored list, unanchored `.git`, `/dist/plugin/`,
    tracked-but-ignored files kept, and deletions propagated;
  - the three sync refusals and their exit behaviour;
  - the exclude list written to a file before rsync starts;
  - the root found from the script's own location;
  - the three-channel deny and its wording, including the
    `PreToolUse:<Tool> hook error:` prefix;
  - leaf-symlink resolution, and the dangling leaf compared as spelled;
  - the jq-less pass-through;
  - `session-start`'s whole-entry match;
  - the ANSI reset on both lines;
  - both warning strings, byte for byte less the reset;
  - the shim's `-ef` PATH strip, empty-entry handling, `unset CDPATH`,
    overwriting of an inherited `CLAUDE_CODE_PLUGIN_DIRS`, and exit 127;
  - `just dogfood` as exactly `bash "plugin-dev/dogfood.sh" sync`, with no gate;
  - `add_hook`'s any-matcher presence rule;
  - the quoted dogfood commands beside the bare version-guard command;
  - the three SC2016 disables named in CLAUDE.md.
- **Probe-backed claims.** These match the reports:
  - realpath resolution of inline roots (CC 2.1.283 bundle);
  - the `--files-from` failures, deletions and exit 23;
  - the 60–108 ms timings;
  - Q3: the deny lands before the `ask`, and `additionalContext` is tied to the
    tool-use id (CC 2.1.284);
  - the subdirectory launch firing no project hook, not even an inline `echo`.

  I also confirmed one premise behind the node's "only those collapsed names are
  checked": `git ls-files -o -i --directory` does not collapse an ignored
  directory that contains a tracked file. The tracked file is kept, and only the
  untracked children are listed.
- **Reload claims against `plugin-craft:verifying-plugin-changes`.** These hold
  as stated:
  - skill bodies on `/reload-plugins`;
  - hook events and agent definitions only after a restart, with `claude -c` a
    full restart that keeps the conversation;
  - hook-script and `bin/` bodies live on each call.
- **The migration path.**
  - `update.sh` prints `migrations/v0.9.0.md` for a pull from 0.8.0, since
    `version_gt` accepts 0.9.0 > 0.8.0 and rejects 0.9.0 > 0.9.0. It also prints
    it for consumers at 0.6.0 and 0.7.1 (cwd-safety, gitmoji, handoff, craft,
    gitlore, shell-gotchas).
  - The steps cover every D12 bullet, in a working order.
  - Step 1 is a no-op vendoring with `plugin-dev/` present, and it wired exactly
    the two dogfood entries beside the existing version-guard in the scratch
    clone.
  - Steps 3–4 then gave a working launch, with `-c --foo` passed through and the
    variable set to the copy.
  - The `.envrc` ordering instruction fits every consumer's `.envrc`:
    `PATH_add .gitlore/bin` comes first, and the last `PATH_add` wins.
  - No consumer has an ignored entry with a pattern character, so none would hit
    the sync refusal.
  - craft's existing `/dist/` already satisfies step 4.
- **Commands for a human.** The blocks in the migration note, the manual's Setup
  and the shared install and update blocks can each be run as written. The
  check-then-append form in step 4 is idempotent.
- **Cross-references.** `docs-test.sh` (pointer resolution, 400-line cap),
  `doc-sync-test.sh` (5 shared blocks, Layout against `toolkit/`),
  `citation-test.sh` and `dist-tree-test.sh` (11 files) all pass. These targets
  resolve:
  - `toolkit/README.md#dogfooding`;
  - the hub's link to `references/dogfood.md`;
  - the node's links to the plan reports and to `version-guard.md`;
  - distribution.md's link to `dogfood.md`.
- **The justfile.**
  - `precommit` shellchecks `toolkit/dogfood.sh` and `toolkit/bin/claude`, runs
    `bash -n` on all 15 suites, and runs every file in `tests/`, with none
    missing.
  - `just _import-check` passes and prints the recap that names `dogfood`.
  - The `dogfood` recipe's doc comment is one line.
  - The gate name is `precommit` throughout.
- **Front page and manual agree.** Both describe the shim and `just dogfood` the
  same way, link the same anchor, and name the same requirements (with `rsync`).
  The install prose in both names the two dogfood hooks. CLAUDE.md's Layout,
  Quality gate, node list and Conventions bullet match the code and the files on
  disk.
- **Living-doc rules.**
  - The hub and the node are in the present tense. The dates and CC versions
    that remain ground claims rather than narrate.
  - The changelog entry is dated, indexed newest first, and records where the
    code departs from the outline. Each departure is true of the code.
  - The account of the consumer shims matches `craft/.bin/claude` (a copy of
    `.claude-plugin` and `skills` in `dist/plugin`, with `unset CDPATH`) and the
    other three shims.
- **Scope.** The gitlore `GITLORE_AUTO_CLAUDE_PLUGIN_DIR` handover is recorded,
  and the brief exists at
  `gitlore/inbox/2026-09-29-brief-remove-auto-plugin-dir.md`.
