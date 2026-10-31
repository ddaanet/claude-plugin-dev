# check-size and check-refs: one scope rule, one exempt reader, generated files

Covers TODO items "Shared path-list parser plus one rule for `plans/`" and "Skip
generated and lock files in check-size by git attribute" (tmp/simplify-altitude.md
items 2 and 3). Contract-level: steps state what must hold, not the code.

## Decisions (settled 2026-11-01: 1b and 2 as recommended)

1. **How `plans/` becomes one rule.** Today check-refs skips it by default and a
   `refs.exempt` replaces the defaults, so a consumer can bring it back;
   check-size skips it always and refuses a `size.exempt` entry for it.
   - (a) Overridable in check-size too: needs a new `size.exempt` directive
     (syntax, refusal rules, manual section, tests). New surface.
   - (b) **Recommended.** Built in for both: check-refs skips `plans/` like
     `plugin-dev/`, and its defaults shrink to `docs/changelog`. No consumer
     loses anything: none of the 13 vendoring repos has a `refs.exempt`.
   - (c) Keep them different, and say why in both design nodes.
2. **Which repos the shared reader serves.** Recommended: `refs.exempt` and
   `size.exempt` only, both in check-size's form (CR stripped, blank lines and
   `#` lines skipped, blanks trimmed, one trailing `/` stripped, optional
   ` # reason`). `dist.sh`'s `dist.include` reader stays its own: it is a strict
   allowlist whose refusals (CRLF, edge blanks, absolute paths, `..`, globs) are
   its contract, pinned by its suites and the dist-branch manual. The finding's
   "three parsers" becomes two sharing one reader, with the third out of scope
   by design. Visible change for `refs.exempt`: blanks around a path are trimmed,
   and a ` # note` after a path becomes a comment rather than part of the path.

## A. Scope rule and shared reader (after decisions 1 and 2)

1. New `toolkit/exempt-list.sh`, sourced, not executable, like
   `check-refs-parse.sh`. It exposes a reader of path lists in the form above,
   returning path, reason and line number per entry, and the scope predicate
   (`plugin-dev/`, root `plans/` under option b) as whole leading components.
2. `check-size.sh` resolves its own directory before its `cd` to the root and
   sources the helper; `read_exempt` keeps its refusals and calls the reader.
   `check-refs.sh` replaces `load_exempt`'s loop and its `plugin-dev/*` case
   with the helper. Both scripts' behaviour stays the same except the scope
   change from decision 1 and the `refs.exempt` change noted in decision 2.
3. Bookkeeping for a shipped file: `tests/dist-tree-test.sh` list, CLAUDE.md
   Layout, `toolkit/README.md` if it names the siblings, and the justfile's
   shellcheck argv unless it is a glob.
4. Docs: check-refs and size-check sections of the manual, and
   `docs/references/check-refs.md` and `size-check.md`, for the scope rule; hub
   one-liners if they change; one dated changelog record.
5. Tests: a `refs.exempt` with a trailing ` # note` and edge blanks; `plans/`
   skipped by check-refs even when a `refs.exempt` exists (option b). Suites stay
   under 20000 bytes.

## B. Skip files marked `linguist-generated` in check-size

1. One batched `git check-attr -z --stdin linguist-generated` over the paths
   `scan_listing` already has; output is `path NUL attr NUL value NUL`. `set`
   or `true` counts as generated; `unset`, `unspecified` and `false` do not.
   Probe the value forms before relying on this list. Applied before
   `is_builtin`; the `uv.lock` and `package-lock.json` names stay as a fallback.
2. A `size.exempt` entry naming an attribute-skipped file is refused as
   "always skipped", like a built-in, not as "matches no listed file".
3. Sign-off line: the skip count `plans/plugin-dev/lockfiles` gains generated
   files. Its wording is pinned by the report suite; update both.
4. Docs: `toolkit/manual/size-check.md` "scope skips in order", the
   `docs/references/size-check.md` node, and one dated changelog record.
5. Tests, in `tests/check-size-scope-test.sh` (9632 bytes): a `.gitattributes`
   marking one over-cap file generated (skipped and counted), one with
   `-linguist-generated` (checked), and the size.exempt refusal from step 2.

Each part is one commit, gated by `just precommit` and given a medium review.
