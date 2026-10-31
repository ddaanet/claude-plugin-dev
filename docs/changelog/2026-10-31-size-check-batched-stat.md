# 2026-10-31 — The size check reads sizes with one batched stat

Counting all bytes with one `wc -c` per file made `check-size.sh` about 2.8 s on
gitlore, against well under a second for the awk pass it replaced. My human
partner pointed out that a byte count needs no read of the file: `stat` gives it
from metadata, and the GNU and BSD forms can be told apart once, at load time,
by whether `stat --version` exits 0.

## Changed

- **One batched `stat` replaces the per-file `wc -c`**: `stat -c %s --` under
  GNU coreutils, `stat -f %z --` otherwise, fed NUL-delimited through
  `xargs -0`. The gitlore run drops to about 0.35 s, measured on Linux under
  load.
- **A stat failure, or a count of output lines unequal to the file list, fails
  the run** with `check-size: counting failed`, as a failed `wc` did.
- **The metric is unchanged**: for a regular file `stat` reports the count
  `wc -c` prints.
- The report suite pins both flavours with stub `stat` commands, so neither
  branch is skipped on the other platform.
