# Review of HEAD~2..HEAD (md rewrap, format-docs widening)

Level: medium. The `code-review` skill ran over the range, and the rendering and
recipe checks the brief asked for ran beside it: a CommonMark parse
(markdown-it-py) of every changed file before and after, a stub-`rumdl` run of
the recipe in a scratch repo, and a reading of the bash 3.2.57 source. Every
finding the skill raised was checked against its source before it went in here.
Line numbers are for the current tree. Neither commit has been pushed.

## Findings

### 1. High: `rewrap.md`'s "text preserved" claim is false. 34 punctuation marks were dropped

`plans/2026-11-09-md-rewrap/reports/rewrap.md:11`, and the body of the `🎨`
commit, which cites it as the verification.

When a span became a fence, any punctuation that followed its closing backtick
was dropped. Of the 103 new fences, 34 lost the mark after them, across 23
files: 24 periods, 9 commas and 1 semicolon. A fence cannot carry trailing
punctuation on its closing line, so each mark disappeared rather than moving.
The report's step 1 still says the `diff` printed nothing for every file, so the
method it describes cannot detect this loss and would pass the next rewrap too.

What a reader sees: in `item-2-1-s5-s6-green.md:11-15` the sentence "via a
hardcoded `unset …`, not `unset $(git rev-parse …)`" loses the comma that marks
the contrast. In `deliverable-review-prose.md:234` the semicolon that joined the
file list to "the Layout list names all but …" is gone. Where a period was lost,
the sentence runs straight into the block. A reviewer who takes the commit at
its word ("each file's text is unchanged") has no reason to read the 60 files,
so the loss lands unseen. The list below gives each fence's closing line and the
mark lost after it:

```text
plans/2026-09-15-first-release-version/reports/deliverable-review-prose.md:234 ;
plans/2026-09-15-first-release-version/reports/item-1-4-test-review.md:157 .
plans/2026-09-15-first-release-version/reports/item-2-1-s5-s6-green.md:14 ,
plans/2026-09-15-first-release-version/reports/item-2-1-s5-s6-green.md:23 .
plans/2026-09-15-first-release-version/reports/item-2-1-s5-s6-green.md:30 .
plans/2026-09-18-deliverable-review-fixes/reports/item-1-1-s1-test-review.md:88 .
plans/2026-09-18-deliverable-review-fixes/reports/item-3-1.md:32 .
plans/2026-09-18-deliverable-review-fixes/reports/runbook-review.md:57 .
plans/2026-09-26-dist-copy-dogfood-launcher/reports/item-1-1-s2-red.md:39 ,
plans/2026-09-26-dist-copy-dogfood-launcher/reports/item-1-1-s2-test-review.md:33 .
plans/2026-09-26-dist-copy-dogfood-launcher/reports/item-1-1-s2-test-review.md:38 .
plans/2026-09-26-dist-copy-dogfood-launcher/reports/item-1-1-s2-test-review.md:46 .
plans/2026-09-26-dist-copy-dogfood-launcher/reports/item-1-1-s2-test-review.md:77 .
plans/2026-09-26-dist-copy-dogfood-launcher/reports/item-1-1-s5-code-review.md:46 .
plans/2026-09-26-dist-copy-dogfood-launcher/reports/item-1-1-s5-green.md:7 ,
plans/2026-09-26-dist-copy-dogfood-launcher/reports/item-1-1-s6-test-review.md:30 ,
plans/2026-09-26-dist-copy-dogfood-launcher/reports/item-2-1-s3-red.md:33 .
plans/2026-09-26-dist-copy-dogfood-launcher/reports/item-2-1-s6-test-review.md:27 .
plans/2026-09-26-dist-copy-dogfood-launcher/reports/item-2-1-s6-test-review.md:31 .
plans/2026-09-26-dist-copy-dogfood-launcher/reports/item-2-2-s4-test-review.md:109 ,
plans/2026-09-26-dist-copy-dogfood-launcher/reports/research-probes.md:22 ,
plans/2026-10-03-dogfood-review-fixes/reports/item-1-1-s2-test-review.md:24 .
plans/2026-10-03-dogfood-review-fixes/reports/item-1-3.md:33 .
plans/2026-10-03-dogfood-review-fixes/reports/item-1-3.md:47 .
plans/2026-10-03-dogfood-review-fixes/reports/item-1-3.md:53 .
plans/2026-10-03-dogfood-review-fixes/reports/preflight-v0.9.0.md:38 .
plans/2026-10-05-dogfood-drop-auto-sync/reports/build-summary.md:13 ,
plans/2026-10-05-dogfood-drop-auto-sync/reports/dogfood-handoff.md:112 .
plans/2026-10-05-dogfood-drop-auto-sync/reports/dogfood-handoff.md:165 .
plans/2026-10-08-dogfood-0.9.2/reports/node-split-report.md:63 .
plans/2026-10-08-dogfood-0.9.2/reports/unprobed-items.md:42 ,
plans/2026-10-08-dogfood-0.9.2/reports/unprobed-items.md:87 ,
plans/2026-10-15-dist-branch-release/reports/slice0-red.md:61 .
plans/2026-10-15-dist-branch-release/reports/slice0-red.md:78 .
```

Also in `rewrap.md:3`: it says "Files edited: 62", but
`git diff --stat HEAD~2 HEAD~1` shows 61 files, and one of them is the report
itself, so 60 were edited. This part is low.

### 2. Medium: four fences freeze a hand wrap as a real line break

A code span renders its source newline as a space. A fence keeps the newline.
Four spans had been hand-wrapped mid-string, and each fence now shows a line
break that the quoted text does not have:

```text
plans/2026-10-03-dogfood-review-fixes/reports/item-1-1-s2-test-review.md:68     regex split at "not" / "started"
plans/2026-09-18-deliverable-review-fixes/reports/item-1-1-s1-test-review.md:96 hint split at "catch" / "up"
plans/2026-09-18-deliverable-review-fixes/reports/item-1-1-s2-test-review.md:157 REFACTOR-NEEDED line on three lines
plans/2026-10-15-dist-branch-release/reports/slice0-red.md:75                   "line 763" shown as two lines
```

Failure scenario: a reader copies `not_started_re` from line 68 and gets a
pattern with a newline between `not` and `started`. The real pattern, as
committed in `tests/` (`git log -S not_started_re`), is one line containing
`not started`, so the copy never matches the launcher's message. The
`plans/2026-10-15-dist-branch-release/reports/slice0-red.md:75` block claims to
show one source line, and the
`plans/2026-09-18-deliverable-review-fixes/reports/item-1-1-s1-test-review.md:96`
block quotes a `die` string, and the extra break misquotes both.

### 3. Low: four parentheticals are split around a fence

```text
plans/2026-09-15-first-release-version/reports/item-1-1-s3-green.md:33
plans/2026-09-15-first-release-version/reports/item-1-2-s1-test-review.md:78
plans/2026-09-18-deliverable-review-fixes/reports/item-1-1-s1-test-review.md:96
plans/2026-09-18-deliverable-review-fixes/reports/item-1-1-s1-test-review.md:102
```

Each one renders as a paragraph that ends in `(`, then the block, then a
paragraph that starts with `).`, `);` or `) —`. This is the "sentence left
broken around a block" the brief asked about. It affects rendering only, and a
reader still recovers the meaning. Under the repo's triage rule it is low, but
the fix for finding 1 will touch the same sentences.

### 4. Low, design fork: TASK.md and TODO.md now fall under the formatter

`justfile:142` (the `'*.md'` pathspec). The handoff plugin's template asks for
"one line" per Remaining item
(`/Users/david/code/handoff/skills/handoff/SKILL.md:107`). Its `todo` edit
replaces `old_string` only when that string occurs exactly once, and otherwise
exits 2 with `todo.old_string: not found`
(`/Users/david/code/handoff/scripts/_checkpoint_plan.py:33-46`). Failure
scenario: a session writes TODO.md through a checkpoint, commits (precommit
rewraps the items), and later edits an item by its one-line form. The edit is
refused, and an agent turn is spent re-reading the file. Every handoff write
also produces a rewrap diff at the next commit. The choice is between excluding
both files (a `:!TASK.md` / `:!TODO.md` exclude on the `ls-files` call) and
accepting the churn. It is a proposal, not a fix.

### 5. Low: the `🔧` commit body misdescribes its own contents

The body of commit `c11bc5e` says "the other files in this commit are that first
reflow". In fact TASK.md's task is replaced, TODO.md's first Remaining item is
removed, and the `memory` gitlink moves. Riding handoff files along is allowed,
but the sentence leads a history reader to skip those files as a mechanical
rewrap. The commit is unpushed, so the body can still be amended.

### 6. Low: no suite covers the new file selection

`justfile:148` says the `rumdl` variable is "Overridable so a test can stand in
a stub", but no file under `tests/` mentions `rumdl` or `format-docs`. A
regression in the pathspec, the skip of a deleted file, or the empty-set exit
would go uncaught. The scratch run below shows the current code is correct.

## Declined or pre-existing (from the skill's findings)

- **`format-docs` does not `git add` what it rewraps** (`justfile:146`). This
  was already true for `docs/` and `plans/`. `whitespace` stages and
  `format-docs` never has. The widening only gives it more files. Under the
  hook, the commit takes the staged text and the wrap is left as a visible
  unstaged diff. No check reads line breaks.
- **Untracked `.md` files are rewritten in place.** This follows the model
  `whitespace` already uses for every untracked file. A clash with a concurrent
  write into `inbox/` is a rare state.
- **`.MD` and `.markdown` are not matched.** No such file exists in the tree.

## Checked and clean

- **Fence indentation and list integrity** (all 60 files of the `🎨` commit).
  CommonMark list and list-item counts are equal before and after, no new
  indented code block appeared, and every new fence sits at the same list depth
  as the span it replaced. `toolkit/migrations/v0.9.1.md:15` sits correctly at
  the ordered item's 3-column content indent. Its sentence and that of
  `plans/2026-10-15-gate-sentinels/brief.md:72` read on across the block with no
  mark lost.
- **Fence opened on a list-marker line** (21 cases, for example
  `plans/2026-09-26-dist-copy-dogfood-launcher/reports/item-1-1-s5-red.md:16`).
  Each parses as a list item that holds a code block. `rewrap.md` says this form
  was chosen because rumdl re-joins an empty marker line. This is not a defect.
- **``'just release`'`` fences** (`deliverable-review-test.md:184`,
  `item-1-4-test-review.md:125`). In the old inline form a stray backtick closed
  the span early. The fence renders the needle correctly, which is an
  improvement.
- **The reflow in the `🔧` commit.** `README.md`, `tests/CLAUDE.md` and
  `inbox/README.md` change in whitespace only. `CLAUDE.md` also changes the one
  intended sentence about the scope of `format-docs`. Block structure is
  unchanged in all four files. The `@memory/ddaanet/shared-claude.md` line is
  still alone on the last line, with a blank line before it.
  `tests/doc-sync-test.sh` passes ("5 shared command blocks").
- **Idempotence.** `rumdl fmt --no-cache --diff` over the recipe's own 372-file
  set produces no diff. The 2 issues it reports are the two unbreakable emphasis
  runs that `rewrap.md` lists as left in place.
- **The recipe** (`justfile:137-146`). Under bash 5.2 with a stub `rumdl` in a
  scratch repo:
  - An empty set exits 0 and never calls rumdl.
  - `sub dir/a b.md` arrives as one argument.
  - `-dash.md` is passed after `--`.
  - A tracked file deleted from disk and listed last is skipped, with no errexit
    abort.

  The real rumdl 0.2.60 accepts `--` and a spaced path, and it applies
  `.rumdl.toml`. **Bash 3.2 was not executed.** Building 3.2.57 was refused by
  the auto-mode classifier. Instead, the 3.2.57 source was read:
  - `subst.c`, `array_length_reference` (about line 4782): the
    `unbound_vars_is_error` test at the top of the function raises an unbound
    error for `${#files[@]}` only when the variable is unset or is not an array,
    so `files=()` gives 0 under `-u`.
  - `execute_cmd.c:1587`: `&&` marks its first command `CMD_IGNORE_RETURN`.
  - `execute_cmd.c:728-735`: errexit is tested only for simple commands, so
    neither a false `[ -f ]` nor the loop's resulting status of 1 exits.

  `"${files[@]}"` is expanded only after the non-empty guard, which avoids the
  pre-4.4 empty-array unbound error. `read -d ''`, process substitution and `+=`
  all exist in 3.2.
