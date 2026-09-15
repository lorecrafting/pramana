# FR-21 candidate v2

Date: 2026-09-13

This candidate is the bounded correction to the independently reviewed v1 failure. It retains
the v1 dependency/executable retirement, workflow, isolation and formatting-debt policy and
adds only the behavior described in `review-response.md`.

The corrected implementation is commit
`4e4acf784742381127bfd54fef49faf957d1c256`, tree
`4e95b891f23d8822122acb3d919605b793c64491`. The final review candidate is that
implementation plus this evidence-only document update; its exact revision is supplied with
the independent review request because a Git document cannot contain the hash of the commit
that contains itself. Each v2
`provenance.json` binds the exact revision/tree, runner/workflow hashes, clean pre/post source,
exact Elixir/OTP/ERTS policy and actual values, complete lock/resolved dependency inventory,
exclusion match counts, stage/command receipts and generated escript. Changed candidate paths
and their SHA-256 values are supplied to the reviewer after the candidate is frozen. The
executed acceptance record is `acceptance-v2.md`.

Evidence required and obtained before renewed review:

- focused v2 tests with optional tiktoken recomputation excluded;
- dirty tracked and untracked source failures before commands;
- missing project, wrong exact toolchain, prohibited dependency and missing executable probes
  with attributable nonzero manifests;
- two full CI passes from clean detached checkouts with independent run roots and a Python
  environment where `tiktoken` is unavailable; and
- clean source status both before and after each successful run.

No `mix.exs`, `mix.lock`, Coordinator, CLI, startup, durable store or live-state file is in the
v2 correction scope. No provider, live daemon, deployment or activation is exercised.
