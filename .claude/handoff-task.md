## Current task

One thread. Two briefs in `plans/` supersede the two ddaanet memory entries
about this toolkit by moving each fact to an artifact that already ships. The
release-diagnostics one landed earlier; so has the first-install invocation,
which is now a `curl` of the dist tag's root `install.sh` piped to
`bash -s -- "$tag"`, replacing the clone of the source tag into `/tmp/cpd`. That
one is recorded in both READMEs, in `install.sh`'s header comment, as its own
section in `docs/references/distribution.md` (where the old anti-`curl | bash`
rule is overturned, not narrowed, because its stated reason — inspectability —
was never performed), as a hub conclusion line, and in a dated changelog entry.
It was dogfooded end to end against a scratch plugin repo, not a fixture.

What remains is the second brief,
`plans/2026-09-02-brief-readme-absorbs-update-lore.md`: fold the vendoring and
update lore into `toolkit/README.md`, which a human's own install or update
request routes an agent to, then reduce `memory/ddaanet/claude-plugin-dev.md` to
whatever the README does not own. That file sits ~70 bytes under the 4KB recall
cap even after this session trimmed its install bullet, so the reduction is
overdue rather than optional.
