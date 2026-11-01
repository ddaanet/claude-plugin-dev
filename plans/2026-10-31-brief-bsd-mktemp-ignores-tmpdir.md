# Brief: bare `mktemp` fails inside the macOS command sandbox

From a plugin-craft session, 2026-10-31. A finding with a proposed fix, not a
decision.

## What happens

On macOS 26.6, `/usr/bin/mktemp` with no template (`mktemp`, `mktemp -d`,
`mktemp -t x`) creates its file under `_CS_DARWIN_USER_TEMP_DIR`
(`/var/folders/…/T/`) and uses `TMPDIR` only as a fallback — the man page says
so outright. The Claude Code command sandbox grants `TMPDIR` (`/tmp/claude-501`)
and not `/var/folders`, so every bare call fails with
`mkdtemp failed on /var/folders/…: Operation not permitted`.

Probed in the sandbox, `TMPDIR=/tmp/claude-501`:

```
mktemp -d                    mkdtemp failed on /var/folders/…: Operation not permitted
mktemp -t x                  mkstemp failed on /var/folders/…: Operation not permitted
mktemp -p "$TMPDIR"          /tmp/claude-501/tmp.BIpwU9JJjm
mktemp "$TMPDIR/x.XXXXXX"    /tmp/claude-501/x.4cEN0M
```

GNU `mktemp` honours `TMPDIR` for the bare form, which is why the same gates
pass sandboxed on Linux.

## What it breaks in a consumer

- `check-refs.sh:77` (`mktemp -d`): a consumer's `just precommit` fails at its
  first gate when an agent runs it through the Bash tool on macOS.
- `dist.sh:207` (`make_tmp`, reached by `tree`, `validate` and `paths`):
  plugin-craft's setup-status probe runs `dist.sh paths`, so its python check
  always skips under the macOS sandbox, and 8 of its bats tests fail there.

Also bare, on paths an agent can reach less often: `install.sh:201`,
`release-marketplace.sh:15`, `release-publish.sh:67`. `release` runs unsandboxed
by design, so those two matter only if that changes.

## Proposed fix

The form `run-bats.sh` and `dogfood.sh` already use:
`mktemp [-d] "${TMPDIR:-/tmp}/<name>.XXXXXX"`, Xs last, since BSD randomises
only a trailing run. A pin could run each script under a `mktemp` stub that
refuses a call with no template argument, in the manner of the
`bsd_portability.bats` stub `migrations/v0.11.0.md` mentions.

plugin-craft fixed its own call the same way and will take the toolkit fix
through `just update-plugin-dev` once a dist tag carries it.

## Second report, 2026-11-01

From a shell-gotchas session, a second brief reporting the same cause: on macOS
26 (Darwin 25.6) inside the sandbox, with the 0.14.0 dist vendored,
`just precommit` stops at `check-refs` (`toolkit/check-refs.sh:78`, now one line
down from the site named above) with `mkdtemp failed on /var/folders/…`. It adds
sites outside `toolkit/`: the root `justfile` (`mktemp` at line 92, `mktemp -d`
at 165) and most of `tests/`, where 54 files call `mktemp` and some
(`check-size-*-test.sh`) already use the template form. shell-gotchas takes the
fix through `just update-plugin-dev` once a dist tag carries it.
