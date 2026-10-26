## Remaining

- release-marketplace.sh rewrites marketplace.json whole in jq's 2-space style on every real bump; edit the version in place instead.
- scripts/self-release.sh common_preflight refuses a dirty tree with a bare "uncommitted changes" naming no path, while toolkit/release-preflight.sh report_dirty names them; make the self-release name the offending paths.
- tests/docs-test.sh resolves docs/ and plans/ pointers with its own grep, which reads links inside inline code spans; check-refs.sh now covers the same ground over every Markdown file, so drop that half of docs-test or point it at check-refs.
