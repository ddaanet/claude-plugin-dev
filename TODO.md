## Remaining

- Run `plans/2026-11-05-self-release-from-dev.md` steps 1-6 after the preflight change: red suite, red review by a different agent, green, docs, one commit with `/code-review medium`, then trim this list.
- Consumer flow, after the self-release slice: the same release-from-dev design in `toolkit/`, a second implementation since the two share no code. It covers `common_preflight` in `toolkit/release-preflight.sh`, its "must be on" refusal, and `push_branch` in `toolkit/release-publish.sh`. Until it lands, `ddaa:preflight` accepts dev while a consumer's recipe still refuses it.
- Same design, requirements for the consumer flow: fetch first and refuse unless `main` and `origin/main` are both ancestors of `HEAD`; allow only `main` and `dev` as the release branch, so a half-finished plan branch stays refused; `--resume` pushes the tag's commit, not `HEAD`, and its already-pushed probe compares against that, so later dev commits are not published. Existing refusal tests and `docs/references/release-flow.md` change with it.
- The `ddaa` preflight change reaches sessions only through a release of `/Users/david/code/skills`, which has not been requested: raise it once the edit lands.
- The root `README.md` list "What a consumer plugin gets" omits `just check-size`; it predates 0.15.0, so that release's preflight left it.
