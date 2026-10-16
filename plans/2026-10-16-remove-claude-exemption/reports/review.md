# Review: remove the `.claude/` clean-tree exemption

Verdict: correct and in scope. One stale code comment to fix before commit
(finding 1); the rest are wording.

## Findings, ranked

### 1. Medium: stale comment still says `.claude/` is exempt

`toolkit/release-tags.sh:248`, in a shipped file:

    # refuses a dirty tree before release_preflight runs, and clean_pathspecs
    # exempts only `.claude/` and the gitlore submodule — never
    # `.claude-plugin/` — so the hand-written bump this refusal is about has

The change updated the twin comment in `tests/release-tags-test.sh:277` and
missed this one. How it goes wrong: a maintainer or agent reading the consumer
script's reasoning is told about an exemption the code no longer makes, which is
the same "list written from memory" drift `clean_pathspecs`' own header says it
guards against. Your stale-mention grep missed it because the wording is
"exempts only `.claude/`", not one of the listed phrases. Fix: change it to
match the test, i.e. "clean_pathspecs exempts only the gitlore submodule — never
`.claude-plugin/` —".

### 2. Low: recovery.md says more about the maintainer's reasoning than the brief does

`docs/references/recovery.md` (section "Why the exemption is removed rather than
narrowed", last sentence): "...and the maintainer's decision is that the cost of
the occasional refusal is the smaller one."

The brief says only that my human partner asks for the removal and that it is
their call ("This is their call... the rest of this brief is context"), plus
that a dirty `TASK.md`/`TODO.md` refusing "is accepted". It never compares two
costs. The doc puts a reason in their mouth that they did not give. How it goes
wrong: a later session weighing whether to bring back a narrowed exemption reads
that sentence as the deciding argument, and tries to argue against it. Fix:
"...and my human partner has decided to accept the refusal it brings back." (or
"the maintainer has decided", whichever voice the node uses). The new changelog
record says it more accurately ("It is overridden by my human partner's
decision") and needs no change.

### 3. Low: comment cites the wrong file for `tree_is_clean`

`scripts/self-release.sh:49`: "as toolkit/release.sh's tree_is_clean excludes
the gitlore memory submodule". `tree_is_clean` now lives in
`toolkit/release-preflight.sh`. The old comment had the same error, but this
change rewrote the line. Fix: `toolkit/release-preflight.sh's tree_is_clean`.

### 4. Low: the preflight comment splits one thought over two paragraphs

`toolkit/release-preflight.sh:44-49`: "One path is exempt, because an agent
session moves it by design between commits." / blank line / "It is a
gitlore-mounted memory submodule: ...". This is the old two-item framing with
one item removed. Fix: merge into one paragraph, e.g. "One path is exempt: a
gitlore-mounted memory submodule, whose gitlink sits ahead of what HEAD records
between commits by design — ...".

### 5. Info: present-tense claim that every consumer has migrated

`docs/references/recovery.md` ("every repo carrying the toolkit has moved to
them") and the new changelog record ("every repo carrying the toolkit has
migrated"). I checked it for the mounted repos: `git ls-files .claude` in
gitmoji, candidature, onekeys, gitlore, shell-gotchas, cwd-safety, handoff,
claude-plugins and this repo shows no `handoff-*` file anywhere. handoff is at
v0.18.0 with `HANDOFF_REL_TASK="TASK.md"`, so the brief's ordering constraint
(land after the handoff release that moves the files) is met. The dated record
can keep the claim. In the present-tense node, though, it is a state claim that
nothing will update; "the `handoff` skill writes them there" is the durable
version. Optional.

### 6. Info: other tracked `.claude/` files exist

gitlore also tracks `.claude/rules/shell.md` and `.claude/token-efficient.md`.
The docs present `settings.json` and `gitlore-hook-setup` as examples, so they
are not wrong. TODO.md:3 says "settings.json and gitlore-hook-setup everywhere",
which is a slight undercount for gitlore. The brief's "check other plugins for
tracked `.claude/` writers" turns up nothing that a skill rewrites between
commits.

## Script correctness (set -euo pipefail, bash 3.2)

- `clean_exempt=()` followed by `"${#clean_exempt[@]}"`: safe under `set -u` on
  3.2. `"${clean_exempt[@]}"` is only expanded inside the `-gt 0` guard, which
  matters because bash before 4.4 treats an empty `"${arr[@]}"` as unbound.
- `clean_specs` always holds at least `.`, so its two expansions
  (`release-preflight.sh:33`, `:87`) are never empty.
- No other expansion of either array in `toolkit/` or `scripts/`.
- No remaining `.claude` exclusion in `toolkit/` or `scripts/`. The other
  `.claude/` hits are install.sh/update.sh/README settings paths and
  self-release.sh:209 (what the root tree contains), all correct. The one stale
  comment is finding 1.
- I did not run anything under a real bash 3.2 binary (Linux box). The
  conclusion comes from reading the code.

## Tests as evidence: mutation results

Each mutation was run in a scratch `cp -r` copy under `$TMPDIR`. The real tree
was not touched.

| Mutation | Suite | Result |
| --- | --- | --- |
| `clean_specs=(. ':(exclude).claude')` | release-tree | 12 failures: both staged-frame scenarios (exit 0, release ran, tag + marketplace bump + gh call) |
| old `.claude/ — agent working state` line restored in `clean_exempt` only | release-tree | 5 failures: no-.claude-exemption and no-empty-header asserts in dirty-root, spaced-path, both staged-frame scenarios |
| `':(exclude).claude'` re-added to self-release.sh | self-release-refusal | 4 failures: staged .claude/ frame exit 0, tag created, gh touched |
| `':(exclude)memory'` dropped from self-release.sh | self-release-refusal | 1 failure: "memory/ is exempted" (the split-out memory scenario still catches it alone) |
| `clean_specs+=(":(exclude)$mem")` neutered | release-tree | resting-memory plugin + marketplace scenarios fail |

Nothing is lost:
- `.claude-plugin/` refusing is still covered by the dirty-plugin-root scenario
  (`release-tree-test.sh`, exit 1, names `.claude-plugin/plugin.json`).
- The removed decoy test only proved that the `.claude` pathspec matched at the
  separator, and that pathspec no longer exists.
- Memory exemption coverage remains in both suites.
- The `stage_claude_frame` removed from `self-release-publish-test.sh` was
  already dead code there. The live copy is in the refusal suite.

## Docs

- The hub (`docs/design.md` ~178) and the node (`recovery.md` "The clean-tree
  check exempts only the memory gitlink") agree. So do `self-release.md` and the
  hub's self-release bullet. The cross-reference anchor text was updated to the
  new heading.
- `git diff docs/changelog/2026-09-01*` is empty. The new record says it
  supersedes that one, and so does the index line.
- The stale-phrase grep outside `plans/`, `inbox/` and `docs/changelog/` is
  clean apart from finding 1. Remaining hits are the new prose and the
  `assert_not_contains` strings. `toolkit/docs/`, `README.md` and `CLAUDE.md`
  hold no exemption statement.
- The `toolkit/README.md` rewrite ("the clean-tree check refuses a dirty
  manifest") is accurate.

## just precommit

See the tail appended below.

Ran on the real tree: exit 0, no FAIL or error lines anywhere in the output.
Tail:

    bash tests/dogfood-launcher-path-test.sh
    ...
    === no next claude exits 127 ===

    all dogfood launcher path scenarios passed
    ok
    exit=0
