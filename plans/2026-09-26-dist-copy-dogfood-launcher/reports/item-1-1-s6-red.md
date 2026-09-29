# Item 1.1/6 RED

Three tests added to tests/dogfood-test.sh (now 416 lines, over the 400 cap;
split decision at end of Phase 1). `bash -n` and `shellcheck` clean.
toolkit/dogfood.sh untouched (`git diff --quiet` passes).

## refuses without a root manifest: red on assertions
```
FAIL: no manifest exit code: expected '1', got '0'
FAIL: no manifest: stderr is not one dogfood: line naming the manifest: ''
FAIL: no manifest: the copy is not created: '.../my consumer/dist/plugin' exists
```

## refuses when dist/plugin is not ignored: red on assertions
The fixture asserts no dist/plugin exists before the sync (first-sync case).
```
FAIL: not ignored exit code: expected '1', got '0'
FAIL: not ignored: stderr is not one dogfood: line naming /dist/plugin/: ''
FAIL: not ignored: the copy is not created: '.../my consumer/dist/plugin' exists
```

## a git failure stops sync before rsync: already green
Passes against the committed SUT (1.1/1's fix). Discrimination proven by
mutation.

### Mutation proof
Moved `mkdir -p "$root/dist/plugin"` from before rsync to right after
`root="$(root_dir)"` (exact string replacement). Result:
```
=== a git failure stops sync before rsync ===
FAIL: a git failure: dist/ is not created: '.../my consumer/dist' exists
```
Only that test's assertion failed (other 6 failures are the two new refusal
tests). Restored by the swapped replacement;
`git diff --quiet toolkit/dogfood.sh` succeeded.
