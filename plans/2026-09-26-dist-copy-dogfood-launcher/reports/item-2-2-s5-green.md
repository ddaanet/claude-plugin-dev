# Item 2.2/5 GREEN — a fresh settings.json carries all three hooks

## What changed

`toolkit/install.sh` step 3: the separate `jq -n` no-settings document is gone.
The input is the existing `settings.json`, or `{}` when absent, piped through
the same three `add_hook` calls. One failure branch remains: it removes the tmp
file, errors `could not rewrite … left unchanged` and exits 1, so no stub is
ever written over a consumer's file. `cat > "$settings"`, the `cmp` guard and
`mkdir -p .claude` are untouched. The step-3 comment now states the unified
shape and why a failure never falls through to a stub.

## Order made to pass

1. `a fresh settings.json carries version-guard and the pre-tool hook under PreToolUse`:
   red before, green after.
2. `a fresh settings.json carries the session-start hook with no matcher`: red
   before, green after. Both passed from the single change.

## Results

- `bash tests/update-plugin-dev-test.sh`: all scenarios passed.
- `shellcheck toolkit/install.sh`: clean.
- `just precommit`: green (no warnings).
