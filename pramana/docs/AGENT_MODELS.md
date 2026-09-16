# How a model reads this corpus

**The current integration surface is MCP tools.** This design note records alternatives
and limitations, not universal claims about model capabilities. The reader can change
without changing the [source-attribution and verification constraints](INVARIANTS.md).
A decision this central should have its alternatives written down rather than assumed.

Nothing here is scheduled. `docs/PLAN.md` is what is next; this is the shape of a choice.

---

## What the current model buys

Two properties, and they are the reason it is the right default rather than merely the
first thing tried.

**The guard is deterministic and model-independent.** `Pramana.Guard` re-resolves the URN
and byte-compares the quoted span. That survives a model swap, a model regression, and a
model that is confidently wrong. Very little else in an LLM system has that property, and
it is the one this project is built around.

**The reader is swappable.** MCP means the corpus does not care which model reads it — and
`docs/COMPETITIVE.md`'s strategic read depends on that: the differentiator is the substrate,
not a particular model's behaviour over it. Any alternative that couples the corpus to one
model gives this up, and should be judged against what it buys back.

---

## Alternatives, and how they rate

### 1. Constrained decoding — make a bad citation unsayable

The guard is **post-hoc**: the model emits a citation, then it is rejected. Grammar-
constrained generation constrains the token distribution so that only a well-formed — or
only a *resolvable* — URN can be produced at all. Proven in adjacent domains: JSON-schema
constrained output, SQL generation, `outlines`, llama.cpp GBNF.

**Complementary to checking afterwards.** A grammar can enforce citation syntax;
restricting generation to validated candidates can also prevent some nonexistent IDs.
Neither proves that the quoted bytes match or that the claim follows from them.

**The limit is architectural.** It needs logit access or explicit provider support, so it
works with a self-hosted model and not through an API that exposes only tool schemas. That
makes it **complementary, not a replacement**: the guard still has to exist for every model
that cannot be constrained, and the guard is what makes the corpus model-independent.

*Verdict: worth building the day a self-hosted reader is on the table. Not before.*

### 2. Claim–evidence as the output type

Invert *generate, then guard* into *assemble, then narrate*. The model emits a structure —
`{claim, supporting_urns, contradicting_urns}` — and prose is **rendered** from it. The
argument becomes the artefact rather than a formatting convention over one.

This fits the corpus unusually well: `Compare.versions/2`, `Apparatus.at/1` and
`Commentary.glosses_on/1` already return evidence-shaped data, and the reader already renders
sections that are absent when there is nothing in them.

It also makes something checkable that currently is not — a claim with no supporting URN is
a structural error rather than a stylistic one.

*Verdict: the most promising thing here that works with any model. It is a change to the
answer format, not to the retrieval layer.*

### 3. Attributed generation with post-hoc revision

A research line — Google's **AIS** framework (*Attributable to Identified Sources*) for
measuring whether a generated sentence is actually supported by what it cites, and
**RARR**-style systems that research a draft and revise it until it is. Generate freely,
then repair against sources.

*Verdict: directionally right and worth reading properly before adopting. The specifics
here are recalled rather than checked, and should be verified against the papers before
anyone builds on this paragraph.*

---

## Rejected, with the evidence this repository already supplies

| model | why not |
|---|---|
| **Classic RAG** — stuff context, generate | Loses survey, parallels, and the model's ability to decide it needs more. It invites exactly the failure `PLAN` item D documents: five plausible near-misses, none about the question, read as an answer. `survey_corpus` exists because top-k structurally cannot answer *how often, and where*. |
| **Using model memory instead of retrieved evidence** | A memorized passage is not sufficient source evidence. Fine-tuning itself does not violate attribution if the system still retrieves and verifies citations. The recorded Tibetan embedding experiment in [PROXIES](PROXIES.md) warns against proxy-only acceptance; it does not establish that all domain fine-tuning fails. |
| **Coupling the corpus to one model** | Gives up the property that makes the guard worth having. [the shared invariants](INVARIANTS.md): *the model is not trusted to cite correctly.* A design that trusts a particular model is a design that has to be re-validated on every model change. |

---

## The gap none of them close

**The guard verifies quotes, not claims.**

A model can cite a genuine passage, quote it byte-perfectly, pass every check this system
has — and still assert something the passage does not support. Everything above addresses
*citation integrity*. None of it addresses *inferential integrity*, and that is the honest
frontier.

The project already knows prompting is not enough here. `survey_corpus` carries a note
telling models to run it before claiming anything about frequency, and [the shared invariants](INVARIANTS.md) says in
the same breath that invariants are **"enforced structurally in the tool response shape, not
by prompting"**. Those two sentences are in tension, and the tension is unresolved.

Two proposed measures could reduce this gap, without establishing complete inferential correctness:

- **A frequency claim should require a survey.** A response asserting "this appears
  throughout the Āgamas" carries a `survey_corpus` result or is refused. Enforceable in the
  response shape, which is where this project puts things it will not leave to prompting.
- **Entailment-check the claim against its cited span** — labelled probabilistic and lower
  confidence, exactly as **invariant #5** requires of anything the deterministic layer
  cannot decide.

Neither is scheduled. Both are written down so the next person does not have to rediscover
that the gap exists.

---

## What to do first, and it is none of the above

`docs/IDEAS.md` already stars it: **"show your work" mode** — every retrieval the agent ran,
replayable and inspectable. It is cheap, it needs no change to the model of interaction, and
it makes an answer **auditable** rather than merely guarded. Auditability is the same
property the corpus already has through `bake_id` and the URN, extended one layer up into
the agent.

Everything on this page is a larger bet than that, and none of it should be taken before it.
