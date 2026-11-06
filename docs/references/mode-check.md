# The mode check

Why `check-modes.sh` runs in the consumer's own gate and not in this repo's
tests or in `update.sh`, why it applies a rule over file contents and not a
list, why it reads disk with `[ -x ]` and not the index, and why it checks only
the directory it is vendored into. The sibling it is wired beside is argued in
[size-check.md](size-check.md), including why a shipped check runs uncached and
is wired by hand. The conclusions these arguments support are listed in
[../design.md](../design.md).

## Why it is consumer-side

A script that loses its execute bit after vendoring breaks nothing a consumer's
gate looks at. Recipes call vendored scripts as `bash <script>`, which ignores
the mode, while `bin/claude` drops off PATH without a word and a direct call
fails with "Permission denied". A consumer commit that flips vendored scripts to
100644 therefore passes every check it has.

Three places could catch it, and only one sees a flip made after vendoring:

- **A test in this repo** reads the toolkit as shipped. It sees the producer's
  modes, never a consumer's later commit.
- **A warning in `update.sh`** runs once, at a pull. A flip made by a later
  consumer commit is invisible to it.
- **A check in the consumer's gate** runs on every commit, over the files that
  consumer holds. It sees the flip in the commit that makes it.

So the check ships as a script the consumer wires into its own `precommit`. The
producer side is still pinned: `tests/dist-tree-test.sh` applies the same rule
to the shipped set, so no release sends out a script without the bit.

## A rule over a list

A file whose first two bytes are `#!` must pass `[ -x ]`. No list of script
names is kept. A list drifts: a script added to the toolkit and not to the list
is the unchecked file the list was meant to prevent, and a consumer's own list
would repeat the omission in every repo.

The rule over-covers on purpose. Every shipped script that starts with `#!` is
made executable, including those run only through `bash` or sourced from a
sibling (`install.sh`, `update.sh`, `version-guard.sh`, `exempt-list.sh`). The
bit is harmless on them, and one rule that needs no exceptions is worth more
than a short list of files that may stay 644. A file with no `#!`, such as the
sourced `release-*.sh` pieces, is never checked.

## Disk, not the index

The mode is read by `[ -x ]` on the file on disk, and the files are those of
`git ls-files -co --exclude-standard`, never the index. This is the repo's
convention for every check: the gate sentinel hashes disk, and a check that read
the index would see a file the next `git add` stages while the hash did not
move, so a cached pass could commit it unchecked. An untracked `#!` file is
checked and an ignored one is not.

## Scope: the directory it lives in

The check reads the directory the script sits in, resolved from its own
location: the vendored `plugin-dev/` in a consumer, `toolkit/` here. It takes no
arguments and runs from anywhere in the work tree. A consumer's own scripts are
not its concern, since the toolkit has no claim on how a consumer modes them,
and a path argument would invite the call that checks the wrong tree. Symlinks
and anything that is not a regular file are skipped.

**Uncached.** The check runs on every call, for the reason `check-size` does:
the set it reads is not one the consumer's sentinel hashes. Its cost is one
listing and a two-byte read per file.

## Report

Each file is one stderr line, `mode-lost: <path from the repo root>`, then a
hint: the `chmod +x` command over those paths, each single-quoted so a path with
a space or a quote runs as written, and a line to commit. A pass prints one line
naming how many `#!` files it checked, so a check that read nothing is visible.
Outside a work tree it prints one line and exits 1.

**Residual bound.** A path holding a newline is reported as split lines.

Adoption blocks nothing by itself. `update.sh` edits nothing outside
`plugin-dev/`, so a consumer runs `just check-modes` once unwired, runs the hint
it prints, and then adds the recipe to `precommit`; the migration note carries
the steps.
