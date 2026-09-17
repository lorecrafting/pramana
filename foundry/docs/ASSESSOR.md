# Semantic assessor — Stage A

**Status:** model-free/fixture implementation for issue #26. This is not an enabled
production provider route and it does not close or bypass any Foundry repair ticket.

[Foundry strategy](STRATEGY.md) · [Repair plan](REPAIR-PLAN.md) ·
[Workflow contract](WORKFLOW-CONTRACT.md)

## Purpose

The assessor is a small provider-neutral advisory boundary for prioritizing optional
task context. Mandatory context is chosen outside the assessor and is never removed by
it. An enabled valid assessment may choose a bounded initial subset of optional context;
omitted optional material remains available through normal repository tools.

The first adapter models TypeSafe Jev's typed System One request/response contract.
Stage A intentionally supplies no production HTTPS transport, no ambient credential
lookup, no implicit retries, no provider fallback and no runtime wiring that can spend.

## Modes and deterministic fallback

- **off** is the default and makes zero assessor calls.
- **shadow** may compute a recommendation when explicitly authorized, but delivers the
  unchanged optional baseline.
- **enabled** is an explicit advisory test mode. A fresh valid result ranks candidates
  and the versioned selection policy supplies at most `max_initial_optional`; a valid
  explicit-none result supplies no optional initial context. Mandatory context is
  unchanged in both cases.
- Unauthorized, unavailable, malformed, stale, unsupported-version or low-confidence
  assessment paths deliver the full deterministic optional baseline.

The selection policy and Jev question set have explicit versions. Request identity binds
those versions, the confidence threshold, initial selection bound, task/objective,
candidate manifest, provider/model and resource limits. Changing those semantics changes
the request identity instead of silently reusing old evidence.

## Stage-A Jev boundary

The adapter currently pins `jev-1.13.0` and requires an explicit API key and explicit
transport supplied by its caller. The repository transport is loopback-only HTTP for
fixtures. Direct test functions can inject a transport to exercise parser/error behavior;
that is test plumbing, not a configured production route.

Candidate questions point at exact structured-state paths. Response validation requires
the exact returned model and answer IDs, the expected typed Choice/Score shapes, bounded
numeric distributions, matching score legend, nonnegative usage and strict duplicate-key
JSON handling. Floating provider values are converted to fixed-point integers before they
enter the typed result; raw response bytes are not authoritative state.

A timeout after request transmission is unavailable evidence, not permission to resend.
Stage A performs no retries. Cancellation is checked before issue and again after transport
returns; a response that arrives after cancellation is not applied. This still does not
prove remote cancellation or non-delivery. Later production integration must use Foundry's
protected claim/reservation, cancellation, receipt, replay and redaction contracts; those
are not proved by these fixtures.

Stage A identity digests use deterministic Erlang term encoding with explicit domain/version
tags. They are BEAM-internal experiment identities, not the workflow contract's protected
cross-client canonical command encoding. A production receipt integration must use the
governing canonical protocol or a separately reviewed versioned digest contract.

## Offline evaluation

`mix run bin/assessor_eval.exs -- INPUT.json` accepts an explicitly versioned, bounded
input and compares baseline and assessor candidate orderings over the same candidate set.
Each case carries a case id and candidate-manifest digest, identifies independently labelled
`relevant_ids`, and records operational measurements separately for `baseline` and
`assessor`. Unknown measurements remain explicit rather than becoming zero. The evaluator
rejects an overlarge top-k, changed candidate set, duplicate case id, excessive case/candidate
counts and ambiguous provenance.

The evaluator reports context misses at a chosen top-k, reads needed to cover all labelled
relevant material, unnecessary reads before full relevance, and known/unknown totals for
input tokens, assessor calls, latency, operator effort and rework. It makes no provider
calls and does not manufacture gold relevance labels.

A useful evaluation must keep mandatory context identical across arms, fix thresholds
before held-out evaluation, include distracting/adversarial cases, and report important
misses as well as savings. Jev or the implementing model cannot be the sole gold-label
source.

## Non-authority boundary

The assessor cannot grant spending, alter budgets/deadlines, determine Git ancestry,
validate receipts, waive checks, establish reviewer independence, accept/merge a
candidate, activate a build, or decide that an unknown effect is safe to retry.

It is also not a replacement for deterministic repository routing. Use code and policy
for facts they can answer exactly. A future diagnostic-triage consumer requires a separate
bounded design after context selection has been evaluated.

## What remains unproved

Stage A does not prove live TypeSafe account compatibility, privacy/retention suitability,
production network isolation, protected provider authorization, persistent receipt
storage, replay integration, cancellation after issued requests, spend accounting,
calibrated thresholds, or an improvement in accepted delivery.

A bounded live/shadow experiment requires explicit account/data/spending authorization
and the relevant accepted FR-owned integration interfaces. Revalidate the provider model,
API contract and terms immediately before that experiment.
