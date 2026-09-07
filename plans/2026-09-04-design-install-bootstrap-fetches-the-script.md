# Design: the first-install bootstrap fetches one file, at a dist tag

2026-09-04

Settles the open question the README-absorbs-update-lore brief parked: how a
first install is invoked. Option 1 of the three weighed — fetch just the script
from a pinned raw GitHub URL — is the chosen direction.

## What is wrong today

The README's first install is a three-step dance:

```sh
url=git@github.com:ddaanet/claude-plugin-dev.git
tag=$(git ls-remote --tags --refs --sort=-v:refname "$url" 'v*' \
        | head -1 | sed 's|.*/||')
git clone --depth 1 -b "$tag" "$url" /tmp/cpd
cd /path/to/your/plugin
bash /tmp/cpd/toolkit/install.sh
```

The clone exists to obtain one file. `install.sh` vendors from its own
`TOOLKIT_URL` and never reads the checkout again. Two further costs are
invisible in the block:

- It resolves the newest **source** tag, while `install.sh` then independently
  resolves the newest **dist** tag. The two lineages are cut from the same
  commit, so they normally agree — but the block is the one place a reader meets
  the source lineage, and the only thing it does with it is get a script.
- The reader is told to clone a repo whose root tree is the very thing the
  toolkit spends a design decision refusing to ship (`memory` gitlink,
  `.claude/`, `CLAUDE.md`). Harmless in `/tmp`, and still a mixed message.
- `/tmp/cpd` is a fixed, predictable path in a world-writable directory. A
  pre-planted symlink there sends the clone somewhere the planter owns, and the
  script the next line runs is then theirs to edit. That is a defect in what is
  already shipped; the block below removes the temp path entirely rather than
  hardening it.

## The decision

Resolve the newest **dist** tag, fetch that tag's root `install.sh` over HTTPS,
run it from the plugin root, and hand it the same tag:

```sh
repo=ddaanet/claude-plugin-dev
cd /path/to/your/plugin
tag=$(git ls-remote --tags --refs --sort=-v:refname \
        "https://github.com/$repo.git" 'dist-v*' | head -1 | sed 's|.*/||')
curl -fsSL "https://raw.githubusercontent.com/$repo/$tag/install.sh" | bash -s -- "$tag"
```

Five properties, each load-bearing:

1. **The raw URL is not a second distribution channel.** `dist-vX.Y.Z`'s root
   tree *is* `toolkit/`, so
   `raw.githubusercontent.com/<repo>/dist-vX.Y.Z/install.sh` serves exactly the
   file the consumer is about to vendor, at exactly the ref it vendors. Nothing
   has to be kept in step, because there is only one artifact. That was the
   stated cost of this option in the brief, and it does not apply once the URL
   names a dist tag rather than `main/toolkit/install.sh`. Verified: that URL
   returns 200 for `dist-v0.7.1`.
2. **`curl … | bash`, plainly.** The rejection recorded in
   `docs/references/distribution.md` rests on "so the script can be inspected
   before execution", and nothing inspects: every variant of this block fetches
   a remote script and immediately runs it. A download-to-file step performs the
   letter of that rule while doing the same thing in spirit, and buys a
   predictable-path problem of its own if the file is not from `mktemp`. The one
   real difference a file makes is atomicity — `bash` executes what it has read,
   so a dropped connection can run a truncated installer. That risk is already
   covered: `install.sh` is idempotent by design, so a partial run is repaired
   by running it again, which is the same remedy as for any other interrupted
   install. The rejection is therefore **overturned**, not narrowed, and the
   temp file disappears rather than being hardened.

3. **The resolved tag is passed through.** The block must resolve a tag anyway
   to build the raw URL — that is what makes it fetch the last *released*
   installer rather than whatever is on `main` — so the tag is in hand before
   `install.sh` starts. Handing it over skips the `ls-remote` `install.sh` would
   otherwise run on its no-ref path, and, more importantly, makes the fetched
   script and the vendored tree the same release by construction: the two
   resolutions are separate queries against separate URLs (HTTPS here, the SSH
   `TOOLKIT_URL` there), so a release landing between them would otherwise fetch
   one tag's installer and vendor another's tree. It also removes the source
   lineage from the block entirely: a first install now mentions `dist-` refs
   and nothing else, which is the discipline every other entry point already
   enforces. Two consequences to note in the prose around the block —
   `install.sh`'s own `resolved newest dist tag:` line only prints on the no-ref
   path, and re-running the block on an already-vendored plugin now warns
   `already vendored — ignoring ref` where it used to be a silent no-op. The
   documented re-run, `bash plugin-dev/install.sh` with no ref, is unaffected.
4. **The block still names no version, so it cannot go stale.** Resolution stays
   dynamic. Pinning an older toolkit means substituting the tag in two places —
   the URL and the argument — which the surrounding prose states.
5. **One `repo` variable on the first line.** Two hosts are unavoidable
   (`github.com` for `ls-remote`, `raw.githubusercontent.com` for the file); the
   variable keeps the block verbatim-runnable with a single substitution point.

`ls-remote` runs over HTTPS here rather than SSH, so the whole bootstrap is
anonymous up to the point `install.sh` runs `git subtree add`, which still uses
its own SSH `TOOLKIT_URL` default. `curl` becomes a first-install requirement;
none of the recipes need it.

## Rejected

- **`gh release download` / an uploaded release asset.** That is the real second
  channel — a file that exists only because someone uploaded it, out of the dist
  tree, needing its own step in `release.sh` and its own way to be wrong.
- **Fetching to a temp file and running that.** Ceremony: it satisfies the
  wording of the anti-`curl | bash` rule while doing exactly what the rule is
  about, and the only substantive thing it buys — a whole script before any of
  it runs — is already covered by `install.sh` being idempotent. With a fixed
  path it is also worse than the pipe, since the file can be swapped between the
  fetch and the run.
- **`raw.githubusercontent.com/<repo>/main/toolkit/install.sh`.** Kills the
  `ls-remote` and one substitution point, and unpins the bootstrap: `main` can
  carry a script whose wiring is mid-change and unreleased. The block's
  stability is not worth installing from an untagged ref.
- **Leaving it as-is** (option 2 in the brief). A once-per-plugin ceremony is
  cheap to leave alone, but this one is also the toolkit's only instruction that
  routes a reader through the source lineage, which every script refuses.
- **A marketplace plugin exposing `/plugin-dev:install`** (option 3). Overturns
  the standing non-goal against a `.claude-plugin/plugin.json` in this repo, for
  a step run once per plugin.

## Changes

Prose and comments only. No new functions, no changed logic path, no new branch
— `install.sh` already accepts an optional dist-tag argument and already
resolves one when given none.

1. **`README.md` §"Installing in a plugin"** — replace the block, state the
   `curl` requirement and the two-place pin.
2. **`toolkit/README.md` §"Installing in a plugin"** (~lines 55–71) — the same
   block. It ships in the dist tree, so both files carry the instructions and a
   change lands in both (CLAUDE.md's Layout rule).
3. **`toolkit/install.sh` header comment** (~lines 4–17) — the
   first-time-install example becomes the fetch form. The source-vs-dist
   paragraph below it stays: it explains the ref guard, which is unchanged.
4. **`docs/references/distribution.md` §"Single `install.sh` handles bootstrap
   and wire"** — rewrite the bootstrap paragraph in place (present tense, no
   strikethrough). It currently says `curl … | bash` is *not* the recommended
   path, on inspectability; that is now the recommended path, the inspectability
   rationale is retired as unperformed, and idempotence is what carries the
   truncation risk. Also: why not the clone, why the raw URL is not a second
   channel, why the tag is passed through.
5. **`docs/design.md`** — one conclusion line beside the existing `install.sh`
   entries: the bootstrap fetches a single file at a dist tag and is not a pipe.
6. **`docs/changelog/2026-09-04-bootstrap-fetches-the-script.md`** plus its
   pointer line in `docs/changelog.md`.

## Verification

- `just precommit` — `shellcheck`/`bash -n` (comment-only change), the
  `_import-check` stub, and `tests/docs-test.sh`'s 400-line cap and pointer
  resolution over the two docs and this plan.
- Dogfood the pipe against a scratch repo, which vendors nothing because both
  ref guards fire before the `subtree add`. Already run against `dist-v0.7.1`:
  `nope` gives "is not a dist tag", `v0.7.1` gives "is a source tag — vendor the
  dist tag instead", both exit 1. That also proves `bash -s --` delivers the
  argument and that nothing in `install.sh` competes for the piped stdin.

  ```sh
  d=$(mktemp -d); git -C "$d" init -q; mkdir -p "$d/.claude-plugin"
  echo '{"version":"0.1.0"}' > "$d/.claude-plugin/plugin.json"
  ( cd "$d" && curl -fsSL \
      "https://raw.githubusercontent.com/ddaanet/claude-plugin-dev/dist-v0.7.1/install.sh" \
      | bash -s -- nope )
  rm -rf "$d"
  ```

- Confirm the raw URL serves the file the consumer vendors, at release time:

  ```sh
  repo=ddaanet/claude-plugin-dev; tag=dist-v0.7.1
  diff <(curl -fsSL "https://raw.githubusercontent.com/$repo/$tag/install.sh") \
       <(git -C /Users/david/code/claude-plugin-dev show "$tag:install.sh") \
    && echo "fetched == vendored at $tag"
  ```

- **No automated test.** An assertion that the fetched file matches the local
  one is true only between a release and the next edit to `install.sh`, so it
  would fail on `main` for most of the toolkit's life and needs the network in a
  gate that otherwise has none. The `diff` above is the dogfood run, done once
  at release time.

## Out of scope

- The `README.md` / `toolkit/README.md` divergence check (a separate open
  decision). This change adds a fourth duplicated block, which strengthens the
  case for it; it does not settle it.
- Anything about `update.sh`. Updates run from inside a vendored tree and never
  needed a bootstrap.
