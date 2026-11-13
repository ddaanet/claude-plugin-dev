## Current task

Release the toolkit as 0.16.2. On `dev`, ahead of `main`, is the
check-frontmatter change: it tries `<top>/.venv/bin/python3` first, then
`python3` on PATH, so a shell or hook without direnv still runs it. That change
has had its per-commit medium review and the doc-drift fix that review called
for, but no release review. It is not breaking, so it needs no migration note.
The first action is to invoke the `release-ritual` skill on `dev`.
