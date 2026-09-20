# FR-07 recovered candidate v6 — current-main acceptance supplement

Date: 2026-09-19

This evidence-only supplement extends `candidate-v6.md`; it does not change the FR-07
implementation. The immutable implementation and review-input revision remains
`940b8f710c661ef5f7ecd7c5c5ae9cc3fbed2ea6` (tree
`2d1632ac183c19a50d87b74ddeb7332f9b7e6f08`). The first recovery freeze is
`dc63c1c8262c71a7f5720dc49a95d9b6cdf36994` (tree
`972e758fc9076e82f35e61b4d68ecbdae68db5d2`).

## Current-main evidence

The recovered implementation was tested after transplantation onto main
`75a56c13ebafa0ab7e67f2cf12f47ad84aad2ebc`, using the repository-pinned Elixir
1.20.3 / OTP 29.0.5 toolchain and a fresh temporary root:

- `MIX_ENV=test mix compile --force --warnings-as-errors`: exit 0; 90 project files
  compiled.
- `mix test test/pramana_foundry/durable_store --seed 9044`: exit 0; 68 tests, no
  failures.
- `mix test --seed 9045`: exit 2; 501 tests, one failure.
- Isolated reproduction,
  `mix test test/pramana_foundry/projections/benchmark_test.exs`: exit 2; two tests,
  one failure.

The sole full-suite failure is
`test/pramana_foundry/projections/benchmark_test.exs:16`. Its process output reports
that Python cannot import `tiktoken`; the benchmark consequently uses fallback token
counts that do not match the committed expected benchmark. The isolated benchmark run
reproduces the same mismatch. This is recorded as an unavailable non-FR-07 dependency
and exclusion, not as a passing full suite and not as an FR-07 implementation failure.
No benchmark source or expected value was changed by this ticket.

The warnings-as-errors build and the complete 68-test durable-store acceptance suite
remain passing. No live daemon, provider, credential, deployment, or activation state
was touched.

## Restored historical input

`foundry/docs/fr-07/diagnosis-v3.md` was recovered byte-for-byte from the preserved
2026-09-13 agent journal and now hashes to
`5f1d7d7113a47e5db07219d933b7f60c491ef130e29054b5b36dc040e591c6f7`, matching the
historical candidate-v5 manifest. It is provenance only and does not modify candidate
behavior.

An independent reviewer must review the exact evidence revision containing this
supplement. This implementation-owner record makes no review or acceptance verdict.
