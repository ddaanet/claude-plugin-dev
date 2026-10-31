# The size check names every source of linguist-generated

The manual said the size check read `linguist-generated` from `.gitattributes`.
A review probe showed otherwise. `git check-attr`, which the check runs, also
reads `.git/info/attributes` and the user's `core.attributesFile`, and a rule in
either one made an oversized file pass. Neither file is among the gate's hashed
inputs, so editing one does not invalidate a cached pass, and the result can
differ from one clone to the next.

This is a docs-only fix. The manual's scope-skip step and the size-check design
node now name every source `git check-attr` reads, and the manual says to set
the attribute in a committed `.gitattributes`. The code is unchanged.
