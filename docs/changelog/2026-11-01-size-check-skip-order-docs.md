# The size check documents its skip order and a rule for attribute sources

Commit 10666bd moved the built-in skip ahead of the `linguist-generated` lookup,
so `git check-attr` is asked only about the paths no built-in took. A file
either one would take is still skipped once, and the skip outcome is unchanged.
The manual and the size-check design node said the generated step came first;
both now list the built-ins before it.

The attribute-source passage in both places gave an enumerated list of the files
`git check-attr` reads. It now gives a rule instead: only a committed
`.gitattributes` is the same in every clone, so the attribute belongs there.

The manual's failure paragraph claimed every failure to list, read or measure
the tree ends the run with one stderr line. It now says only what the code does:
a failure the check detects ends with a `check-size: <reason>` line after
whatever the failing tool printed, and an unreadable file is skipped, not
failed. The code is unchanged.
