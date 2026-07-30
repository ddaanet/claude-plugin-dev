## Current task

Nothing in flight. The toolkit is released at v0.5.0, which is where
`resume-release` landed.

Propagating 0.5.0 into the consumer plugins is deliberately **not** tracked
here. Eight repos vendor the subtree — gitmoji, onekeys, gitlore,
shell-gotchas, cwd-safety, handoff, unsandbox-git-status, candidature — and
each carries an untracked `brief-plugin-dev-0.5.0.md` telling its own agent
how to migrate. Finding a consumer on an old `plugin-dev/VERSION` is expected
and is not work to pick up from this repo.
