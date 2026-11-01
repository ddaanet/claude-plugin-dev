# The frontmatter check

Why `check-frontmatter.sh` exists beside `claude plugin validate`, why
`description` is required and `name` is not, why it parses YAML with a Python
dependency and not awk, why that Python is embedded and run as `python3 -I`, and
what it costs a consumer. The sibling it is wired beside is argued in
[size-check.md](size-check.md), including why a shipped check runs uncached and
is wired by hand. The conclusions these arguments support are listed in
[../design.md](../design.md).

Facts marked `verified against CC 2.1.316` were probed with
`claude plugin validate` and the strings of the Claude Code bundle at that
version. **Runtime loading was not probed**: what Claude Code does at startup
with a file this check refuses or passes is read from the bundle's strings only,
and no session was started to confirm it.

## Why it exists

`claude plugin validate` is the validator a plugin author has, and it does not
parse the block well enough to be the gate. `description: a: b` and
`description: [x`, neither of which is valid YAML, pass it with exit 0 (verified
against CC 2.1.316). A frontmatter that is not a mapping, or a `name` that is
not a string, does fail it with exit 1, and a missing `description` or a missing
block is a warning, which a gate does not stop on. A plugin gate that wants a
file to be loadable needs a check of its own, and every plugin wants the same
one, so it ships.

## What it refuses, and why `description` is required

A file fails when it has no block, is not UTF-8 or not YAML, parses to something
other than a mapping, lacks a non-blank string `description`, or has a `name`
that is present and not a non-blank string.

**`description` is required.** The validator warns on its absence in all three
kinds, and the bundle's own text for an agent calls it a missing required field
(verified against CC 2.1.316). It is the text the model reads to decide when to
use a skill, agent or command, so a file without one is dead weight even where
it loads.

**`name` is not.** The validator says nothing about an absent `name`, nor about
one that differs from its directory or file (verified against CC 2.1.316). A
check that refused either would refuse files Claude Code accepts. A `name` that
is present is held to a non-blank string, because the validator fails a
non-string one and a blank one names nothing.

**No block.** The bundle says an agent without a block does not load at all, and
a skill or command loads with empty metadata (verified against CC 2.1.316). Line
one must be exactly `---`: a CRLF or a byte-order mark makes the line differ,
and the file is refused, because a reader that matches the line exactly sees no
block either. That strictness is the check's, and not a probed property of
Claude Code.

## Why a Python dependency, not an awk parser

The other shipped checks read text with awk. YAML cannot be read that way
without reimplementing a parser. `a: b` is a mapping where `[x` opens a flow
sequence that never closes, a scalar can span lines folded or quoted, and a
value such as `2026-13-45` or `yes` parses to something other than a string. A
hand-written subset would accept some invalid blocks and refuse some valid ones,
which is the validator's fault, repeated. PyYAML `safe_load` is the reference
parser the plugin ecosystem already uses, so the verdict is the parser's, not a
rule of this toolkit's.

The decision is my human partner's, 2026-11-01: Python dependencies come from
`uv sync`, the venv is activated in `.envrc`, and no recipe uses `uv run`.
Neither `uv run` nor `pip` is suggested to a consumer, and the remedy line names
the three steps: `pyyaml` in the dev group of `pyproject.toml`, `uv sync`, and
`.venv/bin` on PATH from `.envrc`.

## Why the Python is embedded and run as `python3 -I`

The script is bash holding a Python program in a heredoc, run as
`python3 -I -c`, with the file list on stdin NUL-delimited.

- **Embedded**, not a sibling `.py`: one shipped file instead of two, and
  `python3 -c` needs no path to the program, so no location is resolved from the
  script's own directory.
- **`-I`, isolated mode**: the check runs inside the repository it checks.
  Without `-I`, Python puts the current directory on `sys.path` and reads
  `PYTHON*` environment variables, so a `yaml.py` in the checked tree, or one in
  the environment, would run in place of PyYAML. `-I` removes both.
- **Stdin for the list**: a path holding a space, a newline or an apostrophe
  survives intact, which an argument list built by word splitting would not.
- **A listing before the interpreter**: with no file to check, the run signs off
  with zeros before `python3` is looked up, so a plugin that ships no skill,
  agent or command needs no parser.

Files are chosen from disk with `git ls-files -z -co --exclude-standard`, the
set the sibling checks read, so an untracked file is read and an ignored one is
not.

## What it costs

- **A consumer without a venv adds one**: `pyyaml` in `pyproject.toml`,
  `uv sync`, and a `PATH_add` in `.envrc`. The migration note carries the steps.
  The check refuses with a one-line remedy rather than skipping, since a skipped
  check reports green while checking nothing.
- **The verdict depends on the PyYAML installed.** It follows YAML 1.1 as PyYAML
  reads it, so a version change could in principle move a verdict. A consumer
  that caches its gate hashes the interpreter's PyYAML version with its other
  tool versions, as this repo does in `PLUGIN_DEV_GATE_TOOLS`.
- **This repo does not run it on itself.** It ships no skill, agent or command.
  `tests/check-frontmatter-*-test.sh` covers the script against fixture plugin
  repos and the venv's real PyYAML, and the suites fail outright if that
  interpreter cannot import `yaml`.
- **The check is stricter than the loader in places and weaker in others, and
  how much is unknown**: runtime loading was not probed, so a file it passes can
  still fail to load and a file it refuses may load.
