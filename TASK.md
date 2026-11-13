## Current task

check-frontmatter resolves the venv itself: it tries `<top>/.venv/bin/python3`,
then `python3` on PATH, so a shell or hook without direnv still runs it. Red
test and doc sweep dispatched; then red review, green, gate, commit,
`/code-review medium`. Not breaking: no migration note. Ships in the next
toolkit release.
