# Size-cap gate: the mechanics of a shipped check

Design report, 2026-10-31, on mechanics only. The unit U and the threshold C are
settled separately, so they stay symbols here. The marker `Unit-dependent:`
(grep for it) opens the sentence at each place where U or C changes the answer.
"The illustration" sets C = 14000 non-whitespace characters: 400 lines at the
median of 35 characters per line, over the 295 surveyed files of 200–400 lines.
It shows which classes of file move. It is not a proposal for C.

## 1. Consumer survey

The survey was read-only, using `survey/measure.sh`, `git ls-files` and plain
reads. All 13 consumers are on 0.12.0, mount a `memory` gitlink, ignore `dist/`
and wire `precommit: check-refs`. None has a `refs.exempt` or a
`.gitattributes`. Seven import `gates.just` (craft, cwd-safety, ghmem, gitlore,
handoff, prohibitions, sandbox-lies), and every one of those cached gates names
a subset of the tree. Seven have no size gate: candidature, gitmoji, handoff,
onekeys, plugin-craft, prohibitions and prompt-fzf. The other six:

| repo          | own size gate                  | lists by | caps    | rumdl  |
| ------------- | ------------------------------ | -------- | ------- | ------ |
| craft         | `check-skills.py`, bundled     | globs    | 200/400 | normal |
| cwd-safety    | `check-docs` recipe, bundled   | globs    | 400     | wrap   |
| ghmem         | `check_line_limits.sh`         | `find`   | 400     | no     |
| gitlore       | `check-docs-links.py`, bundled | os.walk  | 400     | normal |
| sandbox-lies  | `check-line-limits.sh`         | index    | 200/400 | check  |
| shell-gotchas | `scripts/check-size.sh`        | disk     | 200/400 | check  |

"Bundled" means the size check shares a script with link, orphan or citation
checks. In the rumdl column, `normal` is a reflow with `normalize` ahead of the
count, `wrap` a reflow without it, and `check` is `rumdl fmt --check` inside the
gate.

No two of the six share a scope rule, and none has an exemption file. Four cap
chosen directories by suffix. sandbox-lies also caps config files, except under
`tests/fixtures/`, skips `plans/` and `plugin-dev/`, and reads the index,
against the disk rule. Only shell-gotchas excludes more paths: `plugin-dev`,
`memory`, `plans`, `inbox`, `.claude`, `docs/changelog*`, `TODO.md` and
`TASK.md`.

Ten consumers import the shared tier, which states 400 and ~200. Five of them
also state the cap in their own `CLAUDE.md`: craft, cwd-safety, ghmem,
sandbox-lies and shell-gotchas. Five design docs repeat it, among them craft's
FR-5, ghmem's NFR9 and gitlore's D55.

**What a shipped scan meets:** frozen plans under `docs/superpowers/`
(candidature, ghmem); generated tracked files, namely candidature's build copy
of `src/` (every overage would report twice), ghmem's `requirements.txt`, seven
`uv.lock` and one `package-lock.json`; a sandbox-lies fixture of 19424
non-whitespace characters in 88 lines; untracked, unignored root scratch
(cwd-safety, gitmoji); binaries; unwrapped prose, such as handoff's changelog
index at 50482 characters in 103 lines; and a `docs/changelog.md` index in ten
repos, growing a bullet per change.

**Over 400 lines today**, counting `line-cap-test.sh`'s scope plus `docs/*.md`:

| repo         | files over the cap                                           |
| ------------ | ------------------------------------------------------------ |
| candidature  | `DESIGN.md` (1678); six `docs/superpowers` plans             |
| cwd-safety   | `scripts/cwd-safety.py` (602); its test (524)                |
| ghmem        | `uv.lock` (655); two `docs/` files; five plans               |
| handoff      | `tests/test_checkpoint_legacy.py` (1563); `CLAUDE.md` (959)  |
| handoff      | `docs/changelog/2026-05-19-…` record (480); hub (215)        |
| gitlore      | hub `skills/memory-writing/SKILL.md` (257)                   |
| prohibitions | `docs/design.md` (815); `docs/changelog.md` (446); one test  |

The other seven pass. The brief predates handoff's split: its 3985-line bats
file is gone, and `scripts/_lib.sh` is under the cap. Unit-dependent: at the
illustration, ten consumers fail instead of six, joined by five `uv.lock` files,
the fixtures, unwrapped prose, four changelog indexes and seven hubs.

## 2. Propagation list (named, not edited)

**claude-plugin-dev:** `CLAUDE.md` 104, 189–193, 209–211 and 319–326; `justfile`
21, 32, 68, 159 and 163–164; the `.rumdl.toml` header; `tests/line-cap-test.sh`;
`tests/docs-test.sh`; `docs/references/gates.md:108`. In the shared tier:
`memory/ddaanet/shared-claude.md` 336–348, `markdown-reflow-gate.md` with its
index line, and `split-commit-alone.md` 3 and 11. Dated changelog records are
not revised.

**craft** (read-only): `skills/plan-contracts/SKILL.md` (the `description`, 32,
43–44), `references/contracts-and-size.md` (5–16, 37–62, 77, 106–118, 127) and
`references/code-in-a-plan.md:53`; also `splitting-an-oversized-doc.md:128`,
`CLAUDE.md` 6–7, `README.md` 71–73, `docs/design.md` 3, 45 and 144, and
`scripts/check-skills.py`.

## 3. Q1 — Artifact and name

**Recommendation:** an executable `toolkit/check-size.sh`, wrapped by a one-line
`release.just` recipe that nothing depends on:
`check-size: bash "{{toolkit_prefix}}/check-size.sh"`. The consumer wires it in
as `precommit: check-refs check-size`, uncached, the same shape as `check-refs`.

It is not a `gates.just` recipe. Six consumers do not import that file, which
defines one name by design. Bash inside a justfile string also needs a special
test before `shellcheck` can reach it.

**Why uncached.** The check reads every file git does not ignore. No consumer
hashes that set, because the manual says to name paths. A whole-tree sentinel
would break on every edit. Inside a narrower cached body, the check would read
outside the hash, and a cached pass would commit an unchecked file. So it runs
ahead of every guard, on every call.

**That forces a single pass.** On gitlore's 581 regular files, one `awk` over
the list took 0.23 s; a `tr | wc` per file took 9.2 s. The load-bearing contract
is one listing and one counting process. Counts are aligned to the NUL-delimited
list rather than keyed by name, so a newline in a path cannot forge a line.
Empty files are filtered out first, since awk sees no record in them.

`git ls-files -z --eol -co --exclude-standard` marks a binary on disk `w/-text`,
untracked files included (probed with git 2.47), so the same listing finds
binaries. It also flags lone-CR files. `grep -I` under `LC_ALL=C` is the
alternative, and a fixture pins whichever is chosen. In this repo, the call sits
inside the cached body, beside `check-refs.sh --shipped toolkit`, because this
repo's sentinel hashes `:/` minus `memory`.

**Name.** `check-size` names the property, not the unit, and `oversized-file:`
is already unit-neutral. The recipe name is a compatibility surface: a recipe
defined both in an import and in the importing justfile refuses the whole
justfile (probed with just 1.46). No consumer has a `check-size` recipe today,
and the migration note names it. The executable bit is pinned in
`dist-tree-test.sh`, as for `check-refs.sh`. There are no arguments; the root
comes from `git rev-parse --show-toplevel`. There is no `--tree` mode either,
since the dist tree is a subset of the source.

## 4. Q2 — Scope

**Recommendation:** every file git does not ignore, tracked or not, read from
disk. Skip, in order:

1. symlinks;
2. anything that is not a regular file: a gitlink, a nested repo, a deleted
   tracked file, a sandbox char-device mask;
3. unreadable files, each with a stderr notice and a count in the sign-off;
4. binaries;
5. the built-ins: `plugin-dev/`, root `plans/`, and `uv.lock` and
   `package-lock.json` at any depth;
6. `size.exempt` entries.

Everything else counts, `docs/*.md` and untracked drafts included.

Unreadable files are skipped rather than failed because the known producer is
the sandbox; shell-gotchas excludes `.claude/` for the same reason. A gate red
under the Bash tool and green in the hook is worse than a hole that names
itself. Lockfiles are built in because a tool owns them, nobody reads one at one
go, and nobody can split one. Unit-dependent: in lines only ghmem's `uv.lock`
(655) needs the rule. In characters, five do: ghmem's at 90900, handoff's at
63566, craft's at 45058, and gitlore's and shell-gotchas's at about 22910 each.

**`docs/changelog/` is for my human partner to call.** The brief, the task,
`line-cap-test.sh` and shell-gotchas exclude it. `docs-test.sh` and gitlore
count it, and `CLAUDE.md` argues that the wrap keeps the cap measurable there. I
recommend counting it. A record is checked by the commit that writes it, while
its author can still split it, and it never changes afterwards. So the cap fires
once, at the right moment, and the repeating warning that took `plans/` out
never arises. The cost is one `size.exempt` line for each record that predates
adoption or a metric change; handoff has one today. Excluding the directory
would shrink this repo's own coverage.

**The index `docs/changelog.md` counts either way.** It only grows, and the fix
is a split by period. It fails in prohibitions today. Unit-dependent: at the
illustration, it also fails in craft, gitlore, handoff and this repo (17939).

Not made defaults, for want of a need: `inbox/` (a brief lands there untracked,
so one over C would fail a commit nobody here wrote, but the largest is 70
lines), `TODO.md` and `TASK.md` (98 lines at most), and fixtures and build
copies, which take a consumer directory entry. The check relies on `dist/`
staying ignored, which the dogfood sync enforces. Root scratch is scanned, as
`git add -A` would stage it and `check-refs` reads it.

## 5. Q3 — Exemptions

**Recommendation:** a root `size.exempt` in `refs.exempt`'s grammar, plus a
mandatory reason on the same line:

```text
# Files over the size cap on purpose, and trees it does not govern.
tests/test_checkpoint_legacy.py  # deleted by the legacy pass, TODO.md
CLAUDE.md  # split pending, TODO.md
docs/superpowers  # frozen superpowers plans and specs
```

**The path** runs to the first ` #`, with trailing blanks trimmed. The reason
after it must not be empty. Comment lines, blank lines and `\r` are skipped. A
path matches itself and every whole component below it, as in `dist.include`.
There are no globs, since a glob silently covers files written later.

**There are two kinds of entry.** A file entry ratchets: it must name a listed
file that is over its cap. A directory entry declares scope: it must hold a
listed file, but none of those files has to be over. Entries add to the
built-ins and never replace them.

**Refusals.** An entry with no reason, one matching no listed file, a file entry
within its cap, and a repeat of a built-in or of another entry are each refused
with one line, `size.exempt:<n>: <path> — <why>`, and the run fails.

**Why refuse stale entries.** handoff's two entries each name an end: a deletion
and a split. Refusing a missing path makes the deletion commit drop its line.
Refusing a file back under C makes the split commit drop its line, and catches a
later regrowth. A warning would repeat until someone ignored it.
`check-sentinel` and `dist.include` already refuse paths that match nothing. As
residuals, a generated file held by a file entry would flip as it hovers near C.
That is why lockfiles are built in, and why other generated files take a
directory entry. A path that contains ` #`, ends in a blank or starts with `#`
cannot be named.

**Alternatives weighed.** A reason on a comment line above the path: deleting
the entry orphans it, and a shared comment is ambiguous. `path|reason`: `|` is
legal in a path. Replace semantics, as `refs.exempt` has: one entry would put
every plan back under the cap; additive costs a difference between the two
`.exempt` files, which the manual states once. One config shared with
`check-refs`: that list holds frozen history and this one overages with an end,
only this one ratchets, and sharing needs a section parser and a migration.
`.gitattributes`: a second channel with no reason and no ratchet. An inline
marker like gitlore's `<!-- hygiene-ok -->`: it needs a comment syntax and hides
the decision in the file.

Unit-dependent: the ratchet compares against C. A metric change therefore turns
some entries stale and makes others necessary, so the release that makes it
needs a migration note.

## 6. Q4 — Per-path thresholds

**Recommendation:** two constants in the script, neither settable by a consumer.
C applies to every file. `C_hub`, about C/2, applies to any file named
`SKILL.md` at any depth, which also covers candidature's hub source at
`src/SKILL.md`. `C_hub` is a constant of its own, so a hub density measured
separately can set it.

**The gate makes "~200" exact.** handoff's hub is 215 lines and gitlore's 257,
and both fail on adoption. Unit-dependent: at the illustration, a `C_hub` of
7000 fails seven hubs in five repos.

**No configurability.** A need would be a reader measured to differ, such as
session-injected content that wants a tighter cap. A file that outgrew C is not
one: gitlore's `artifact-size.md` rejects "a cap set by whatever grew last".
Should a need appear, it becomes a per-path cap in `size.exempt`, where review
sees it, and never an environment variable.

## 7. Q5 — Report and sign-off

Failures go to stderr, one line each, in `LC_ALL=C` path order:

```text
oversized-file: <path>: <n> <U> > <C>
oversized-file: <path>: <n> <U> > <C_hub> (SKILL.md hub)
```

The token comes first. Five checkers and the shared rule use `oversized-file:`,
in three positions between them, and the shipped form settles which. U is the
metric's noun, and `<n>` is exact.

One hint line follows: split along a seam, and do not shave prose or docstrings
to fit. It does not name `size.exempt`, because an agent reads an advertised
exemption as its next step. Unit-dependent: in lines, the hint adds "not by
cramming lines".

An exemption error is `size.exempt:<n>: <path> — <why>`. A failed run prints
`check-size: <reason>` and exits 1. An empty listing is a failure, never a pass.
The sign-off is one stdout line naming every check with its count:

```text
check-size: cap <C> <U>: <n> files; hub cap <C_hub> <U>: <h> SKILL.md;
size.exempt: <e> entries, each with a reason and still needed; skipped:
<p> plans/plugin-dev/lockfiles, <b> binary, <l> symlinks, <r> unreadable
```

## 8. Q6 — Formatter dependency

**Under lines, the dependency is real.** A line count is honest only after a
normalizing hard wrap. Eight consumers run no Markdown formatter: candidature,
ghmem, gitmoji, handoff, onekeys, plugin-craft, prohibitions and prompt-fzf.
cwd-safety's rumdl lacks `normalize`. A line gate must therefore bring a pinned,
normalizing rumdl, run ahead of the check, into eight repos, or it can be gamed:
handoff's 50482-character index counts as 103 lines.

**Under non-whitespace characters, it goes.** A wrap moves only whitespace,
except where it adds characters per new line: `>` on wrapped blockquote
continuations, which rumdl adds (+1); comment leaders (`#` and ` * ` +1, `//`
+2); `\` continuations in shell and justfiles (+1); Python strings split by
implicit concatenation (+2); realigned table delimiter dashes; and Markdown
backslash hard breaks (+1). List markers do not repeat, and indentation is
whitespace.

The bound is 1–2 characters per line. At 35 per line, wholly quoted or commented
prose moves 3–6% between an 80-column wrap and none. A script with a third of
its lines commented moves about 1%. Cramming gains no more than that. The
formatter stays for readability, but its place ahead of the check stops being
load-bearing.

**Unit sub-choice, for the metric agents.** Non-whitespace bytes and codepoints
differ by 0.4–0.5% on handoff's `CLAUDE.md` and `release-tags.sh`, 0.9% on this
repo's `design.md`, and 2.5–2.8% on candidature's French prose. Both count in
one portable awk pass under `LC_ALL=C`. Bytes are `length` after deleting
`[ \t\r\f\v]`. Codepoints also delete the UTF-8 continuation bytes
`[\200-\277]`. That matched `wc -m` (78253) under mawk; BSD awk is unverified.
Neither needs a UTF-8 locale, and NBSP still counts.

## 9. Q7 — This repo's own suites

`tests/line-cap-test.sh` retires. Its fixtures move to new suites, and its
self-scan becomes the precommit call. `tests/docs-test.sh` retires too: it
asserts nothing once the script counts `docs/*.md`.

Three fixture suites replace them, each with one script under test, its own
harness and under 400 lines: `check-size-scope-test.sh` (Q2's skips, and paths
holding a space or a newline), `check-size-exempt-test.sh` (Q3's refusals and a
directory entry) and `check-size-report-test.sh` (format, hub cap, order,
counts, exit codes, empty listing). Each fixture is over C exactly where only
its own exclusion keeps it out, so every exclusion has a red. The report suite
pins C as a literal; the other two read C from the script.

The `justfile` adds the script to `shellcheck`, runs
`bash toolkit/check-size.sh` after `check-refs`, and updates the suite lists;
`_import-check` asserts that `just --dry-run check-size` prints exactly
`bash "plugin-dev/check-size.sh"`; the `format-docs` comments are rewritten
(Unit-dependent). `dist-tree-test.sh` adds `check-size.sh` and
`manual/size-check.md` and an executable-bit block. `doc-sync-test.sh` fails
until `CLAUDE.md` has a Layout bullet for each new path. `CLAUDE.md` updates its
suite list and restates "No suite file passes 400 lines" in U. This repo keeps
no `size.exempt`: its suites are never exempted.

`docs/design.md` is at 397 lines, so it needs a seam, cut in a commit of its
own, before it can take a new section. A new node,
`docs/references/size-check.md`, carries the Q1–Q6 arguments, and a changelog
record goes with it. The toolkit must pass its own check before it ships.
Unit-dependent: at the illustration, eleven files here need splitting first,
among them `docs/design.md` (20243), `CLAUDE.md` and four suites.

## 10. Q8 — Consumer rollout

**Adoption blocks nothing by itself.** `update.sh` edits nothing outside
`plugin-dev/`, and nothing in `release.just` depends on `check-size`. After
`just update-plugin-dev` and `just --list`, a consumer:

1. runs `just check-size` once, unwired, and reads the list;
2. splits each listed file, or exempts it with a reason, using a directory entry
   for a frozen or generated tree;
3. adds `check-size` to `precommit`'s dependencies;
4. commits apart from the subtree merge, with precommit green.

The only red is step 1's output. There is no seeding flag, because a reason
cannot be generated, and a placeholder defeats the rule. In lines, the longest
list is candidature's: 7 entries, or 2 with a `docs/superpowers` entry.
Unit-dependent: at the illustration, gitlore needs 20. That says the answer is
splitting, or revisiting C.

handoff, in lines, exempts the two files its `TODO.md` names. One is
`tests/test_checkpoint_legacy.py`, which the legacy pass deletes no earlier than
2026-11-16. The other is `CLAUDE.md`, whose split is pending. Its TODO does not
foresee the 215-line hub, nor the 480-line record if records count.

Retiring consumers' own checkers is optional. ghmem's, sandbox-lies's and
shell-gotchas's are standalone and retire whole; sandbox-lies's fixtures
exception becomes a directory entry. craft's `check-skills.py`, gitlore's
`check-docs-links.py` and cwd-safety's `check-docs` lose only their size half.

The migration note, `toolkit/migrations/vX.Y.Z.md`, carries the four steps, the
recipe name (so a clashing consumer recipe is renamed first), the retirement
list, and the proof that it worked: `just check-size` prints the sign-off, and
`just precommit` passes.

The manual gains a chapter, `toolkit/manual/size-check.md`. `toolkit/README.md`
(309 lines) gains a stub section and a Contents bullet, and the `release.just`
header names the recipe.

Unit-dependent: under a line metric, the note must also install a pinned,
normalizing rumdl, run ahead of the check, in eight consumers.

## 11. Q9 — Cross-repo consequences

These are proposals only, for a character metric. The places to change are
listed in §2.

**The shared bullet.** "400 lines caps" becomes "C U (about 400 wrapped lines)
caps". "~200 a `SKILL.md` hub" becomes "`C_hub` U", without the tilde, since the
gate enforces the number. The "never satisfy it quietly" sentence keeps the ban
on shaving and turns the one on cramming into a reading rule. "A count is only
honest once a hard-wrapping formatter has run …" stops being a counting
precondition. "`oversized-file: <n> lines > <cap>`" becomes "the toolkit's
`check-size`, reporting `oversized-file: <path>: <n> <U> > <cap>`"; today's
literal omits the path whatever the metric. `markdown-reflow-gate.md` drops its
"honest only against `normalize`" paragraph.

**craft plan-contracts.** The `description` and `SKILL.md:32` change "line cap"
to "size cap". `contracts-and-size.md` 5–16 is restated in U; its 3.5× ratio of
contract to code was measured in lines, so it stays a line figure or is measured
again. "Measure the cap honestly" (37–62) drops wrapping first as a counting
step, and `check-size` replaces `wc -l`. In "The three forms of cramming", long
lines stop gaming the count, while run-on paragraphs and shaving still do.

Also revisit craft's `check-skills.py` and its FR-5, and gitlore's D55. D55
rejects tokens because "lines are exact, free and reproducible", which holds
equally for characters.

Unit-dependent: all of this section. Under a line metric, only the report
literal and the tilde change.
