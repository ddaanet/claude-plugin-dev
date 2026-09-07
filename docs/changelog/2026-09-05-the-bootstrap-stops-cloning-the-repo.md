# 2026-09-05 — The bootstrap stops cloning the repo to get one file

A first install used to resolve the newest *source* tag, `git clone --depth 1`
it into `/tmp/cpd`, and run `bash /tmp/cpd/toolkit/install.sh`. The clone
existed to obtain a single file: `install.sh` vendors from its own `TOOLKIT_URL`
and never reads the checkout again. It now fetches that one file instead, from
the dist tag it is about to vendor, and pipes it to bash.

The fetch is not a new distribution channel, which was the objection that kept
this option unpicked. `dist-vX.Y.Z` is a `git subtree split --prefix=toolkit`,
so its root tree *is* `toolkit/` and `install.sh` sits at the root of it — the
raw URL for that tag serves precisely the file the plugin is about to vendor, at
precisely the ref it vendors. There is nothing to keep in step, no asset to
upload, and no way for the installer and the content to be different releases.
The old block also had two lineages in play at once: it pinned a source tag to
get the script while `install.sh` separately resolved the newest dist tag. The
block now names `dist-` refs only, and hands the resolved tag to the script,
which both closes that gap and saves a second `ls-remote`.

## Why the anti-`curl | bash` rule did not survive contact

The design said outright that `curl … | bash` was *not* the recommended
bootstrap path, and gave a reason: a cloned script can be inspected before it
executes. Nothing inspected it. The block cloned and immediately ran, exactly as
a pipe does, so the rule was buying its own wording and not the property the
wording names.

The first replacement attempt kept the letter of it — fetch to a file, then run
the file — and was worse. At the fixed `/tmp` path the README already used, the
file is pre-plantable and swappable between the fetch and the run, which is a
real defect the clone form shares (a symlink at `/tmp/cpd` redirects the clone
somewhere its planter owns). Hardening that with `mktemp` produced a five-line
ceremony whose only substantive gain over the pipe is atomicity: bash executes
what it has read, so a connection dropped mid-transfer can run a truncated
installer. That gain was already spent. `install.sh` is idempotent by design, so
a partial run is repaired by running it again — the same remedy any interrupted
install has.

So the rule is gone rather than narrowed, and the temp file disappeared rather
than being hardened. What replaces the inspectability argument is the dist-tag
pin: the thing being executed is a released, tagged artifact, identical to the
one that lands in `plugin-dev/` a second later.

## Where it landed

The block appears in `README.md` and `toolkit/README.md` — both, because only
one of them ships — and in `install.sh`'s own header comment. The reasoning is
in `docs/references/distribution.md` under a section of its own, with the
temp-file and release-asset forms recorded as rejected; the hub carries the
one-line conclusion.

Verified against `dist-v0.7.1` before the change was written: the raw URL
returns the byte-identical file to `git show dist-v0.7.1:install.sh`; a
nonexistent tag 404s under `curl -f`; and piped into `bash -s -- <ref>` the
script receives its argument and both ref guards still fire — `nope` is refused
as not a dist tag, `v0.7.1` as a source tag naming `dist-v0.7.1` instead — with
nothing vendored in either case.
