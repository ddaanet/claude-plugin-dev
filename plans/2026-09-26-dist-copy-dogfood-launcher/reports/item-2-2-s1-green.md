# Item 2.2 slice 1 — GREEN

## What changed

`toolkit/install.sh` step 3, existing-settings branch: the single jq program
became `add_hook event matcher command` (stdin to stdout; an empty matcher omits
the key; present = any entry under the event carries the command, whatever its
matcher). Three calls are chained in one pipeline into the tmp file:
version-guard (`Write|Edit`, `hook_cmd` spelling unchanged), pre-tool
(`Write|Edit|NotebookEdit`), session-start (no matcher). A pipeline failure
still errors, removes tmp and exits 1 with the file unchanged; writing is still
`cat > "$settings"` guarded by `cmp`. New commands carry SC2016 disables. The
header's step 3 and the `changed` line name the dogfood hooks. The no-settings
branch is untouched (version-guard only; slice 5).

## Assertions

The three slice-1 assertions passed together on the first implementation; the
implementation was written as one function, since all three calls share it.

- install adds the pre-tool hook once: pass
- install adds the session-start hook once: pass
- the commands quote the project dir: pass (2:2)

## Results

- `bash tests/update-plugin-dev-test.sh`: all scenarios passed
- `shellcheck toolkit/install.sh`: clean
- `just precommit`: green (one earlier run failed once in release-test.sh, the
  known intermittent; the rerun passed)
