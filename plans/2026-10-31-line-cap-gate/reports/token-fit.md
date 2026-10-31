# Token fit: lines, bytes, non-whitespace characters and words

Question: does a count of non-whitespace characters (nonws) predict a file's
token cost to Claude better than its line count does? This report measures that
and states where the answer does not favour the premise. Raw data, the scripts
and the working notes are in
`/Users/david/code/claude-plugin-dev/tmp/token-fit/` (git-ignored): `data.tsv`,
`analyze.py`, `analysis.out.md`.

## Method

Token counts come from `edify tokens`, which calls the count_tokens endpoint: no
model turn, no baseline to subtract, no sampling noise. The exact command, run
on batches of 25 files:

```sh
edify tokens --model opus --json FILE...
```

`--model opus` resolved to `claude-opus-5-5`. Two presentations per file:

- **raw**: the file as it is on disk.
- **readtool**: `cat -n -- FILE`, written to `tmp/token-fit/catn/NNN.txt` and
  counted the same way. Line number right-aligned in six columns, a tab, the
  line.

Every predictor (lines, bytes, nonws, words) is the **raw file's** metric on
both rows, recomputed from disk with the survey's own commands
(`LC_ALL=C.UTF-8`, `grep -Ic ''`, `wc -c`, `tr -d '[:space:]' | wc -m`,
`wc -w`). The question is what the agent pays when it reads a file, given a cap
that can only look at the file on disk. The source repositories were only read.

An edify count carries a constant overhead of 7 tokens (below), not subtracted.
Smallest file: about 800 tokens, so at most 1 percent.

### Earlier `claude -p` calls, not used in any fit

The brief first asked for `claude -p` probes. 105 were logged before the
coordinator switched the method: 99 on haiku ($0.2605), 6 on opus ($0.4808),
$0.7413 summed `total_cost_usd`; a 106th was in flight when the runner was
stopped and is not logged (its reply file exists, its cost is not summed). No
call failed. The shell script was `run.sh`, the log `calls.tsv`, the replies
`raw/NNN-*.json`. Command:

```sh
{ printf 'Reply with the single word ok.\n'; cat -n -- FILE; } |
  timeout 180 claude -p --model haiku --output-format json --tools "" \
    --strict-mcp-config   # usage: input + cache_creation + cache_read
```

Claude Code 2.1.316. Noise measured: 11 haiku baselines over 16 minutes, every
one 14522 tokens (sd 0); 3 opus baselines, every one 13747 (sd 0). So on this
machine the baseline did not drift at all. These numbers are used only as the
cross-check below.

### Sample

131 files, 2 to 25 KB, scope `gated` or `docs-md`, from 14 repositories
(`select_sample.py`, seeded): md 44 (30 prose-heavy, 14 with at least 20 percent
of lines inside a code fence or table), sh 24 (one `.bash` helper folded in),
bats 20, py 18, js/ts 14 (`.mjs`, `.ts`, `.tsx`), just 8, json 3. No yaml file
of that size exists; json has only 5 candidates, one a near copy. Within a type,
files are spread over nonws-per-line bins, and each stratum's lowest and highest
file are forced in. Identical files under two paths were dropped. Consequence:
extremes are over-represented against the population, so absolute error levels
(especially p90) read worse than a random draw would; the comparison between
predictors is the useful part.

## Tokenizer check

Edify, 4 files (three sample files and a one-line file `a\n`):

| file | haiku | opus |
|---|---:|---:|
| dogfood-sync-allowlist-test.sh | 6805 | 6805 |
| sandbox-lies SKILL.md | 4403 | 4403 |
| check-skills.py | 3544 | 3544 |
| `a\n` | 9 | 9 |

Haiku and opus agree exactly. The earlier `claude -p` run agreed too: on the
same three files haiku and opus differed by 0 tokens (4396, 6798, 3537 after the
baseline). Edify minus the `claude -p` delta is exactly +7 on 55 of 56 files
measured both ways, so edify equals the real prompt cost plus a fixed 7. The one
exception is `handoff/TODO.md` (-31), which changed on disk between the two
measurements (5631 bytes then, 5544 now); the edify row is the current file.

## Results

Fit: tokens = k*x, k = sum(xy)/sum(x^2), no intercept. R2 is centred (1 -
SSR/SST about the mean tokens); a through-origin fit flatters an
uncentred R2. APE is |predicted - measured| / measured; p90 by linear
interpolation. LOO refits k without the file being scored.

### Pooled fit, raw (n=131)

| x | k tok/unit | units/tok | R2 | med APE | p90 APE | LOO med |
|---|---:|---:|---:|---:|---:|---:|
| lines | 17.90 | 0.056 | 0.874 | 13.3% | 32.3% | 13.5% |
| bytes | 0.4164 | 2.402 | 0.961 | 8.4% | 19.1% | 8.4% |
| nonws | 0.5135 | 1.948 | 0.956 | 8.7% | 23.0% | 8.9% |
| words | 3.020 | 0.331 | 0.863 | 15.7% | 33.8% | 16.0% |

### Pooled fit, readtool (n=131)

| x | k tok/unit | units/tok | R2 | med APE | p90 APE | LOO med |
|---|---:|---:|---:|---:|---:|---:|
| lines | 21.06 | 0.047 | 0.909 | 11.3% | 27.9% | 11.4% |
| bytes | 0.4873 | 2.052 | 0.961 | 7.2% | 18.5% | 7.3% |
| nonws | 0.6006 | 1.665 | 0.951 | 9.5% | 23.0% | 9.5% |
| words | 3.528 | 0.283 | 0.850 | 16.8% | 36.6% | 17.1% |

Paired bootstrap over files (2000 resamples, k refitted each time): median APE
of nonws minus that of the other predictor, percentage points (negative: nonws
better).

| vs | raw: mean [95% interval] | nonws better | readtool: mean [95%] | nonws better |
|---|---|---:|---|---:|
| lines | -4.8 [-9.1, -0.8] | 99% | -2.2 [-5.7, +1.3] | 89% |
| bytes | +0.5 [-1.2, +2.3] | 32% | +1.8 [-0.2, +3.3] | 4% |
| words | -7.0 [-10.2, -3.9] | 100% | -7.1 [-10.3, -4.1] | 100% |

### Per-type k, each type fitted alone

Tokens per line, and units per token (1/k). A predictor whose per-type k is
stable lets one cap treat types alike.

| type | n | raw tok/line | bytes/tok | nonws/tok | rt tok/line | bytes/tok | nonws/tok |
|---|---:|---:|---:|---:|---:|---:|---:|
| md | 44 | 18.4 | 2.56 | 2.12 | 21.6 | 2.19 | 1.81 |
| sh | 24 | 20.3 | 2.23 | 1.81 | 23.3 | 1.94 | 1.57 |
| bats | 20 | 19.8 | 2.10 | 1.71 | 22.9 | 1.82 | 1.48 |
| py | 18 | 14.6 | 2.52 | 1.94 | 17.7 | 2.07 | 1.60 |
| just | 8 | 19.0 | 2.48 | 1.93 | 22.0 | 2.14 | 1.67 |
| json | 3 | 11.7 | 2.37 | 1.38 | 14.7 | 1.89 | 1.10 |
| js/ts | 14 | 17.2 | 2.29 | 1.87 | 20.3 | 1.94 | 1.59 |
| md prose | 30 | 18.9 | 2.65 | 2.20 | 22.0 | 2.28 | 1.90 |
| md code/tbl | 14 | 17.8 | 2.41 | 1.97 | 21.0 | 2.04 | 1.68 |
| all non-md | 87 | 17.6 | 2.29 | 1.82 | 20.7 | 1.95 | 1.55 |

(rt = readtool.) Spread of per-type k over the seven types (max/min, and
coefficient of variation), with and without json, whose 3 files sit alone at the
extreme:

| x | raw all | raw w/o json | rt all | rt w/o json |
|---|---|---|---|---|
| lines | 1.74 / 17% | 1.39 / 10% | 1.59 / 14% | 1.32 / 9% |
| bytes | 1.22 / 7% | 1.22 / 7% | 1.21 / 6% | 1.21 / 7% |
| nonws | 1.54 / 14% | 1.24 / 7% | 1.65 / 16% | 1.23 / 6% |
| words | 2.48 / 34% | 1.33 / 12% | 2.66 / 38% | 1.39 / 13% |

### Fairness: median APE per type under the one pooled k

| type | n | raw lines | bytes | nonws | rt lines | bytes | nonws |
|---|---:|---:|---:|---:|---:|---:|---:|
| md | 44 | 16 | 10 | 13 | 14 | 12 | 14 |
| sh | 24 | 13 | 7 | 8 | 11 | 5 | 6 |
| bats | 20 | 11 | 13 | 13 | 9 | 12 | 12 |
| py | 18 | 19 | 5 | 5 | 16 | 3 | 4 |
| just | 8 | 7 | 2 | 3 | 5 | 3 | 4 |
| json | 3 | 50 | 9 | 30 | 41 | 11 | 35 |
| js/ts | 14 | 10 | 7 | 5 | 9 | 6 | 7 |
| md prose | 30 | 18 | 12 | 15 | 15 | 14 | 17 |
| md code/tbl | 14 | 10 | 8 | 8 | 8 | 5 | 8 |

Signed mean error under the pooled k, raw (positive: the cap would think the
file costs more than it does; readtool is within 4 points of these except json,
where it is +42 lines, -8 bytes, -34 nonws):

| type | lines | bytes | nonws |
|---|---:|---:|---:|
| md | -8% | +10% | +12% |
| md prose | -11% | +12% | +15% |
| md code/tbl | 0% | +4% | +6% |
| sh | -10% | -8% | -8% |
| bats | -8% | -14% | -14% |
| py | +21% | +4% | -2% |
| json | +52% | -2% | -30% |

Each type fitted alone (own k) the median APE falls to 3-14 percent for every
predictor, md 14/6/6 (lines/bytes/nonws, raw). The pooled-k gap is the
cross-type unfairness; the own-k gap is how much a per-type constant would fix.

Largest errors under the pooled k, raw (npl = nonws per line): lines: `TODO.md`
(md, 396 nonws per line) 90%, `raw_nodes.py` (py, 18) 78%, `rules.md` (md, 135)
76%, `fixtures.ts` (js/ts, 123) 71%; nonws: `hooks.json` (json, 13) 36%, the
other `hooks.json` 30%, then md files at 25-30%; bytes: nothing above 28%.

### What a cap admits

Tokens of a file at 400 lines (own tok/line * 400), against tokens of a file at
the nonws count the pooled raw fits equate to 400 lines (13945 nonws, 7160
tokens), each type at its own k:

| type | at 400 lines | at 13945 nonws |
|---|---:|---:|
| md prose | 7539 | 6329 |
| sh | 8109 | 7721 |
| bats | 7929 | 8173 |
| py | 5827 | 7201 |
| json | 4666 | 10129 |

Without json the range is 5827-8109 (1.39x) under the line cap and 6329-8173
(1.29x) under the nonws cap.

### Two predictors: tokens = a*nonws + b*lines

share = sum(b*lines) / sum(tokens), the part of the cost attributed to the line
term. "1-pred" is the nonws-only fit's median APE.

| group | n | raw a | b tok/line | share | 2-pred | 1-pred |
|---|---:|---:|---:|---:|---:|---:|
| pooled | 131 | 0.376 | 4.96 | 27% | 7.4% | 8.7% |
| md | 44 | 0.336 | 5.49 | 28% | 7.1% | 6.2% |
| sh | 24 | 0.397 | 5.82 | 29% | 2.3% | 5.6% |
| bats | 20 | 0.462 | 4.28 | 22% | 2.1% | 4.1% |
| py | 18 | 0.490 | 0.76 | 5% | 4.7% | 4.7% |
| just | 8 | 0.402 | 4.29 | 23% | 3.2% | 3.1% |
| js/ts | 14 | 0.494 | 1.31 | 7% | 2.2% | 2.8% |

| group | n | rt a | b tok/line | share | 2-pred | 1-pred |
|---|---:|---:|---:|---:|---:|---:|
| pooled | 131 | 0.374 | 8.20 | 38% | 6.2% | 9.5% |
| md | 44 | 0.331 | 8.90 | 40% | 6.0% | 7.9% |
| sh | 24 | 0.399 | 8.84 | 38% | 2.1% | 6.0% |
| bats | 20 | 0.460 | 7.48 | 33% | 2.1% | 4.9% |
| py | 18 | 0.487 | 4.04 | 22% | 4.0% | 3.2% |
| just | 8 | 0.401 | 7.38 | 34% | 2.5% | 4.1% |
| js/ts | 14 | 0.492 | 4.50 | 21% | 1.8% | 4.5% |

The same fit with bytes in place of nonws gives pooled b of 3.54 (raw) and 6.81
(readtool) tokens per line, med APE 8.2 and 6.9 percent. The line and nonws
columns are correlated, so single b values carry sampling error that this report
did not estimate.

### Cost of the Read-tool prefix

Paired: readtool tokens minus raw tokens, same file. Across all 131 files: 3.16
extra tokens per line (through the origin), median 3.13, min 3.00, max 3.42; 17
percent of the raw tokens at the median (2 to 32 percent). Per type the median
is 3.09-3.19 (json 3.00 exactly). Files under 100 lines and files of 100-999
lines both sit at 3.13. No file here has 1000 lines.

## Conclusion

### Measured

- Tokens per nonws character: 0.51 pooled raw (1.95 characters per token), per
  type from 0.45 (md prose) to 0.73 (json). Bytes per token: 2.40 pooled. Tokens
  per line: 17.9 pooled raw, 21.1 as the Read tool shows it.
- Pooled, raw: median APE lines 13.3%, words 15.7%, nonws 8.7%, bytes 8.4%.
  Readtool: lines 11.3%, nonws 9.5%, bytes 7.2%, words 16.8%.
- Against lines, nonws wins raw by 4.8 points of median APE (interval -9.1 to
  -0.8) and readtool by 2.2 (interval -5.7 to +1.3, so not clear of zero).
  Against bytes it does not win: +0.5 raw (indistinguishable) and +1.8 readtool
  (bytes better in 96 percent of resamples). Against words it wins by 7 points
  in both.
- Per-type stability, excluding the 3 json files: bytes per token 1.22x max/min,
  nonws 1.24x, lines 1.39x (raw). With json in, nonws is 1.54x and lines 1.74x,
  bytes still 1.22x. Json is the one type nonws treats worst (30 percent low in
  the mean; punctuation tokens are short, so characters per token fall to 1.4).
- Where lines fail worst: files whose lines are unusually long or short
  (`TODO.md` at 396 nonws per line is 90 percent off; a 18-per-line py file 78
  percent). These are the cases nonws and bytes repair. Within the ordinary
  range (about 20 to 55 nonws per line) the line count's median error is 7 to 19
  percent by type, mostly a bias: py is over-predicted by lines (+21 percent
  mean), md prose under-predicted (-11), sh and bats under (-8 to -10).
- Whitespace and line structure do cost tokens. Bytes (which include whitespace)
  fit at least as well as nonws, and md prose is the clearest case: nonws
  over-predicts it by 15 percent and bytes by 12, where lines under-predict by
  11. A line term added to nonws cuts the pooled median APE from 8.7 to 7.4
  percent raw and from 9.5 to 6.2 readtool.
- The per-line term is type-dependent in raw text: about 4-6 tokens per line in
  md, sh, bats and just (22-29 percent of the cost), under 1.5 in py and js/ts
  (5-7 percent). As the Read tool shows it, every file gains 3.1 tokens per
  line, nearly independent of type and file length, and the line term rises to
  4-9 tokens per line (19-40 percent of cost).

### Interpretation

- The premise holds against lines and does not extend to bytes. Nonws is a
  better size proxy than lines mainly because lines ignore line length; but the
  whitespace that nonws drops is not free, and dropping it left the md prose
  bias larger than keeping it did. On this sample no measured gain separates
  nonws from a plain byte cap, and the byte cap has the more stable per-type
  ratio.
- The Read-tool presentation does not rescue nonws: the line-number prefix is a
  cost per line of about 3 tokens that a cap on raw characters cannot see, and
  it favours a line term (or a byte cap, which carries it implicitly through
  newlines and indentation). It also narrows the gap between lines and nonws,
  since lines now pay for the prefix: readtool lines and nonws differ by 2
  points, not clear of zero.
- A single nonws cap is fairer across code and prose than a line cap (1.24x
  against 1.39x without json), though the margin is small and, with 3 json
  files, not established for json.
- Limits: 131 files, stratified with forced extremes; files over 25 KB and under
  2 KB are not covered; json n=3, just n=8; one tokenizer generation (both
  models agree, other generations untested); the proportional fit has no
  intercept, so the constant 7-token overhead sits in the error; the
  repositories sampled are one author's, mostly Markdown, shell and Python.
