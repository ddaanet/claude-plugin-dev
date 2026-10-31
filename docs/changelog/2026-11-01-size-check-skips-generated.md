# The size check skips files marked linguist-generated

A generated file has no author to split it, and a lock file is only the
commonest one. `check-size` now asks git, in one batched
`git check-attr -z --stdin linguist-generated` over the paths that reach the
count, and skips each file whose value is `set` or `true`. Probed on git 2.47:
`x` prints `set`, `-x` prints `unset`, `x=true` prints `true`, `x=false` prints
`false`, no attribute prints `unspecified`, and `x=yes` prints `yes`, which is
not counted. The `uv.lock` and `package-lock.json` names stay as a fallback for
a repo with no attribute.

A `size.exempt` entry naming such a file is refused as "a generated file is
always skipped", as a built-in is, rather than as "matches no listed file". The
sign-off count reads `plans/plugin-dev/lockfiles/generated`, and a generated
file is counted once, whether or not a built-in would also take it.
