# Chinese pilot scope materialization

**Status:** materializer contract implemented; live scope not yet accepted.
**Pilot:** chinese-commentary-v1

[Pilot charter](PILOT_CHARTER.md) · [preflight](PILOT_PREFLIGHT.md) ·
[acceptance contract](PILOT_ACCEPTANCE.md) · [rights boundary](CHINESE_PILOT_RIGHTS.md)

This document owns the procedure for turning one explicitly selected current corpus release
into the exact Chinese pilot scope. It deliberately does **not** contain a historical or
fixture-derived list of the ten demand-ranked works.

The pilot_scope gate remains blocked until this procedure is run against the accepted live
release and the resulting artifact is reviewed.

## Frozen v1 selection

The materializer uses:

- **10 demand-ranked seed families**, recomputed from the live CBETA Taishō quotation graph;
- the four named Āgamas: T0001, T0026, T0099, T0125, verified against live
  title/division/role metadata rather than silently assumed present;
- only comments_on and subcommentary_of expansion edges;
- at most **2 relation hops**, matching the frozen acceptance ceiling;
- only non-model assertion methods: catalogue, manifest, title_match, lemma_match,
  shared_text;
- only CBETA / Taishō (cbeta.T) works in the first pilot scope.

An llm work-relation assertion cannot put a work into pilot scope. A typed relation whose
source role is not allowed by Pramana.Relations.may_explain/1 to explain the target role is
also excluded and counted.

This is intentionally stricter than "a row exists."

## Demand ranking: codify the proxy honestly

The old 14-work tranche was selected from a one-off "directed citation weight" analysis.
The repository preserved what was learned about that proxy, but not a reusable production
query that can be replayed verbatim. The new materializer therefore codifies the retained
rules rather than pretending hidden historical SQL is an immutable specification.

For every current-bake CBETA Taishō quotation pair:

1. exclude reuse inside the same letter-stripped work family;
2. collapse repeated rows to distinct text_sha256 evidence;
3. if exactly one work's text_role may explain the other's role, direct from explanatory
   work to explained work;
4. otherwise, when both date_start values are known and differ, direct later → earlier;
5. if role and date both resolve but disagree, mark the pair **conflicting** and give it no
   demand weight;
6. if neither resolves, mark it **unresolved** and give it no demand weight;
7. score a target family by distinct {citer_family, passage_hash} evidence;
8. pick the best-attested member of a winning family, breaking exact ties by work ID.

The artifact reports the full direction denominator:
directed_pairs + unresolved_pairs + conflicting_pairs = cross_family_pairs.

That makes the proxy inspectable. It does not turn shared text into a scholarly citation
graph.

## Release and mutable-graph identity

Generation requires an explicit expected release ID:

    cd pramana
    mix pramana.pilot.scope \
      --release-id <exact-selected-release-id> \
      --out /tmp/pramana-pilot-scope.json

The task refuses when:

- no release is selected;
- the selected release ID differs from the requested ID;
- the release uses legacy/coarse rather than v2 translation/vector content identity; or
- Pramana.Release.drift/0 is not :current.

The release identifies the source/retrieval state, but current work relations and
commentary alignments are mutable tables outside release_id. The artifact therefore
records separate SHA-256 digests for:

- work metadata;
- the classified quotation-ranking input;
- work-relation assertions; and
- current-bake commentary alignments.

Do not claim release_id alone freezes those graphs.

## Relation traversal

Relations point **explanatory work → explained work**. Scope expansion therefore walks the
reverse lookup from a seed/parent to works that point at it.

For every admitted edge the artifact retains:

- source and target work IDs;
- relation type;
- hop at which the edge was encountered;
- seed ancestry;
- every admitted corroborating assertion;
- assertion method/confidence/scope/target URN; and
- a digest of the assertion evidence.

Several assertion methods for one relation are corroboration, not duplicate edges.

Works outside CBETA/Taishō, model-only relation assertions, and role-incoherent relation
rows are excluded and counted rather than silently disappearing.

## Passage-alignment census

For each admitted relation pair, the artifact records:

- total current-bake commentary_alignments rows;
- distinct root URNs;
- distinct commentary URNs; and
- whether any passage-level alignment exists.

A zero means "the accepted work relation has no current-bake passage alignment," not
"there is no commentary."

## Deterministic artifact

The saved schema is pramana-pilot-scope/v1.

It contains:

- exact release components;
- frozen selection parameters;
- ranking denominator and top-ten evidence;
- combined seed list;
- every expanded work with role/source/hop;
- admitted relation edges/assertions;
- per-edge alignment coverage;
- evaluation denominators;
- input graph digests; and
- scope_content_sha256 over canonical sorted-key JSON.

There is no wall-clock generation timestamp in the semantic payload. Identical inputs must
produce byte-identical output.

Validate any saved artifact without a live database:

    elixir bin/check_pilot_scope.exs --validate /tmp/pramana-pilot-scope.json

or from the umbrella:

    cd pramana
    mix pramana.pilot.scope --validate /tmp/pramana-pilot-scope.json

Structural validation proves only the file's internal contract. It does not prove that the
file still matches today's database.

## What closes the preflight gate

A later review may change pilot_scope to ready only when it has:

1. the exact accepted release ID;
2. a live materializer output generated against that release with no drift;
3. reviewed top-ten demand rows and ranking denominators;
4. all four verified Āgamas;
5. complete expanded-work and relation lists;
6. passage-alignment coverage;
7. source/rights review covering **every expanded work**, not only the seeds;
8. recorded scope and input hashes; and
9. evidence that the reviewed artifact is the one participant/rehearsal execution will use.

A test fixture, historical 14-work list, successful command exit, or structurally valid
JSON is not enough.

## Current preflight state

**Blocked.** This PR builds the measuring instrument. It does not have a reviewed accepted
live-corpus artifact merely because the source code can query one.
