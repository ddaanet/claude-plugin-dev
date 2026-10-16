# Gate sentinels and the quiet bats runner

Why a consumer's gate can skip itself behind a hash of its inputs, why the
functions travel as an interpolated prolog, why the inputs are a list the
consumer owns, and what the guards inside the prolog refuse. The release gate
they sit beside is in [release-flow.md](release-flow.md); the shipped-file
boundary they cross is in [distribution.md](distribution.md). The conclusions
these arguments support are listed in [../design.md](../design.md).

## Where it came from

gitlore carried both pieces in its own tree: a `bash_prolog` justfile variable
defining the sentinel functions, and `scripts/run-bats.sh`. handoff's release
printed several hundred lines of bats TAP and then re-ran the whole gate on a
tree it had just passed, and asked for the same two answers. Copying them into
each plugin is the drift this repo exists to end, so they ship here.

## Opt-in, in a file of their own

`release.just` is imported by every consumer, and its `prerelease` contract is
mandatory. The gate sentinels are neither: a plugin whose gate is a few seconds
long gains nothing from a cache, and one that does not trust its own input list
is better without. So they live in `toolkit/gates.just`, imported by a line the
consumer adds, and `release.just` neither imports nor mentions it. A consumer
that adds nothing sees nothing. The one coupling is a name clash, which
`_import-check` pins by importing both into one stub: `gates.just` defines
`plugin_dev_gate_prolog` and nothing else.

The `precommit`/`prerelease` contract is untouched. A cached `precommit` is
still a recipe that exits 0, so `release` behind `prerelease: precommit` skips
the same checks the commit gate skipped, on the same evidence.

## The functions travel as a prolog variable

The guard must leave the recipe (`exit 0`) and the record must read what the
guard set (`guard_hash`, `sentinel`), so the functions have to run in the
recipe's own shell. Two ways to get them there: `source plugin-dev/gates.sh` as
the second line of each recipe, or interpolate a variable as the shebang. The
variable was chosen because it was verified to work in an imported justfile and
because the import line is then the only wiring: a sourced file puts the toolkit
prefix and a path that depends on the working directory into every gate recipe.
The cost is that the bash lives inside a justfile string, where `shellcheck` and
`bash -n` do not reach. `tests/gates-guards-test.sh` closes that: it evaluates
the variable and runs `shellcheck` over it.

The variable is `[private]`, so it stays out of `just --list`.

## Names, with no aliases

gitlore's `GITLORE_GATE_DIR`, `GITLORE_GATE_FORCE` and `gitlore/gates` become
`PLUGIN_DEV_GATE_DIR`, `PLUGIN_DEV_GATE_FORCE` and `plugin-dev/gates`, and the
runner's log prefix `plugin-dev-bats.`. gitlore patches its own justfile when it
takes the tag that ships them, so an alias would be dead weight kept to spare a
caller that is edited in the same step. The function names are unchanged, since
nothing about them was gitlore's.

## The inputs are a list the consumer owns

The hash covers the names and contents of the non-ignored files matching the
pathspecs the guard is given, tracked or not. The toolkit cannot infer the list:
it does not know what the consumer's checks read, and a hash of the whole tree
would be invalidated by every scratch file and, under the command sandbox, by
the phantom dotfiles it masks into the root. So the consumer names paths, and
the cache is correct exactly while every check reads inside them. That rule is
the memory `gate-cache-must-cover-every-check` carried from ghmem: a check whose
scope exceeds the hash goes red on an unrelated commit, days after the file that
broke it.

A gitlink is the case no list can fix. `git ls-files` yields the one path, which
is not a regular file, so only its name reaches the hash; neither an edit inside
the submodule nor a new commit of it moves anything. A check that reads a
gitlink therefore runs uncached, in the recipe body ahead of the guard. This
fails in the opposite direction from the under-covered tree: a gate that is
green on precisely the commit the check exists for.

**No drift check ships.** gitlore guards its list with a suite that asserts
every declared path exists and every top-level entry is declared or excluded. It
reads gitlore's own justfile and its own exclusion list, so a shipped version
would need a second declaration from each consumer, and the consumer's checks —
the thing the list must cover — are still invisible to it. The coverage rule is
documented in the manual instead, with a procedure to prove a list. The cost is
that a pathspec matching nothing narrows the hash silently. Revisit when a
second consumer adopts and a pattern for the declaration shows.

## Tool versions are the consumer's list

gitlore hashes `bats`, `shellcheck`, `jq` and `python3` versions because it pins
none of them; handoff pins its Python tools through `uv.lock` (an input file)
and not `bats`, `shellcheck` or `claude`. The set differs per consumer, so the
toolkit hashes none by default. A consumer lists them in an exported
`PLUGIN_DEV_GATE_TOOLS`, one shell command per line.

Alternatives rejected: an argument to each `sentinel-guard`, which repeats the
list per gate; and a just variable the imported file defines and the importing
justfile overrides, which depends on how just resolves a name defined on both
sides of an import and was not established. An exported variable is plain
environment, set in a justfile or `.envrc`, with no such dependency. Each line
runs through `bash -c` with stderr folded in, since some tools print versions to
stderr, and a failing line fails the hash.

## What the guards refuse

- **A pass is recorded only against the hash taken before the checks.** A peer
  session editing an input mid-run moves the hash; recording the new one would
  seal in a pass for a tree nothing checked. The gate leaves no sentinel and
  exits 1, because a caller that saw status 0 would read it as green.
- **A hash that cannot be computed records nothing and says so.** A partial hash
  would match itself on the next run if the failure were deterministic. The
  recipe still passes, since the checks did; a cache that quietly stopped
  caching is the failure nobody hears about.
- **Every component of the hash fails explicitly.** The hash runs inside a
  command substitution inside a condition, where bash suspends errexit, so a
  version command that died would drop out of the stream and the gate would keep
  caching against a hash that no longer covers it. The same reason makes every
  refusal inside `check-sentinel` an explicit `exit`: it runs as the condition
  of an `if`.
- **One guard per recipe body, enforced.** `check-sentinel` leaves shell
  variables for `record-sentinel`, so a second gate in one body would clobber
  the first's state and record the wrong pass. gitlore documented this in a
  comment; the prolog refuses it, because a comment is read once and the
  clobbering is silent. `record-sentinel` with no guard before it, a guard with
  no pathspec (which would hash the whole repository) and a gate name holding a
  `/` (which would write outside the gate directory) are refused likewise.
- **The sentinel lives under the gitdir.** Bookkeeping in the working tree would
  show in `git status` or in its own hash and invalidate the gate on every run.
  `git rev-parse --git-path` resolves per worktree, so a worktree has its own
  passes.

The hash is a `cksum`, a 32-bit CRC. Two different trees colliding is a
one-in-four-billion event per edit; it is inherited from gitlore, and `cksum` is
POSIX where a stronger digest is spelled `sha256sum` on GNU and `shasum -a 256`
on macOS. The failure is a skipped run of checks, which the next real edit
repairs.

## The quiet runner

`run-bats.sh` is gitlore's, ported with one rename. A full TAP stream is
hundreds of lines, and piping it through `tail` risks cropping the one `not ok`.
The runner logs the whole stream, prints only the `not ok` blocks (or the whole
log when no TAP line appeared, as when bats died before a plan), then one
summary line, and exits with bats' own status. The log template ends in its `X`s
because BSD `mktemp` randomises only a trailing run of them. It does not depend
on the sentinels, and a consumer may take either alone.

## Out of scope

gitlore's per-suite cache (`run-bats-cached.sh`, `parse-bats-junit.py`, and the
`run-suites` function that reaches them) keeps one key per suite beneath the
whole-tree sentinel. It is bats-specific and larger than the rest together. It
is left in gitlore, and is a candidate for a later opt-in once a second consumer
wants it. `run-suites` reads `sentinel_dir`, `gate_inputs` and
`gate-inputs-hash`, so those names are part of what the prolog promises.
