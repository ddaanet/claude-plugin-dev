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

The hash covers the names, contents and execute bits of the non-ignored files
matching the pathspecs the guard is given, tracked or not. The toolkit cannot
infer the list: it does not know what the consumer's checks read, and a hash of
the whole tree would be invalidated by every scratch file and, under the command
sandbox, by the phantom dotfiles it masks into the root. So the consumer names
paths, and the cache is correct exactly while every check reads inside them. The
guard hashes two more itself, the justfile and the vendored toolkit tree: both
exist in every consumer (`install.sh` writes the import into the root justfile,
and the toolkit is vendored at `plugin-dev/`), so listing them was a step to
forget that named no choice. The hash does not cover `$0`, the recipe's own
script, because the justfile already holds it.

They are a second input set, listed apart from the consumer's pathspecs and
joined to it after listing. Appended to the consumer's list they would share its
excludes, and `sentinel-guard lint ':!docs'` would hash the justfile alone:
excludes subtract from the positive pathspecs of their own list, and a list of
excludes alone subtracts from the whole repository. They are also absolute. A
literal `justfile` resolves against the directory the recipe runs in and matches
nothing under `[working-directory]`, in a module, or for a file named
`Justfile`. The prolog interpolates `justfile()` and, evaluated in `gates.just`
itself, `source_directory()` (the vendored directory), each shell-quoted, as
`gate_builtins`, and the listing passes them as `:(literal)` pathspecs so a glob
character in the path is not one. Both functions were probed through an import:
`source_directory()` is `gates.just`'s own directory whoever imports it, and
`justfile()` is the root file even from a module. A module's own file is
therefore not covered, and the manual says to list it. A `gates.just` outside
the repository fails the listing, which the hash reports as uncomputable. The
array lives in the prolog and not in `check-sentinel`, so a caller that sets
only `gate_inputs` and calls `gate-inputs-hash`, as gitlore's `run-suites` does,
still gets both inputs; `gate_cwd` defaults to the current directory for the
same reason. That rule is the memory `gate-cache-must-cover-every-check` carried
from ghmem: a check whose scope exceeds the hash goes red on an unrelated
commit, days after the file that broke it.

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
documented in the manual instead, with a procedure to prove a list. The one
check that needs no declaration ships: the guard refuses a pathspec that matches
no file, because a typo there would narrow the hash and cache forever. An
exclude pathspec has no files of its own and is not held to it: `:!…`, `:^…`,
and `exclude` among the comma-separated magic words of `:(…)`. A positive
pathspec that merely contains the word, `:(glob)excluded/**`, is held to it. The
check stops at the first file it finds rather than listing them all. Revisit the
rest when a second consumer adopts and a pattern for the declaration shows.

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
  seal in a pass for a tree nothing checked. The gate leaves no sentinel, prints
  a one-line notice, and keeps the checks' own verdict. The checks did pass,
  against the tree they read, so failing the recipe would report a failure that
  did not happen and make a concurrent edit break an unrelated commit; the cost
  of withholding the sentinel is one redundant run.
- **A hash that cannot be computed records nothing and says so.** A partial hash
  would match itself on the next run if the failure were deterministic. The
  recipe still passes, since the checks did; a cache that quietly stopped
  caching is the failure nobody hears about.
- **Every component of the hash fails explicitly.** The hash runs inside a
  command substitution inside a condition, where bash suspends errexit, so a
  version command that died would drop out of the stream and the gate would keep
  caching against a hash that no longer covers it. A file that cannot be read
  fails it likewise: the first version read files in a loop whose status was its
  last iteration's, and recorded a partial hash.
- **A name and its content are delimited, and the execute bit is in.** Name
  followed by content streamed the same bytes for a tree of two files and a tree
  of one file holding the second's name and content. Each regular file now
  contributes `cksum`'s line (checksum, size, name), and a manifest line carries
  its execute bit: a hook that loses it stops running and nothing else changed.
  `cksum` runs once over the whole list through `xargs -0`, in place of one
  `cat` per file, twice per uncached run; it is POSIX and takes `--` on GNU and
  BSD alike. A symlink is told
from a regular file (`l` for `x` or `-`), so a file replaced by a link to the
same content moves the hash. No other mode bit is hashed. The same reason makes
every refusal inside `check-sentinel` an explicit `exit`: it runs as the
condition of an `if`.
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
- **The guard pins the directory it ran in.** The gitdir path and the pathspecs
  are relative to the working directory, and a recipe body may `cd` before it
  records. The sentinel path is made absolute and the starting directory kept at
  guard time, and the hash runs from there.
- **`PLUGIN_DEV_GATE_FORCE` is any non-empty value.** `0` forces too. The test
  is the shortest one, and the manual says so rather than the code growing a
  comparison to match a spelling.

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
summary line, and exits with bats' own status. The whole log is shown whenever
bats failed with no `not ok` block to show (a `teardown_file` crash, a test
count that does not add up, an abort mid-run), since it is then the only account
of the failure. A run that exits 0 having run no test (a `--filter` that matches
nothing, an empty `.bats` file) is a failure, since a gate that records it has
vouched for nothing: it prints `bats: no tests ran`, the log, and exits 1. A
green run removes the log, because `$TMPDIR` can be a small tmpfs and a passing
log is never read; a failed run keeps it, and only then does the summary line
name it. The log template ends in its `X`s because BSD `mktemp` randomises only
a trailing run of them. It does not depend on the sentinels, and a consumer may
take either alone.

## Out of scope

gitlore's per-suite cache (`run-bats-cached.sh`, `parse-bats-junit.py`, and the
`run-suites` function that reaches them) keeps one key per suite beneath the
whole-tree sentinel. It is bats-specific and larger than the rest together. It
is left in gitlore, and is a candidate for a later opt-in once a second consumer
wants it. `run-suites` reads `sentinel_dir`, `gate_inputs` and
`gate-inputs-hash`, so those names are part of what the prolog promises.
