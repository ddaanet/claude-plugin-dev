# One scope rule and a shared exempt reader for check-size and check-refs

Two checks skipped `plans/` by different mechanisms: `check-refs` as a default
that a `refs.exempt` replaced, so a consumer could bring plans back, and
`check-size` as a built-in that `size.exempt` refused to name. Each also carried
its own parser for the same list form.

Decided 2026-11-01 (option 1b of the plan): `plans/` is built in for both, as
`plugin-dev/` already was, and `check-refs`' default shrinks to
`docs/changelog`. No vendoring repo had a `refs.exempt`, so none loses anything.
A plan's links were already never required to resolve, so the one visible change
is that the pass line no longer counts `plans/` among the exempt files skipped.

The new sourced `toolkit/exempt-list.sh` holds the scope predicate and one
reader for `size.exempt` and `refs.exempt`: CR stripped, blank and `#` lines
skipped, blanks trimmed, one trailing `/` dropped, an optional ` # reason`. For
`refs.exempt` that means blanks around a path are trimmed and a ` # note` after
a path is a comment instead of part of the path. `dist.sh`'s `dist.include`
reader stays its own: it is a strict allowlist whose refusals are its contract.
