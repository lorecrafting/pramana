# FR-21 candidate v3

Date: 2026-09-13

This is the smallest correction to the independently reviewed v2 candidate. Its behavior diff
is limited to initial provenance transport handling and one executable regression.
`review-v2.md` preserves the exact review and `review-response-v2.md` records disposition.

The exact immutable candidate commit/tree and changed-path hashes are supplied with this
document after freeze; a document cannot embed the hash of the commit containing itself.
Renewed review should challenge only the v2 R1 correction and confirm that the accepted B1,
B2, B4 and B5 behavior was not weakened.

Required evidence:

- touched Elixir source formats cleanly and force-compiles with warnings as errors;
- the focused CI test file passes all 10 tests;
- a clean checkout whose output directory contains a `provenance.json/` directory exits 70,
  prints that exact destination and `:eisdir` once, creates no manifest/artifact and does not
  retry the failed write; and
- candidate source remains clean and no provider, daemon or foreign process is invoked.

The existing FR-21 limitations remain unchanged, including per-build artifact hashing rather
than a byte-reproducible escript claim and the explicit external/provider/live/activation/
integration/FR-22 exclusions.
