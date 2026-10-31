# 2026-10-31 — The size check counts all bytes, not non-whitespace bytes

`check-size.sh` was written to count non-whitespace bytes, with a self-test that
refused an awk whose `length` counts characters. Before release, my human
partner decided the metric is the file's size as `wc -c` prints it. The caps
stay at 20000, and 10000 for a `SKILL.md`; what changes is what they mean.

## Changed

- **The metric is all bytes**, whitespace, indentation and newlines included,
  counted by one `wc -c` per file. A failure is
  `oversized-file: <path>: <n> bytes > <cap>`; the sign-off line starts
  `check-size: cap 20000 bytes:`.
- **The caps are derived from a token target**: about 10k tokens for a file and
  5k for a hub, as an agent reads it. At 2.052 bytes per token as the Read tool
  presents a file, 20000 bytes is about 9.7k tokens and 10000 about 4.9k.
- **The awk self-test is gone.** A byte count needs no awk character semantics.
- **The manual, the README stub, `release.just` comments, `CLAUDE.md`, the
  design hub, [size-check.md](../references/size-check.md) and the unreleased
  0.13.0 migration note** state the new metric.

## Reasoning

The token-fit report's pooled readtool fit puts bytes at a median absolute error
of 7.2% against 9.5% for non-whitespace bytes, and bytes win in 96% of
resamples. Raw, the two are indistinguishable (8.4% against 8.7%). The Read
tool's line-number prefix costs about 3.1 tokens a line, and all bytes track
line count through newlines and indentation, which non-whitespace bytes do not.

The previous cap was about 12k tokens as presented, looser than the 10k target.
Re-wrapping a file still barely moves its bytes, since a wrap swaps spaces for
newlines. Indentation is now counted, which is right, because the agent pays for
it. The earlier decision, in
[2026-10-31-size-check.md](2026-10-31-size-check.md), stands as the record of
how the non-whitespace metric was reached.
