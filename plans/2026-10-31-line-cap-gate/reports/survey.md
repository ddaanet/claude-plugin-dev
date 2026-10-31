# Line-cap survey: what a character cap holds against 400 lines

Analysis of `tmp/line-cap-survey/*.tsv` (14 repos); it reports and does not
choose a factor. Each table is a section of `survey/analyse.py` (named in the
heading or caption), run as `python3 -I analyse.py <section>`.

## 0. Conventions

- **Governed set**: scope `gated` plus `docs-md`, 1243 files. `plans` and
  `changelog` rows never enter a count. cpd = claude-plugin-dev.
- **n/l** is nonws per line; **agg** is total nonws over total lines;
  percentiles and medians are per file, over files with at least 100 lines
  unless stated.
- **Type groups**: `sh` folds in `.bash` helpers (45) and extensionless shell
  scripts; `js/ts` is mjs, ts, tsx; `json` adds jsonl; `config` is toml, yml,
  cfg, dotfiles, `*.include` and the commit template; `other` is extensionless
  non-shell files (14 of 23 are one-line `gitlore-hook-setup`) and one awk file;
  `code*` is sh, bats, py, just, js/ts.
- **Candidates**: A pooled median, B md median, C sh median, D bats median, E py
  median (added), F pooled p75; G, H, I are the largest nonws of a file at most
  400 lines: G in cpd (`docs/design.md`, 20243), H in 14 repos (handoff
  `uv.lock`, 63566), I as H without lock files (handoff `docs/changelog.md`,
  50482). Cap = f x 400 rounded to 500; G, H, I round up to stay no-regression.
- **in** = compliant today (at most 400 lines), fails under the cap. **out** =
  fails today, passes under it. Only cpd has the gate; for the other 13 repos
  "fails today" means "would fail".
- **adj**, a labelled sensitivity: governed minus the 8 lock files and the 27
  `docs/superpowers/` files (plans the survey filed as `docs-md`, in candidature
  and ghmem). 12 of the 22 files over 400 lines today are these.

## 1. Per type, pooled over repos (section `types`)

all governed files (nonws/line; agg = total nonws / total lines)

| group  | files |  lines |   agg |   p50 |  p10 |  p25 |   p75 |   p90 |
|:-------|------:|-------:|------:|------:|-----:|-----:|------:|------:|
| md     |   325 |  56972 |  46.2 |  43.9 | 34.7 | 38.3 |  50.5 |  56.9 |
| sh     |   302 |  47513 |  36.3 |  35.9 | 28.6 | 31.9 |  40.6 |  45.5 |
| bats   |   204 |  42594 |  33.4 |  32.6 | 26.7 | 29.6 |  36.0 |  39.9 |
| py     |   134 |  29183 |  29.3 |  29.3 | 24.2 | 26.8 |  31.2 |  33.2 |
| just   |    16 |   1523 |  36.4 |  33.7 | 23.6 | 29.1 |  36.3 |  40.5 |
| js/ts  |    38 |   2760 |  33.6 |  33.4 | 26.6 | 29.5 |  36.8 |  41.0 |
| json   |    79 |   1999 |  33.8 |  21.2 | 12.4 | 13.3 | 105.2 | 207.4 |
| config |    79 |   1010 |  24.3 |  24.2 |  8.0 | 12.4 |  29.2 |  30.7 |
| txt    |    35 |   1084 |  71.5 |  40.3 | 27.5 | 33.5 |  52.5 | 161.9 |
| lock   |     8 |   1630 | 155.2 | 146.0 | 78.3 | 80.2 | 183.4 | 208.3 |
| other  |    23 |    230 |  36.4 |   6.0 |  6.0 |  6.0 |  42.8 |  42.8 |
| code*  |   694 | 123573 |  33.6 |  33.2 | 26.5 | 29.4 |  37.2 |  42.3 |
| ALL    |  1243 | 186498 |  38.7 |  34.7 | 23.3 | 29.4 |  42.2 |  50.7 |

governed files with >=100 lines (nonws/line; agg = total nonws / total lines)

| group  | files |  lines |   agg |   p50 |   p10 |   p25 |   p75 |   p90 |
|:-------|------:|-------:|------:|------:|------:|------:|------:|------:|
| md     |   199 |  50969 |  46.0 |  45.1 |  35.7 |  39.9 |  50.1 |  53.7 |
| sh     |   177 |  41257 |  36.3 |  35.8 |  29.1 |  32.2 |  39.6 |  43.4 |
| bats   |   171 |  40342 |  33.6 |  33.1 |  27.1 |  30.1 |  36.3 |  40.6 |
| py     |   103 |  27462 |  29.3 |  29.3 |  24.5 |  27.0 |  31.1 |  32.9 |
| just   |     6 |   1156 |  37.4 |  35.8 |  31.9 |  33.9 |  40.0 |  41.7 |
| js/ts  |     8 |   1340 |  33.3 |  34.7 |  27.6 |  32.1 |  36.4 |  38.1 |
| json   |     2 |    235 |  14.5 |  14.5 |  13.2 |  13.7 |  15.3 |  15.8 |
| config |     2 |    281 |  27.8 |  27.7 |  26.0 |  26.6 |  28.7 |  29.4 |
| txt    |     3 |    661 |  59.1 |  61.5 |  54.0 |  56.8 |  67.6 |  71.3 |
| lock   |     5 |   1532 | 160.1 | 175.1 | 144.6 | 153.3 | 208.3 | 208.3 |
| code*  |   465 | 111557 |  33.6 |  33.2 |  26.7 |  29.6 |  36.9 |  41.3 |
| ALL    |   676 | 165235 |  38.6 |  35.5 |  27.5 |  30.9 |  42.2 |  49.6 |

`json`, `config`, `txt` have 2 to 3 files at 100 lines and say little; `lock`
n/l is 145 to 208; small files add noise (`json` p90 207, `other` p50 6.0: the
one-line hook-setup files). Within a type, p10 to p90 spans about plus or minus
20% of the median (md 35.7 to 53.7 around 45.1).

## 2. Per repo by type (section `repotype`)

Cells are `n:median n/l`, files with at least 100 lines; repos with fewer than 3
such files are omitted (onekeys, prompt-fzf).

| repo              |    md |    sh |   bats |    py | just | js/ts |    ALL |
|:------------------|------:|------:|-------:|------:|-----:|------:|-------:|
| claude-plugin-dev | 17:47 | 65:35 |      - |     - | 2:39 |     - |  84:37 |
| candidature       | 55:41 |  1:23 |      - |  9:30 |    - |  6:36 |  71:38 |
| craft             | 10:45 |     - |      - |  2:31 |    - |     - |  13:44 |
| cwd-safety        |  6:47 |     - |      - |  2:41 | 1:33 |     - |   9:47 |
| ghmem             | 23:41 |  3:35 |   7:30 | 61:30 | 1:30 |     - |  98:31 |
| gitlore           | 37:50 | 53:39 | 103:33 |  3:28 | 1:42 |     - | 199:37 |
| gitmoji           |  3:39 |  4:34 |      - |     - |    - |     - |   7:34 |
| handoff           | 18:51 | 10:36 |  20:37 | 24:28 | 1:36 |  1:34 |  76:36 |
| plugin-craft      |  9:51 |  4:29 |   5:23 |     - |    - |     - |  18:40 |
| prohibitions      |  2:50 | 23:35 |      - |     - |    - |     - |  26:35 |
| sandbox-lies      | 12:50 | 12:34 |  36:32 |  2:32 |    - |     - |  64:34 |
| shell-gotchas     |  7:47 |     - |      - |     - |    - |     - |   8:48 |

Between repos, cells with at least 9 files: md 41 to 51, sh 34 to 39, bats 32 to
37, py 28 to 30. Thin cells (plugin-craft bats 5:23) are not a pattern.

## 3. The near-cap cohort (governed files with 300 to 400 lines)

Section `cohort` (`cohort-full` lists every repo's files). The cpd list is in
full: the cap is enforced there.

| repo                   |   n | med L | med nonws | max nonws |  n/l |
|:-----------------------|----:|------:|----------:|----------:|-----:|
| claude-plugin-dev      |  40 |   340 |     12808 |     20243 | 37.2 |
| ghmem                  |  33 |   355 |     11087 |     15471 | 30.3 |
| gitlore                |  45 |   353 |     12935 |     25135 | 38.8 |
| handoff                |  17 |   352 |     12209 |     63566 | 34.7 |
| sandbox-lies           |  22 |   358 |     11983 |     19881 | 32.9 |
| 5 repos with n<10 each |  10 |   348 |     12634 |     18056 | 39.4 |
| ALL (no lock)          | 166 |   352 |     12429 |     25135 | 34.8 |

cohort nonws by type

| set               | type |  n |   p10 |   p50 |   p90 |   max |
|:------------------|:-----|---:|------:|------:|------:|------:|
| 14 repos, no lock | md   | 33 | 12868 | 16502 | 19868 | 25135 |
| 14 repos, no lock | sh   | 56 | 10416 | 12776 | 15034 | 17451 |
| 14 repos, no lock | bats | 42 |  9654 | 11772 | 13690 | 16451 |
| 14 repos, no lock | py   | 34 |  8739 | 10058 | 12336 | 12558 |
| claude-plugin-dev | md   |  5 | 13359 | 17222 | 20072 | 20243 |
| claude-plugin-dev | sh   | 35 | 10506 | 12528 | 14321 | 17123 |

claude-plugin-dev cohort, 40 files, largest nonws first down the left column
then the right; name, lines, nonws, nonws/line; t/ = tests/ with -test.sh
dropped, d/ = docs/, ref/ = references/, k/ = toolkit/

```text
d/design.md              397 20243 51.0  t/self-release-publish   361 12804 35.5
d/ref/recovery.md        385 19815 51.5  t/release-dist-publish   370 12665 34.2
CLAUDE.md                340 17222 50.7  t/dogfood-sync-allowlist 304 12528 41.2
k/release-tags.sh        365 17123 46.9  t/dist-subcommands       362 12491 34.5
t/release-lost-tag       367 14916 40.6  t/dogfood-pre-tool-paths 332 12369 37.3
t/version-guard-git      348 14695 42.2  scripts/self-release.sh  328 12169 37.1
t/release-resume-hint    362 14361 39.7  t/release-push-route     332 12145 36.6
t/install-legacy         342 14260 41.7  t/update-plugin-dev      316 12127 38.4
d/ref/release-flow.md    300 14181 47.3  t/dogfood-sync-refusal   341 11912 34.9
t/release-core           355 13942 39.3  t/release-dist-resume    349 11593 33.2
k/dogfood.sh             389 13771 35.4  t/dogfood-session-start  305 11526 37.8
t/dogfood-sync-copy      363 13681 37.7  t/release-pipefail       313 11391 36.4
t/release-dist-refusal   384 13408 34.9  t/dist-build             347 11152 32.1
t/self-release-refusal   387 13164 34.0  t/gates-guards           361 11043 30.6
t/release-dist-optin     375 13011 34.7  t/release-hint-size      315 10874 34.5
t/install-vendor         319 13004 40.8  t/dogfood-launcher-path  318 10614 33.4
t/version-guard-wording  307 12988 42.3  t/dogfood-pre-tool-jq    302 10434 34.5
t/release-tree           334 12974 38.8  t/dist-warning           330  9746 29.5
t/release-rollback       325 12842 39.5  t/gates-sentinel         300  8624 28.7
k/README.md              309 12811 41.5  k/dist.sh                301  8252 27.4
```

What 400 lines holds in practice: the cpd cohort is 35 shell scripts (8.3k to
17.1k nonws, median 12.5k) and 5 markdown files (12.8k to 20.2k). The pooled
cohort sits at a median of 352 lines, 88% of the cap, and its median nonws per
type is 0.86 to 0.92 of 400 x the type median n/l from section 1. cpd's
`docs/design.md` (397 lines, 20243) is its largest.

**Split to a cap elsewhere?** Section `splitcap`: files per 20-line band
(header = band start, so 380 is 380 to 400); l/sp = of the >400 files, lock
files or `docs/superpowers/`; repos with under 3 files in or above the bands are
omitted (6 small ones).

| repo              | files | 340 | 360 | 380 | 401 | 421 | 441 | >400 | l/sp |
|:------------------|------:|----:|----:|----:|----:|----:|----:|-----:|-----:|
| claude-plugin-dev |   113 |   7 |   9 |   5 |   0 |   0 |   0 |    0 |    0 |
| candidature       |   136 |   1 |   0 |   0 |   0 |   0 |   0 |    7 |    6 |
| cwd-safety        |    27 |   0 |   0 |   1 |   0 |   0 |   0 |    2 |    0 |
| ghmem             |   166 |   8 |   5 |  11 |   1 |   1 |   1 |    8 |    6 |
| gitlore           |   316 |   7 |  11 |   8 |   0 |   0 |   0 |    0 |    0 |
| handoff           |   115 |   5 |   2 |   4 |   0 |   0 |   0 |    2 |    0 |
| prohibitions      |    56 |   0 |   0 |   0 |   0 |   1 |   1 |    3 |    0 |
| sandbox-lies      |   137 |   3 |   5 |   6 |   0 |   0 |   0 |    0 |    0 |

gitlore (316 files, none over 400, 26 in the three bands below the cap) and
sandbox-lies (137 files, none over, 14 below) show cpd's cliff. handoff was
split recently (its brief names a 3985-line `tests/hook-test.bats`, now absent);
its two files over 400, `CLAUDE.md` and `tests/test_checkpoint_legacy.py`, match
the two exemptions the brief describes. ghmem piles up too (11 files at 380 to
400, mostly py) but has 8 over 400, 6 of them superpowers plans or `uv.lock`.
candidature, prohibitions and cwd-safety (7, 3, 2 over) show no cliff.

## 4. Candidate caps

Section `candidates`. over = files above the cap; in, out as in section 0; all
for 14 repos except cpdIn (in, cpd only; cpd out is 0 throughout) and adjIn,
adjOut. Over 400 lines today: 22 files (14 repos), 0 (cpd), 10 (adj).

|   | candidate   |     f |   cap | over |  in | out | cpdIn | adjIn | adjOut |
|:--|:------------|------:|------:|-----:|----:|----:|------:|------:|-------:|
| A | pooled med  |  35.5 | 14000 |   81 |  60 |   1 |    11 |    50 |      0 |
| B | md med      |  45.1 | 18000 |   36 |  17 |   3 |     2 |    13 |      1 |
| C | sh med      |  35.8 | 14500 |   70 |  50 |   2 |     8 |    43 |      1 |
| D | bats med    |  33.1 | 13000 |  107 |  86 |   1 |    20 |    74 |      0 |
| E | py med      |  29.3 | 11500 |  172 | 150 |   0 |    38 |   137 |      0 |
| F | pooled p75  |  42.2 | 17000 |   42 |  23 |   3 |     5 |    19 |      1 |
| G | noreg cpd   |  50.6 | 20500 |   22 |   7 |   7 |     0 |     3 |      2 |
| H | noreg 14    | 158.9 | 64000 |    2 |   0 |  20 |     0 |     0 |      9 |
| I | noreg 14-lk | 126.2 | 50500 |    4 |   1 |  19 |     0 |     0 |      8 |

A to F each fail 36 to 172 files against today's 22, and fail 2 to 38 cpd files
that comply. G fails the same count (22) but a different set: 7 in, 7 out, none
in cpd. H and I have 0 and 1 in-flips and pass 20 and 19 of today's
22. Section `sweep`, in/out over 14 repos: 14000 60/1, 16000 35/2, 18000 17/3,
20000 8/7, 22000 6/8; on adj 50/0, 31/1, 13/1, 4/2, 2/3; cpd in 11, 5, 2, 1, 0.

**Flips, 14 repos** (section `flips`): the union of each candidate's top 15 by
margin (in: nonws minus cap; out: cap minus nonws). Marks for A to I: X = in
that candidate's top 15, x = flips but ranks lower, . = does not flip.

in: compliant today, fails under the cap

| file                                 | type | lines | nonws | ABCDEFGHI |
|:-------------------------------------|:-----|------:|------:|:----------|
| handoff:uv.lock                      | lock |   363 | 63566 | XXXXXXX.X |
| handoff:docs/changelog.md            | md   |   103 | 50482 | XXXXXXX.. |
| craft:uv.lock                        | lock |   294 | 45058 | XXXXXXX.. |
| gitlore:docs/changelog.md            | md   |   353 | 25135 | XXXXXXX.. |
| gitlore:uv.lock                      | lock |   110 | 22910 | XXXXXXX.. |
| shell-gotchas:uv.lock                | lock |   110 | 22908 | XXXXXXX.. |
| ~ocs/references/index-composition.md | md   |   385 | 20669 | XXXXXXX.. |
| claude-plugin-dev:docs/design.md     | md   |   397 | 20243 | XXXXXX... |
| sandbox-lies:docs/design.md          | md   |   399 | 19881 | XXXXXX... |
| ~gin-dev:docs/references/recovery.md | md   |   385 | 19815 | XXXXXX... |
| ~ocs/references/merge-and-resolve.md | md   |   400 | 19675 | XXXXXX... |
| ~/fixtures/quiet-index-line-read.txt | txt  |    88 | 19424 | XXXXXX... |
| ~ocs/design/rejected-alternatives.md | md   |   341 | 18999 | XXXXXX... |
| ~cs/design/driving-the-transition.md | md   |   373 | 18842 | XXXXXX... |
| ~lore:docs/references/tier-stores.md | md   |   344 | 18823 | XXXXXX... |

out: fails today, passes under the cap

| file                                 | type | lines | nonws | ABCDEFGHI |
|:-------------------------------------|:-----|------:|------:|:----------|
| ~/2026-06-09-linkedin-card-walker.md | md   |   879 | 29225 | .......XX |
| ~ns/2026-06-10-plugin-claude-code.md | md   |   867 | 30855 | .......XX |
| prohibitions:docs/design.md          | md   |   815 | 38063 | .......XX |
| ~2-outillage-bootstrap-validation.md | md   |   633 | 19693 | ......XXX |
| cwd-safety:scripts/cwd-safety.py     | py   |   602 | 20756 | .......XX |
| ~2026-07-22-ghmem-dispatch-b2-fit.md | md   |   588 | 22049 | .......XX |
| cwd-safety:tests/test_cwd_safety.py  | py   |   524 | 24766 | .......XX |
| ~/2026-03-30-refonte-architecture.md | md   |   486 | 12608 | XXXX.XXXX |
| ~2026-07-21-ghmem-dispatch-triage.md | md   |   482 | 16694 | .X...XXXX |
| ~07-17-ghmem-dispatch-heat-status.md | md   |   471 | 19159 | ......XXX |
| ghmem:docs/ghmem-decisions.md        | md   |   459 | 22972 | .......XX |
| prohibitions:docs/changelog.md       | md   |   446 | 23870 | .......XX |
| ~ans/2026-07-11-ghmem-corpus-sync.md | md   |   438 | 18027 | ......XXX |
| ~eny-worktree-discarding-git-test.sh | sh   |   426 | 14457 | .XX..XXXX |
| ghmem:docs/ghmem-design.md           | md   |   401 | 18264 | ......XXX |

The in list leads with 4 lock files and 2 changelogs, then design docs near 20k.
Under A the 60 in-flips are 39 md, 11 sh, 4 lock, 3 txt, 3 bats; by repo gitlore
19, cpd 11, handoff 9, ghmem 7 (section `breakdown`).

**Flips, cpd only** (section `flips-cpd`): rows are files failing under A, B, C
or F; D and E fail more (20 and 38, see cpdIn).

| file                              | type | lines | nonws | ABCDEFGHI |
|:----------------------------------|:-----|------:|------:|:----------|
| docs/design.md                    | md   |   397 | 20243 | xxxxxx... |
| docs/references/recovery.md       | md   |   385 | 19815 | xxxxxx... |
| docs/changelog.md                 | md   |   268 | 17939 | x.xxxx... |
| CLAUDE.md                         | md   |   340 | 17222 | x.xxxx... |
| toolkit/release-tags.sh           | sh   |   365 | 17123 | x.xxxx... |
| tests/release-lost-tag-test.sh    | sh   |   367 | 14916 | x.xxx.... |
| tests/version-guard-git-test.sh   | sh   |   348 | 14695 | x.xxx.... |
| docs/references/dogfood.md        | md   |   295 | 14587 | x.xxx.... |
| tests/release-resume-hint-test.sh | sh   |   362 | 14361 | x..xx.... |
| tests/install-legacy-test.sh      | sh   |   342 | 14260 | x..xx.... |
| docs/references/release-flow.md   | md   |   300 | 14181 | x..xx.... |

**Where handoff's oversized files land** (section `handoff`; p = passes, F =
fails, marks for A to I).

| file                            | type | lines | nonws |   n/l | marks     |
|:--------------------------------|:-----|------:|------:|------:|:----------|
| CLAUDE.md                       | md   |   959 | 54804 |  57.1 | FFFFFFFpF |
| docs/changelog.md               | md   |   103 | 50482 | 490.1 | FFFFFFFpp |
| tests/test_checkpoint_legacy.py | py   |  1563 | 47997 |  30.7 | FFFFFFFpp |
| scripts/_lib_drive.sh           | sh   |   286 |  9198 |  32.2 | ppppppppp |
| scripts/_lib.sh                 | sh   |   207 |  9183 |  44.4 | ppppppppp |

`tests/hook-test.bats` is not in the survey (handoff's 21 bats files are 65 to
352 lines, 2.4k to 12.5k nonws; only E fails any, four at 11.8k to 12.5k).
`scripts/_lib.sh` and its `_lib_*.sh` siblings (109 to 286 lines) pass every
candidate. `CLAUDE.md` fails all but H; `tests/test_checkpoint_legacy.py` all
but H and I; `docs/changelog.md` (103 lines) fails A to G.

## 5. Per-type caps versus one cap

Section `pertype`. n100 = files with at least 100 lines; own = 400 x the type's
median, rounded; eqA, eqF = cap A (14000) or F (17000) divided by the type's
median n/l, the line count where a median-density file reaches it; flipA,
flipOwn = in/out over all governed files of the type.

| type  | files | n100 |  med |   own | eqA | flipA | flipOwn | eqF |
|:------|------:|-----:|-----:|------:|----:|------:|--------:|----:|
| md    |   325 |  199 | 45.1 | 18000 | 311 |  39/1 |    12/2 | 377 |
| sh    |   302 |  177 | 35.8 | 14500 | 391 |  11/0 |     9/1 | 474 |
| bats  |   204 |  171 | 33.1 | 13000 | 423 |   3/0 |     8/0 | 513 |
| py    |   134 |  103 | 29.3 | 11500 | 477 |   0/0 |     6/0 | 579 |
| just  |    16 |    6 | 35.8 | 14500 | 391 |   0/0 |     0/0 | 475 |
| js/ts |    38 |    8 | 34.7 | 14000 | 403 |   0/0 |     0/0 | 489 |

A pooled cap tightens prose and loosens code: under A a median md file reaches
the cap at 311 lines, sh at 391, bats at 423, py at 477 (under F: 377, 474, 513,
579). A fails 53 compliant md, sh and bats files (39 md) and no py file;
per-type caps fail 35 (12 md, 9 sh, 8 bats, 6 py) and pass 3 failing md or sh
files: the within-type spread, not the type mix, makes those flips.

## 6. The SKILL.md hub cap (200 lines today)

Section `hub`: `skills/*/SKILL.md`, 25 files in 7 repos (n/l p10 to p90 39.7 to
56.3). medNW, maxNW = median, max nonws. The second table is 200 x f per
candidate and the hubs over it.

| repo          |  n | medL | maxL | medNW | maxNW |  n/l | maxlen |
|:--------------|---:|-----:|-----:|------:|------:|-----:|-------:|
| candidature   |  1 |   96 |   96 |  3451 |  3451 | 35.9 |    179 |
| craft         |  5 |   88 |  171 |  3981 |  7528 | 45.8 |    551 |
| gitlore       |  6 |  104 |  257 |  4641 | 12599 | 45.4 |    642 |
| handoff       |  4 |   86 |  215 |  3628 |  8536 | 40.0 |    833 |
| plugin-craft  |  5 |  124 |  178 |  6184 |  9019 | 50.7 |    807 |
| sandbox-lies  |  1 |  200 |  200 |  9916 |  9916 | 49.6 |    738 |
| shell-gotchas |  3 |   89 |  107 |  4440 |  6218 | 58.1 |    595 |
| ALL           | 25 |  107 |  257 |  5273 | 12599 | 45.9 |    833 |

|           |    A |    B |    C |    D |    E |    F |     G |     H |     I |
|:----------|-----:|-----:|-----:|-----:|-----:|-----:|------:|------:|------:|
| 200 x f   | 7100 | 9000 | 7200 | 6600 | 5900 | 8400 | 10100 | 31800 | 25200 |
| hubs over |    7 |    3 |    6 |    7 |   10 |    4 |     1 |     0 |     0 |

200 lines at the hub median n/l is 9.2k nonws. Today 2 of 25 hubs exceed 200
lines (gitlore `memory-writing` 257, handoff 215); `sandbox-lies` sits at 200
lines and 9916 nonws. Hub n/l matches md as a whole (45.1).

## 7. Wrap-width sensitivity

Section `wrap`. cpd md is reflowed to 80 columns. >=100 = md files with at least
100 lines; medmax, p90max = median, p90 of their longest line; n/l their median;
n/B, n/w = nonws per byte, per word over all the repo's md. "With .rumdl.toml"
is cpd, craft, cwd-safety, gitlore, sandbox-lies, shell-gotchas. The second
table groups the >=100 files by their own longest line.

|                   | >=100 | medmax | p90max | B/line |  n/l |   n/B |  n/w |
|:------------------|------:|-------:|-------:|-------:|-----:|------:|-----:|
| claude-plugin-dev |    17 |     81 |    148 |     56 | 47.3 | 0.829 | 5.34 |
| candidature       |    55 |     92 |    444 |     49 | 41.1 | 0.825 | 5.85 |
| craft             |    10 |     80 |    433 |     55 | 45.0 | 0.824 | 5.05 |
| ghmem             |    23 |     80 |    192 |     48 | 40.6 | 0.829 | 5.97 |
| gitlore           |    37 |     95 |    351 |     61 | 49.6 | 0.830 | 5.40 |
| handoff           |    18 |    130 |    687 |     70 | 50.6 | 0.834 | 5.60 |
| plugin-craft      |     9 |    584 |    993 |     74 | 51.3 | 0.836 | 5.44 |
| sandbox-lies      |    12 |     84 |    541 |     58 | 50.2 | 0.834 | 5.37 |
| with .rumdl.toml  |    89 |     91 |    341 |     59 | 48.2 | 0.830 | 5.37 |
| without           |   110 |     98 |    567 |     53 | 41.6 | 0.829 | 5.77 |

| file maxlen   |   n |  n/l |  p25 |  p75 |   n/B |  n/w | L@20k |
|:--------------|----:|-----:|-----:|-----:|------:|-----:|------:|
| maxlen <= 100 | 111 | 44.2 | 39.9 | 48.8 | 0.829 | 5.47 |   452 |
| 101-200       |  46 | 45.1 | 41.9 | 50.7 | 0.831 | 5.54 |   444 |
| 201-500       |  21 | 44.0 | 37.7 | 47.5 | 0.827 | 5.83 |   454 |
| > 500         |  21 | 50.7 | 39.7 | 63.1 | 0.830 | 6.02 |   395 |

- **nonws is wrap-independent in the data.** Over all 14 repos (the table shows
  8) n/B is 0.82 to 0.84 and n/w 5.05 to 5.97, while B/line runs 44 (gitmoji) to
  74 (plugin-craft).
- **The line count is less sensitive than expected.** md n/l median is 44.2,
  45.1, 44.0 for files whose longest line is at most 100, 101 to 200, 201 to 500
  characters, and 50.7 above 500 (p25 to p75 39.7 to 63.1): at 400 lines a
  wrapped file holds about 17.7k nonws, a long-line one 20.3k, +15%. Blanks,
  headings and list items dilute the effect, and maxlen is coarse: a table or
  URL sets it in a wrapped file.
- **The rumdl grouping goes the wrong way** (48.2 with a `.rumdl.toml`, 41.6
  without), confounded by content: the rumdl repos hold the design-doc-heavy md.
  The survey cannot separate wrap from content.
- **Where a line cap is blind**: very few, very long lines.
  `plugin-craft: docs/design.md` (125 lines, 16764 nonws) holds what a cpd md
  file (47.3 n/l) holds in 354 lines; `handoff:docs/changelog.md` (103 lines,
  50482) in 1067. Section `longlines` lists six files with at least 50 lines and
  n/l over 100 (lock files excluded): two more changelogs (61 and 65 lines,
  12.2k and 9.5k nonws), gitlore's `agents/memory-merger.md` (57 lines, 7.6k)
  and a sandbox-lies fixture (88 lines, 19.4k). A line cap passes all six; A to
  G fail handoff's changelog; A, C, D, E also fail plugin-craft's `design.md`,
  which B, F, G pass.

## Observations (no recommendation)

- **Fewest flips**: G (20500), 14 flips over 14 repos (7 in, 7 out), 5 on adj, 0
  in cpd. The exact minimiser of in plus out is 13 flips at caps 20669 to 22971
  (f 51.7 to 57.4) over 14 repos, 4 flips at 20669 to 20755 on adj. Next are B
  (18000: 20 flips, 14 on adj, 2 cpd in) and F (17000: 26, 20, 5). A, C, D, E
  give 61, 52, 87, 150 flips and fail 11, 8, 20, 38 cpd files.
- A, C, D, E sit at code density (n/l 29 to 36); prose is 45 to 51 and carries
  39 of A's 60 in-flips. The cohort and the type medians agree (section 3), so
  the files that flip are the dense tail of each type.
- **Surprising**: handoff `docs/changelog.md` (103 lines) fails every candidate
  through G; no candidate under 64000 passes handoff's 363-line `uv.lock` (lock
  n/l 145 to 208), so a nonws cap needs a lock exemption or accepts them at H;
  md wrap sensitivity of n/l is small (about +15% unwrapped); the pre-split
  `hook-test.bats` and `_lib.sh` are not measured.
