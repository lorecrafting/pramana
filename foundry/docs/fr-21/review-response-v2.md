# FR-21 response to v2 independent review

Date: 2026-09-13

Reviewed candidate: `1bd381d96d6c58379d1a9586888fca56811bdc4f`

The exact independent FAIL is preserved in `review-v2.md` with SHA-256
`f9477b3497dc925eabd97a05b5af4806c523c071ef5f1f071fe10f87a124c64f`. The review accepted
the corrections for v1 blockers B1, B2, B4 and B5 and found one remaining output-transport
branch of B3.

## R1 — initial manifest destination cannot be replaced

Resolved at the bootstrap boundary. Failure of the first atomic manifest write now has a
distinct transport result. It returns infrastructure exit 70, prints the exact
`provenance.json` destination and inspected filesystem reason once, and returns immediately
without asking the ordinary failure recorder to retry the impossible write.

Ordinary attributable setup/policy failures still write their failure manifest and retain
exit 2. If the failure recorder itself discovers that its destination has become unavailable,
it now reports that transport failure with the same path-bearing exit-70 result.

An executable regression creates the output directory and a directory at its
`provenance.json` destination. This proves `mkdir_p` succeeds while atomic replacement cannot;
it asserts exit 70, the exact path, the `:eisdir` reason, one diagnostic occurrence, and the
unchanged destination directory.

The focused CI test file passes 10 tests. A separate force compile with warnings as errors and
formatting of the touched Elixir files both pass. The exact clean-candidate adversarial receipt
and candidate commit/tree/path hashes are supplied with the renewed review request.

The nonblocking stale CLI module documentation remains deferred because the shared root has
unrelated CLI changes; it is not part of this blocker correction.

No accepted v1 correction, dependency policy, toolchain policy, exclusion or authority
boundary changed. No provider, live daemon, activation, Git integration or FR-22 lifecycle
evidence is claimed.
