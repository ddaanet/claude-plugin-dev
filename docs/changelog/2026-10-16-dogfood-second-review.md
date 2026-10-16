# 2026-10-16 — The second review of the dogfood no-copy warning

A review of the commit that moved the no-copy warning from the shim to
`session-start` (see
[the unconditional-shim entry](2026-10-16-dogfood-shim-unconditional.md)) found
one assumption unprobed and four loose ends. That entry stays as written; this
one records the round.

## What changed

- The assumption: the named-but-no-directory branch, which tells the user to run
  `just dogfood` and then `/reload-plugins`, rests on a
  `CLAUDE_CODE_PLUGIN_DIRS` entry naming a missing directory reaching a
  `SessionStart` hook unchanged. Probed on CC 2.1.301 with the real binary, a
  throwaway `CLAUDE_CONFIG_DIR` and `claude -p 'reply ok' --max-turns 1`. A
  `SessionStart` hook wrote the variable to a file, once from a plugin's
  `hooks/hooks.json` and once from project settings. It held the launch value
  verbatim: a missing absolute entry with a space in its name after a real
  plugin directory, and a lone missing entry. The hook fires before any model
  call, so the run needed no login. The branch stands. The probe needed the
  throwaway config directory because the command sandbox makes
  `~/.claude/session-env` read-only, which fails every hook with `EROFS`.
- `toolkit/dogfood.sh`: the header's usage block now lists the named-but-no-
  directory warning beside the other two. The two no-copy branches built the
  same `additionalContext` literal; it is computed once and only the
  `systemMessage` differs.
- `CLAUDE.md` and `toolkit/README.md` said the shim is silent. It still prints
  `dogfood: no other claude on PATH` and exits 127, so both now say it never
  warns about a missing copy, which `session-start` does.
- The named-no-copy message, for an absent directory and for a regular file at
  `dist/plugin`, is pinned in `tests/dogfood-session-warn-test.sh`. The earlier
  entry credits the session-start suite with it; the warning scenarios moved to
  the warn suite, and the session-start suite keeps the silent cases and the
  `jq`-less message.
