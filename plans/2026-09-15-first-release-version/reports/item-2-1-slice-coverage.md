# Item 2.1 — what each slice discriminates

Extracted from the slice-1 test review and confirmed independently by the
slice-1 code review. It is its own node because it is about slices 2–6, not
about slice 1, and it is the thing to re-read before weakening or dropping any
of them.

## Method

Back up `toolkit/version-guard.sh`, write a plausible wrong implementation in
place, run `bash tests/hook-test.sh`, restore. One suite invocation per
mutation.

## Slice 1 discriminates nothing about the predicate

| Mutation | Description | Slice 1 result |
| --- | --- | --- |
| **C** (control) | Intended green: listing filtered by `git tag --list 'v*' --sort=-v:refname` piped through `^v[0-9]+\.[0-9]+\.[0-9]+$`, initial wording when empty | `all hook scenarios passed` |
| **A** | Initial-release wording emitted **unconditionally**, for every deny — no predicate at all | `all hook scenarios passed` |
| **B1** | Keyed on `git tag --list 'v*'` emptiness, **no semver filter** | `all hook scenarios passed` |
| **B2** | Keyed on **repo-ness** (`git rev-parse --git-dir` succeeding), not on tags at all | `all hook scenarios passed` |

Slice 1 establishes only that the initial-release wording
*exists and is reachable for a tagless repo*. That is structural rather than a
defect: the fixture has no tags, so every predicate a reasonable implementation
could key on agrees on it. Mutation C confirms the contract is satisfiable by
the intended implementation rather than over-specified into unbuildability.

## Which slice catches which wrong predicate

- **Mutation A** — caught by **slice 4** (the `v1.2.3` half must give
  steady-state wording; A gives initial) and independently by **slice 6** (a
  stubbed `git` exiting 127 must give steady-state; A gives initial).
- **Mutation B1** — caught by **slice 4** only, specifically its `vnext`/`v1.2`
  half, which is exactly the case the runbook names. B1 passes slices 3, 5 and
  6.
- **Mutation B2** — caught by **slice 4** only, via its `v1.2.3` half (a tagged
  repo is still a repo, so B2 answers initial). B2 passes slice 6 as well,
  because with `git` stubbed to 127 `rev-parse` also fails and B2 falls through
  to steady-state, and passes slice 5 because it never reads tags.

**Slice 4 is the only slice that catches all three wrong predicates. If slice 4
is weakened or dropped, the wording branch has no discriminating test at all.**

## The predicate as landed is the right one

Confirmed by the code review with a targeted probe rather than by reading, and
replayed unchanged after that review's fixes:

```
tags: vnext + v1.2 (non-semver)          rc=0   wording=INITIAL  stderr=[]
tags: v1.2.3                             rc=0   wording=STEADY   stderr=[]
tags: vnext + v1.2 + v0.9.0              rc=0   wording=STEADY   stderr=[]
```

Slice 4's required behaviour already holds as landed, so slice 4 will arrive
green and is a characterization guard proven by mutation rather than a red. The
code review re-ran mutations A and B1 against the committed code and reproduced
both table rows.

## Slices 5 and 6 are still genuinely red

Confirmed after the slice-1 code review's fixes:

- **Slice 5.** The tagless fixture invoked with `GIT_DIR` pointed at a `v1.2.3`
  fixture yields **STEADY** wording — the leak is not cleared.
- **Slice 6.** A `git` stubbed to 127 against the tagless fixture yields the
  **initial-release** wording, the inversion of the item's stated intent
  (`a failed listing yields the steady-state wording`).

## Slice 1 does not pre-empt the others

It asserts wording presence only, and leaves `$proposed` containment (slice 2),
`systemMessage` invariance (slice 3), the predicate (slice 4), `GIT_*` clearing
(slice 5) and the listing-failure fallback (slice 6) entirely to their own
slices. The `run_guard` env-injection mechanism it builds ahead of slice 5 is
verified working.
