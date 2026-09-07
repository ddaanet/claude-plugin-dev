# 2026-09-07 — Two CLAUDE.md rules became static checks

`tests/doc-sync-test.sh` enforces two things CLAUDE.md had only stated.

**The two READMEs.** `README.md` presents this repo; `toolkit/README.md` is the
manual that ships in the dist tree. Both carry the install and update
instructions, and CLAUDE.md says a change to that flow has to land in both. Only
one of them ships, which is exactly why the other is easy to forget. The
same-day change that moved the first install to a `curl` of the dist tag's root
`install.sh` sharpened the case: the block is now written out in four places,
counting `install.sh`'s own header comment and
[references/distribution.md](../references/distribution.md).

The prose differs on purpose — different audience, different depth — so
comparing files would be noise. The check compares only the fenced code blocks
in the two "Installing in a plugin" and "Updating in a plugin" sections, and
requires every block in the root README to appear verbatim in the manual. That
is one-directional by construction, because the manual says more: it carries a
widened-`prerelease` example the root README expresses in prose. It still
catches an edit to *either* side of a block the two share, which is the drift
that actually happens. A renamed heading yields zero blocks and would pass
silently, so zero blocks is itself a failure.

It found real drift on its first run: the two copies of the
`just update-plugin-dev` block had diverged on comment alignment.

**CLAUDE.md's Layout list against `toolkit/`.** `tests/dist-tree-test.sh`
already pins the shipped tree exactly, so an added file is a deliberate edit
there. Nothing tied the prose to it — a file added to `toolkit/` and not to the
Layout list is invisible to the next session, and a bullet left behind after a
rename points at nothing. The check compares every backtick-quoted `toolkit/…`
path anywhere in CLAUDE.md (not just the Layout bullets: a path named under
Conventions should not go stale either) against `git ls-files toolkit/`, with
the same two exemptions dist-tree-test uses — `LICENSE`, which carries no
explanation worth a bullet, and `migrations/`, covered by the single `vX.Y.Z.md`
pattern bullet rather than named per release.

Both directions were probed by hand against a deliberately broken tree before
wiring the script into `precommit`: a divergent README block, a Layout path
renamed to something that does not exist, and an untracked-then-staged file
under `toolkit/` with no bullet. Each failed with the diff naming what moved.
