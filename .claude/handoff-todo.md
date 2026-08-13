## Remaining

- Run `just release` (confirm bump size first, unsandboxed) to cut the
  new toolkit version.
- For each of the 8 sibling consumers, check `brief-plugin-dev-0.5.0.md`:
  drop it if already upgraded past 0.5.0, otherwise update it to
  reference the new version — carrying the <0.5.2 bootstrap workaround
  from `brief-update-plugin-dev-bootstrap-gap.md`, not the "go straight
  to vX.Y.Z" framing.
