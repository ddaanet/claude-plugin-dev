## Current task

`toolkit/update.sh` now takes a dirty gitlore memory gitlink out of the way
instead of refusing: a checkout ahead of HEAD's pointer is amended into a HEAD
no other ref holds or folded into the subtree merge, one behind is checked out
at the recorded commit, a diverged one refuses. Design nodes (`clean-tree.md`,
`distribution.md`, hub) are updated and every commit on `dev` has had its medium
review; my human partner took the defaults on every open question. The first
action is to invoke the `edify:release` skill on `dev` for a minor toolkit
release (not breaking, no migration note).
