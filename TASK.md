## Current task

Pre-release review of everything since the 0.13.0 release (range v0.13.0..HEAD on main): a dogfood-manual dist.include fix, a resume_preflight test, one plans/ scope rule with a shared exempt reader (toolkit/exempt-list.sh) for check-size and check-refs, check-size skipping linguist-generated files, and a doc fix naming every attribute source. Each commit already had its medium review; four low findings were declined (plans/ shipped-link check dropped, refs.exempt single trailing slash, size.exempt directory entry over generated files, a check-refs header wording).

Next: run /simplify over the range, then /code-review xhigh of v0.13.0..HEAD, which may split across several agents. Triage both, fix high and medium only, then one /code-review medium pass on the fixes, fix its findings, no further round. Then the release (just release) is my human partner's call.
