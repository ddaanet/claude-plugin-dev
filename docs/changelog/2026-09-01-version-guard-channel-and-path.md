# 2026-09-01 — version-guard: output channel, manifest location, edit shape

The half of the shell-gotchas audit that was deferred because it changes
the hook's output channel and needed its own test rewrite. Four defects,
all in `version-guard.sh`, all reproduced before being fixed.

**The deny JSON was written to stderr with `exit 2`, so neither channel
worked as designed.** Claude Code parses a hook's stdout as JSON and only
on exit 0; on exit 2 the stderr text is handed to the model verbatim. The
edit was still blocked — `exit 2` does that on its own — but
`permissionDecision`, `permissionDecisionReason` and `systemMessage` were
inert as structured fields. The human never saw the one-line notice, and
the agent got a single-line JSON blob with literal `\n` escapes instead of
the formatted refusal. The dual-channel design existed only on paper. The
JSON now goes to stdout with exit 0, where `permissionDecision: "deny"`
blocks the call the same way and additionally delivers `systemMessage`.

**`realpath -m` inverted the guard on macOS.** BSD realpath has no `-m`,
so both command substitutions in the manifest comparison produced empty
strings, `[[ "" == "" ]]` was true, and the `|| exit 0` never fired.
Every Write or Edit in a plugin repo fell through to the version
comparison: writing any file whose content carried a differing
`"version"` — a `package.json`, a fixture, a JSON snippet in docs — was
refused with a message naming a file the agent was not editing. The
highest-blast-radius item in the audit, because the toolkit ships for
macOS and Linux both and Linux CI cannot see it. Replaced with shell
absolutisation; the manifest path is built by the script rather than
supplied, so nothing was gained by resolving symlinks.

**The manifest was located from the payload `cwd`.** `cwd` tracks the
Bash tool's persistent shell, so once a session had `cd`-ed into a
subdirectory or `/add-dir`-ed elsewhere, the manifest was not where the
hook looked, and the "not my file" path exited 0 — a silent, complete
bypass with no message on either channel. It now reads
`CLAUDE_PROJECT_DIR`, which is stable for the session and is already what
`install.sh` wires the hook command around. No fallback to `cwd`: that
reintroduces the drift.

**An Edit of the bare version value passed the guard entirely.** The
branch grepped `new_string` for a `"version"` key, so `old_string:
"1.2.3"` / `new_string: "9.9.9"` — the shortest unique string, and the
form an agent reaches for first — produced no match and was allowed,
while the same semantic edit written with the key was blocked. The branch
now applies the edit to the manifest text and re-reads `.version` from
the result, which also retires the grep/sed-versus-jq asymmetry the
design doc used to explain. The substitution goes through jq's `split/1`,
a literal-string split: bash's `${text/pat/rep}` treats its pattern as a
glob, and `[`, `]` and `*` are ordinary characters in a JSON fragment.

`tests/hook-test.sh` could not have caught the first of these: both deny
scenarios captured with `2>&1`, so the assertions passed identically
whichever stream the JSON landed on. Its version-guard half was rewritten
around a helper that diverts stderr to a file and asserts on stdout
alone, plus an assertion that a deny writes nothing to stderr. Four
scenarios were added, each watched failing against the unchanged script
first: an Edit of the bare version value, a drifted payload `cwd`, a
repo-root-relative `file_path` (`tool_input.file_path` is whatever the
model emitted and is not always absolute), and a PATH-stubbed BSD
`realpath` that rejects `-m`, which makes Linux CI reproduce the macOS
inversion.
