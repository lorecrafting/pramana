# Pramāṇa pilot charter

**Status:** implementation-plan checkpoint; decisions and evidence still under review.
**Base:** `ac80923d4795be84b0f432031ad6e17a330f589f`
**Strategic initiative:** I-P1 leading to I-P2/I-P3 after Foundry G0.

## Product thesis

Pramāṇa should let a scholar, practitioner or ordinary curious person ask a Dharma or
Buddhist question and receive an answer whose important claims can be traced back to
inspectable textual evidence and useful supporting resources.

The experience should not stop at a matching sūtra passage. Where the corpus actually
supports the relationship, it should help the user follow an explanatory chain such as:

**sūtra / discourse → śāstra or treatise → commentary → subcommentary**

The chain exists to make difficult canonical material understandable without collapsing
the distinction between source, interpretation and generated explanation. A commentary
may explain a source; it does not become the source. Missing or uncertain links must stay
visible.

## Work in this PR

Resolve D1–D7 into one bounded pilot charter:

1. audience and recurring research job;
2. one initial canon/collection, chosen from current corpus evidence;
3. preregistered usefulness, fidelity, latency and effort thresholds;
4. human/generated rendering policy;
5. evidence-packet, privacy and retention policy;
6. exact historical replay promise;
7. one post-repair vertical slice and explicit non-goals.

This PR is product discovery and specification only. It does not admit post-repair
implementation, launch providers, change Foundry authority, or claim G0 is complete.

## Review workflow

Plan → corpus/source inspection → draft charter → self-review → corrections →
adversarial review → corrections → exact-head documentation/CI validation.
