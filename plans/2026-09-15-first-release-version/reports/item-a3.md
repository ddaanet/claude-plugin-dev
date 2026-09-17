# Item A3 — `url.<base>.pushInsteadOf` recorded as a stated bound

Addendum item, agreed 2026-09-17 alongside A1 and A2, run before Phase 4.
Documentation and one code comment. **No code change**, by decision.

## The gap

FR-6 names three push-redirect keys and `common_preflight` checks exactly those.
The prose around the check did not say "three keys"; it said "the push route",
which implied a completeness the check does not have.

## Measured, not read

Three probes, local bare repos, `git` as installed on this box:

1. **`url.<decoy>.pushInsteadOf = <origin-url>`, none of the three keys set.**
   `git push origin main` landed in the decoy; `git ls-remote origin` still read
   origin's *old* tip. Precisely the probe/publication split the check exists to
   prevent, and invisible to it — all three keys read `<unset>`.
2. **`url.<decoy>.insteadOf = <origin-url>`.** Both the push *and* `ls-remote`
   went to the decoy. Probe and publication agree, so the probe's evidence is
   about the repository the release actually publishes to. Correctly out of
   scope.
3. **`url.<decoy>.pushInsteadOf = https://example.invalid/`** — a base that does
   not prefix origin's URL. Inert: the push landed in origin, the decoy stayed
   empty.

Probe 3 is the one that decides the shape of the fix.

## Why a bound and not a check

"Refuse when it is set" is honest for the three keys because they are
repo-scoped and their presence is itself the anomaly. It does not carry over
here. The rewrite fires only when its base prefixes origin's URL (probe 3), and
a global `insteadOf`/`pushInsteadOf` rewrite is an ordinary thing for a
developer or a corporate setup to have configured. Refusing on presence would
reject healthy repositories. Deciding whether a particular base matches is the
URL-identity problem `recovery.md` already declines to solve without a network
round trip on the common path.

Recorded detail for whoever revisits this: `git config --get-regexp` reports the
key lowercased (`url.<base>.pushinsteadof`), so any future detection must match
case-insensitively on the key while the base keeps its case.

## Where it is written

- `docs/design.md` — the hub's conclusion gains a clause: a fourth route,
  deliberately not checked, a stated bound rather than an oversight. The hub was
  asserting an absolute ("a push redirected away from origin is refused") that
  is not true as stated.
- `docs/references/recovery.md` — the argument, in "The push route has to agree
  with the probe": all three measurements, why "refuse when set" does not
  generalize, and why plain `insteadOf` needs no check. The section's opening
  sentence changes from "three settings redirect a push elsewhere" to "several
  settings can redirect a push elsewhere; `common_preflight` checks three",
  which is the over-claim itself.
- `toolkit/release.sh` — the same bound in the comment beside the check, so a
  reader meets it without leaving the file. Shipped code, so it cites
  `recovery.md` (a doc consumers vendor a pointer to via `toolkit/README.md`)
  and not a `plans/` document.

## Changelog

One dated record covering the whole addendum:
`docs/changelog/2026-09-17-refusals-that-end-in-an-act.md`, indexed from
`docs/changelog.md`. A1 and A2 are in it too — they changed shipped refusal
behaviour and wording that the design nodes describe.

## Verification

No test change: no behaviour changed. `just precommit` via the pre-commit hook
covers `docs-test.sh` (the 400-line cap over `docs/` and `plans/`, plus pointer
resolution), `doc-sync-test.sh`, `shellcheck` over `release.sh`, and the full
release suite, which must stay green since only a comment moved in the script.

`docs/references/recovery.md` was at 349 lines before this and stays under the
400-line cap after it.
