# Brief: a skill frontmatter check in the standard consumer setup

From a shell-gotchas session, 2026-10-29. A proposal, not a decision.

## What happened

shell-gotchas' `bats-gotchas` skill shipped an unquoted `description:`
containing `pitfalls: tests`. That is invalid YAML
(`mapping values are not allowed here`), so a strict frontmatter loader cannot
register the skill. It passed `just precommit` (`check-refs`, `jq` on
`plugin.json`, shellcheck) and the per-commit medium review of the commit that
introduced it, and was caught only by an adversarial review of the whole release
branch. Nothing in the toolkit's standard setup parses a `SKILL.md`.

Most consumers ship skills, so every one of them has the same hole; any
description with a `: ` in it reproduces it.

## What shell-gotchas did locally

`scripts/check-frontmatter.py` (in shell-gotchas), run from `precommit` as
`python3 -I scripts/check-frontmatter.py`. For each `skills/*/SKILL.md` it
splits the block on the `---` fence lines, parses it with PyYAML `safe_load`,
and fails when it is invalid YAML, not a mapping, lacks a non-empty string
`name` or `description`, or has a `name` different from its directory. It signs
off with `check-frontmatter: N skills have valid name and description`.

## Proposal

Ship an equivalent check in `toolkit/` beside `check-refs`, as a recipe a
consumer wires into its own gate (`precommit: check-refs check-frontmatter`),
and add it to the standard setup the README and `plugin-craft:plugin-creation`
describe.

## Open questions for the toolkit side

1. **Parser dependency.** PyYAML is not in Apple's stock `python3`, and the
   toolkit is otherwise shell plus `jq`. Options: require PyYAML (the `-I` flag
   hides user site-packages, so the install hint must name system packages); run
   via `uv run --with pyyaml`; or use a different parser (`yq`, a Node `yaml`
   package). A hand-rolled regex is not an option.
2. **Which parser matches Claude Code's loader.** `safe_load` accepts duplicate
   keys (last wins) that a stricter YAML 1.2 parser rejects, and the fence
   handling may differ on a BOM or trailing whitespace. Worth checking what
   Claude Code actually uses before choosing, so the gate and the loader agree.
3. **Scope.** Also cover `agents/*.md` and `commands/*.md` frontmatter, which
   have the same failure mode.
4. **Coverage.** A fixture test pinning the rejection of `description: a: b`;
   shell-gotchas' local check has none.

Once triaged here, shell-gotchas would drop its local script in favour of the
toolkit recipe on its next `just update-plugin-dev`.

## Addendum: probe results on open questions 1 and 2 (same day)

Probed on Linux against Claude Code 2.1.312 (native build), Bun 1.4.3, perl
5.40.1, Python 3.13.5. Nothing below was probed on macOS.

- **Claude Code's loader is `Bun.YAML.parse`.** The bundle defines
  `function wH(e){return Bun.YAML.parse(e)}` next to the skill frontmatter field
  list, and logs `Failed to parse YAML frontmatter!`. The parser is not
  reachable from outside: `BUN_BE_BUN=1 claude -e …` is rejected by Claude
  Code's own option parser.
- **`claude plugin validate` does not check skill frontmatter.** On a plugin
  copy, a manifest-less dir, a `skills/` dir and a `.claude/skills` layout, it
  reported `contents: []` and exited 0 with `description: pitfalls: tests`.
  `claude plugin details` takes an installed plugin name, not a path.
- **Behaviour on three cases**:

  | input | Bun.YAML | PyYAML `safe_load` | perl `CPAN::Meta::YAML` |
  |---|---|---|---|
  | `description: pitfalls: tests` | error | error | error |
  | duplicate key `a: 1` / `a: 2` | last wins | last wins | last wins, warns |
  | `name: [x` (unclosed flow) | error | error | accepted as string `[x` |

  All three agree on the three shell-gotchas `SKILL.md` frontmatter blocks.
- **`CPAN::Meta::YAML` is core perl since 5.13.9** (`corelist`), so it is the
  only parser among the toolkit's existing dependencies, but it is a YAML subset
  and its pod says it "should not be used for any other general YAML parsing"
  than CPAN metadata. `just`, `git`, `jq` and the Python standard library have
  none.

shell-gotchas' decision: keep PyYAML, failing the gate with an install hint when
it is not importable.
