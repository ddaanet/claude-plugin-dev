# 2026-09-17 — The self-release gets the recovery it had been shipping to consumers

`toolkit/release.sh` has given every consumer an idempotent tail and
`just resume-release` since 2026-07-29. This repo's own release had neither. It
was four unguarded lines at the bottom of a `justfile` recipe — `git push`,
`git push origin` the two tags, `gh release create` — and cutting 0.8.0 is where
that bill came due: the commit and both tags landed locally, the push was
refused, and finishing the release meant running the recipe's last three lines
by hand.

Running them by hand was the smaller problem. The larger one is what a re-run
would have done instead. After the local half of the release lands,
`toolkit/VERSION` holds the new version and the newest tag names it, so the
drift guard — VERSION must equal the latest tag — *passes*, because the drift it
was built to catch is a hand-written bump, not a failed push. The tag-collision
guard passes too: it asks whether the *next* version's tags exist, and they do
not. So `just release minor` would have bumped again, published the version
after the one that failed, and left the failed one tagged in two places with no
GitHub release and nothing anywhere refusing it. The guard set was complete
against every state except the one the flow actually produces when it breaks.

So the recipe body moved to `scripts/self-release.sh` and grew the consumer
shape: a tail that probes origin before each step and reports what was already
done, reached by `just release <bump>` and by `just resume-release`, the latter
depending on no gate for the reason `release.just` already gives consumers — a
prerelease that passed must not have to run again to finish the release it
gated.

One guard has no consumer counterpart. `release` now refuses to bump while the
version currently in `toolkit/VERSION` is tagged locally but missing either tag
on origin or its GitHub release, and names what is missing. `release.sh` needs
nothing like it because a consumer's half-landed release shows up as
`plugin.json` disagreeing with its marketplace entry, which `check-version.sh`
reads as the release's pre-flight. The toolkit publishes no marketplace entry.
`toolkit/VERSION` is its only witness, and a failed push leaves that witness
looking correct — so the check has to be against origin and GitHub directly.

The split tag needed its own thought. `resume-release` re-cuts `dist-vX.Y.Z`
from the `vX.Y.Z` tag rather than from `HEAD`, because by the time a resume runs
`HEAD` has usually moved past the release commit and the dist ref must carry the
tagged `toolkit/` tree. And when origin already holds the dist tag while this
clone does not, it is left alone rather than re-split: the split is
deterministic in practice, but "in practice" is not a basis for pushing a
recomputed ref over a published one, and `push_tag`'s mismatch refusal is the
only thing standing between a differing split and a moved tag.

Extracting to a script rather than growing the recipe was the other call. The
recipe body was 56 lines of bash that `shellcheck` never saw, in a file no test
drove — a combination that is only tolerable while the code is trivial, and this
code had just stopped being trivial. `tests/self-release-test.sh` now drives it
end to end against real repos with local bare origins and a `gh` stub, the same
fixture shape `tests/release-test.sh` uses for the consumer flow. Deleting the
new guard's one call site fails seventeen of its checks.

The `ls-remote` reads are written as a captured assignment trimmed with
`${line%%$'\t'*}` rather than a pipe into `cut`, so a failed probe cannot be
read as "the ref is not on origin" — the direction in which every caller takes
it as licence to act. The pre-existing `ls-remote | cut` captures in
`release.sh`, which fail closed only by way of `set -o pipefail`, are still
open.
