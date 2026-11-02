# Test suites

The suites `just precommit` runs under `tests/` (every `*-test.sh`, by glob;
this file only describes them), and what each covers.

`version-guard-{decision,wording,git}-test.sh`, `check-version-test.sh`, the
eleven `release-*-test.sh` suites that split `release.sh`'s consumer flow by
scenario group (`release-core`, `-resume-push`, `-resume-hint`, `-tree`,
`-first`, `-lost-tag`, `-push-route`, `-tags`, `-rollback`, `-pipefail`,
`-hint-size`), `release-core-root-skip-test.sh` (which runs the `release-core`
suite under a stub `id` printing 0, to pin its root guard),
`release-dist-{publish,resume,refusal,optin}-test.sh` (`release.sh` publishing
the `dist` branch), `self-release-{publish,refusal}-test.sh`,
`update-plugin-dev-test.sh`, `run-bats-test.sh` (the quiet runner, against a
stub `bats`), `gates-{sentinel,guards,inputs,hash}-test.sh` (`gates.just`'s
cache, its guards, the files it hashes and the re-hash after a formatter, driven
through real `just` recipes in a fixture consumer),
`install-{vendor,settings,legacy}-test.sh` (`install.sh`'s vendoring, settings
wiring and legacy-entry migration), `dist-tree-test.sh` (the shipped-file list),
`dist-{build,refusal,warning,subcommands}-test.sh` (`dist.sh`'s allowlist, tree
build, refusals, warnings and other subcommands),
`check-refs-{syntax,scan,shipped}-test.sh` (`check-refs.sh`: what a reference
is, which files are read and exempt, `plans/` always skipped, and the shipped
check), `check-size-{scope,exempt,report}-test.sh` (`check-size.sh`: which files
are counted (including `linguist-generated` files), the `size.exempt` refusals,
and the report, caps and counts),
`check-frontmatter-{block,fields,scope,interpreter}-test.sh`
(`check-frontmatter.sh`, against fixture plugin repos and the venv's real
PyYAML: the block refusals, the `description` and `name` refusals (a skill's
`name` is its directory's, an agent's is required and need not match its file, a
command's optional), which files are read and the sign-off counts, and the
missing or PyYAML-less interpreter), `doc-sync-test.sh` (the install/update
command blocks shared by the two READMEs, and
[docs/toolkit-layout.md](../docs/toolkit-layout.md) against `toolkit/`'s actual
contents, and the `toolkit/` paths the root [CLAUDE.md](../CLAUDE.md) names),
`citation-test.sh` (refuses a `<script>.sh:<line>` citation into a file outside
`plans/`), `mktemp-template-test.sh` (refuses a `mktemp` call with no template
in `*.sh`, `*.just` and justfiles), `whitespace-test.sh` (the `whitespace`
recipe, against a fixture repo), the `dogfood.sh` suites
(`dogfood-sync-{copy,nested,allowlist,refusal}-test.sh`,
`dogfood-pre-tool-{paths,jq}-test.sh` and
`dogfood-session-{start,warn}-test.sh`) and
`dogfood-launcher-{exec,path,bin}-test.sh` (the `bin/claude` shim).
