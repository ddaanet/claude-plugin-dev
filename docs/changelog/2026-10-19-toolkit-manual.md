# 2026-10-19 — `toolkit/docs` becomes `toolkit/manual`

My human partner decided that user documentation and design material live apart.
`manual/` holds user documentation and ships; `docs/` holds design and never
ships; a README reaches design by at most one absolute URL, in a Development
line. The toolkit follows its own rule, in the unreleased 0.12.0.

- **The rename.** `toolkit/docs/` (`dist-branch.md`, `dogfood.md`, `gates.md`)
  moves to `toolkit/manual/`, so a consumer sees `plugin-dev/manual/`. The
  toolkit's README stubs, the root README, `CLAUDE.md`'s Layout entries, the
  `install.sh` hint, the `gates.just` comment, `TODO.md` and the tests naming
  the shipped list (`dist-tree-test.sh`, a `check-refs-shipped-test.sh` fixture)
  follow.
- **The convention reaches consumers.** The dist-branch chapter recommends
  listing `manual` and never `docs`, linking into `manual/` relatively and
  reaching design by one absolute URL. It replaces the earlier advice, written
  with `check-refs`, to list `docs` when a README links into it, which shipped
  the design along with the link. The 0.12.0 migration note gains a step for the
  rename and the recommendation, and its `check-refs` hint no longer suggests
  listing `docs`.
- **Recorded as a decision.** The hub's dist-branch conclusions and
  `references/dist-branch.md` state it in the present tense. It stays a
  recommendation: nothing refuses a plugin that lists `docs`.
- **Left as written.** Earlier changelog records and `plans/` still name
  `toolkit/docs/`, as dated records do. `migrations/v0.11.0.md` now names
  `plugin-dev/manual/`, since a consumer follows it after the pull that moved
  the files.
