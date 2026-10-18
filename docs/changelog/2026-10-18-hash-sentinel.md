# 2026-10-18 — Gate sentinels: `hash-sentinel` re-hashes after a formatter

A gate whose formatter rewrites inputs had two placements and both cost a run.
As a recipe dependency, ahead of the guard, the formatter ran on every call,
cached or not. Moved into the body after the guard, it was skipped on a cached
run, but its edits moved the inputs away from the hash the guard took, so
`record-sentinel` withheld the pass as "inputs changed while the checks ran",
and only a second run, with nothing left to format, recorded it. ghmem's
`run-format` sits in the first placement for that reason.

## Added

- **`hash-sentinel` in the prolog.** Called after the formatter and before the
  checks, it re-takes `guard_hash` through `gate-inputs-hash`, so the pass
  records the formatted tree in the same run and a cached run skips the
  formatter. The peer-edit protection is unchanged: the checks start after the
  re-hash, and an input that moves while they run still withholds the pass.
- **Its refusals.** With no guard earlier in the body it exits 1, mirroring
  `record-sentinel`. A re-hash that fails empties `guard_hash`, so
  `record-sentinel` refuses as for any uncomputable hash rather than comparing
  against the guard's pre-format hash.
- **`tests/gates-hash-test.sh`.** A formatter edit recorded in one run and the
  next run cached without formatting; the same recipe without `hash-sentinel`
  not recorded (the behaviour it replaces, pinned); no guard refused; a failed
  re-hash refused; an input moved after the re-hash not recorded.

Opt-in, with no variable renamed, so no migration note: a gate that does not
call it behaves as before.
