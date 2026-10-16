# 2026-10-16 — Gate sentinels: a fourth review, before release

The review of the third round's commit
([record](2026-10-16-gate-sentinel-third-review.md)) found one gap in the guard,
two documentation errors and two tests that were missing.

- **The guard refused the short top-anchored excludes.** The exemption from the
  "matches no file" check covered `:!…`, `:^…` and `exclude` among the magic
  words, and not `:/!…` and `:/^…`, which git reads as excludes anchored at the
  top. From a directory whose files all sit below the excluded path, such a
  spelling lists nothing and was refused as a typo. Both are in the match now.
- **The manual said `':(top,exclude)docs'` covers the whole repository.** It
  anchors the exclude and not the listing: probed from a subdirectory, the list
  still holds only that directory's files. A gate over the whole repository
  minus `docs` writes `:/ ':(top,exclude)docs'` or `:/ ':/!docs'`, and the
  manual says so. The design node already said the whole repository is spelled
  `:/`.
- **The list of options `run-bats.sh` does not support was wrong both ways.** It
  named `--formatter` and `-F` outright, though `-F tap` and `-F tap13` are the
  format the runner reads, and left out `-p`, `-c`, `-v` and `-h`. The usage
  line, the manual, the migration note and the design node now give the rule: an
  option that changes the output format or prints something other than test
  results is unsupported, with those as examples.
- **`$(readlink)` drops trailing newlines.** Two link targets that differ only
  by them hash alike. The code is unchanged: the residual-bound comment on
  `gate-inputs-hash` names it beside the file name that holds a newline.

The third-review record says the manifest follows a link's target for the
execute bit, and that a link's target losing the bit was among the assertions
written first. Only the opposite direction, `chmod +x` on the target, was in
`tests/gates-inputs-test.sh` then; `chmod -x` is pinned from this commit on.

The guard fix was written as a failing test first: two recipes in
`tests/gates-guards-test.sh` run in a directory whose only files an exclude
removes, one per spelling, and both were refused before the change. The link
tests added to `tests/gates-inputs-test.sh` are `chmod -x` on a link's target, a
dangling link added, and a dangling link repointed to another missing target.
With the `readlink` branch removed the dangling-link assertions fail, along with
the directory and file repointing ones; with the second round's `l` mode
restored in its place the execute-bit assertions fail. Removing the branch alone
leaves the execute-bit ones green, as it should: the `-x` test follows a link
without it.
