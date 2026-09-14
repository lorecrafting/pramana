# Product Strategy, Market Fit, and UI/UX Blueprint

*Document status: Live design specification for multi-model critique and iterative discussion.*

---

## 1. Executive Summary & The Core Thesis

Pramāṇa (प्रमाण) exists to establish **epistemic warrant** for a claim about a text, not merely
to retrieve plausible passages or generate ungrounded answers.

When users search for Buddhist philosophy or practice online today, they face an epistemic crisis:
- **Pop-Buddhism & SEO blogs (Medium, Reddit, Lion's Roar):** Fluent interpretations with almost
  zero verifiable citations, frequently attributing modern western self-help quotes to the historical Buddha.
- **Fragmented scholarly archives (CBETA, SuttaCentral, 84000, SAT):** Siloed by language and tradition.
  CBETA is Traditional Chinese only; SAT is archaic; 84000 is exclusively Tibetan; SuttaCentral is primarily Pāli.
  No tool allows an English-speaking reader to ask one question and inspect the Pāli, Chinese, and Tibetan evidence together.
- **Generic frontier LLMs (ChatGPT, Claude, Perplexity):** High verbal fluency, low epistemic warrant. They blend
  Theravāda, Mahāyāna, and Vajrayāna doctrines without distinction, hallucinate sūtra references, and quote out of context.

**The Product Opportunity:** A unified, English-first product harness that delivers an authoritative
answer grounded in immutable, byte-verifiable canonical anchors across all three major Buddhist canons.

---

## 2. Target User Personas & Jobs-to-be-Done (JTBD)

### Persona 1: The Practitioner & Serious Inquirer
- **Profile:** Meditator, reader, podcast listener. Speaks English; reads neither Classical Chinese nor Tibetan.
- **Immediate Need:** Conceptual and practical clarity on Buddhist doctrine (e.g., *"What does Buddhism actually teach about grief?"*, *"What is the difference between citta, mano, and viññāṇa?"*).
- **Current Friction:** Searching Google yields superficial listicles. Asking ChatGPT produces plausible-sounding prose that cannot be verified.
- **JTBD:** *"Give me a clear, synthesised English explanation, but give me the exact source passages so I know this is authentic Dhamma and not modern internet folklore."*

### Persona 2: The Dharma Teacher & Writer
- **Profile:** Monastic, study group leader, retreat teacher, or book author.
- **Immediate Need:** Preparing a talk, workshop, or article with authentic textual backing.
- **Current Friction:** Remembering a simile (e.g., *"the simile of the lute and tuning the strings"*) but spending 45 minutes digging through fragmented websites to locate the authentic sūtra, translator, and context.
- **JTBD:** *"Help me find the canonical passage across traditions, understand how early commentators interpreted it, and let me copy an authoritative excerpt with proper citations for my handout or slides."*

### Persona 3: The Scholar, Translator, & Graduate Student
- **Profile:** Academic in Asian Studies, Buddhist Studies, or comparative philosophy.
- **Immediate Need:** Philological precision and apparatus integrity.
- **Current Friction:** Must cross-reference physical printed volumes (Taishō Tripiṭaka, Derge Kangyur/Tengyur) against digital databases with inconsistent segmentation and missing variant readings.
- **JTBD:** *"Give me the exact physical edition coordinates (Taishō volume/page/register/line, Derge folio), the Song/Yuan/Ming textual variants, parallel Chinese/Tibetan witnesses, and a 1-click BibTeX export."*

---

## 3. The Progressive Disclosure UX Model

A world-class product harness must avoid two failure modes: dumping raw ancient text on casual seekers,
and dumbing down technical data for scholars. The solution is **progressive disclosure**:

```
┌────────────────────────────────────────────────────────────────────────┐
│ Level 1: Grounded Answer Synthesis                                    │
│ Plain-English conceptual synthesis with clickable warrant badges       │
├────────────────────────────────────────────────────────────────────────┤
│ Level 2: Lineage & Tradition Perspectives                              │
│ Clustered by tradition: Early Pāli / Indo-Tibetan / East Asian         │
├────────────────────────────────────────────────────────────────────────┤
│ Level 3: Dual-Pane Source Inspector (Side-by-Side)                     │
│ Canonical text in physical layout alongside verified English rendering│
├────────────────────────────────────────────────────────────────────────┤
│ Level 4: The Philological Deep Dive                                    │
│ Word-level etymology, variant apparatus, and commentary trees          │
├────────────────────────────────────────────────────────────────────────┤
│ Level 5: Cryptographic Export & Citations                              │
│ 1-click BibTeX, print coordinates, and shareable verified replay links │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 4. Key Feature Specifications

### Feature 1: The "Claim & Warrant" Answer Canvas
- **Natural Language Inquiry:** User enters queries in English (e.g., *"How is the concept of non-self (anattā/anātman) defended against eternalism?"*).
- **Grounded Answer Section:** An LLM synthesises an answer in clear English.
- **Structural Invariant:** **No sentence may make a doctrinal assertion without an anchored citation badge** (e.g., `[SN 22.59 §2]`, `[T0262 @ p0001c19]`).
- **Interactive Trigger:** Clicking any claim badge or hovering over any asserted sentence highlights the exact supporting source span and slides out the Source Inspector.

### Feature 2: Slide-Out Dual-Pane Source Inspector
- Slides in from the right edge without navigating away from the answer.
- **Left Column (Canonical Source):**
  - Displays original Pāli, Classical Chinese, or Tibetan text.
  - Formatted according to native edition conventions (Taishō column registers, Derge folios).
  - Highlights the exact cited byte range.
  - Displays provenance pill: `Indian Root Text · 姚秦 鳩摩羅什譯 (c. 406 CE) · Certain`.
- **Right Column (Translation & Layers):**
  - Displays peer-reviewed human translation (`tier: t0`, e.g., Patton, Sujato, 84000).
  - If only machine translation exists, displays `tier: t1 — Machine Draft (Unreviewed)` with transparent model identifier (`model:mitra`).
- **Context Slider:** Allows expanding context from ±1 line to full discourse/sūtra section.

### Feature 3: The Rosetta Stone Etymological Popover
- Clicking or hovering over technical terms in any passage reader view (`/passage` or inspector) opens an interactive card powered by Pramāṇa's 89,649 glossary entries:
  - **Sanskrit:** *Śūnyatā* (शून्यता)
  - **Chinese:** 空 (kōng) — with translator divergence (e.g., Kumārajīva: 空 vs. Xuanzang: 性空)
  - **Tibetan:** སྟོང་པ་ཉིད (stong pa nyid)
  - **Canonical Definitions:** Synopses from *Mahāvyutpatti*, Soothill-Hodous, and DILA lexicons.

### Feature 4: The Dharma Fact-Checker (`/check`)
- **Use Case:** "Check this Dharma claim" (a viral acquisition and research tool).
- **Interface:** A clean text box where users can paste an article, lecture transcript, book snippet, or social media post.
- **Verification Engine:** Pramāṇa evaluates every clause against the canon using `Pramana.Guard`:
  - 🟢 **Canonical (Verified):** Direct match in root sūtras/suttas with clickable receipts.
  - 🟡 **Commentarial / Late Tradition:** Attested in Kamakura Japan, Song China, or later Tibetan scholasticism, but absent from Early Buddhist texts.
  - 🔴 **Unattested / Spurious:** No canonical warrant found in any of the three major canons.
- **Exportable Verification Report:** Users can share a cryptographic verification card: *"Pramāṇa Audit: 85% Canonical, 15% Late Commentary."*

### Feature 5: The Scholar's Export Toolkit
- **One-Click Citations:**
  - Standard formats: Chicago 17th, APA 7th, MLA 9th.
  - Academic print edition formats: e.g., `Taishō Shinshū Daizōkyō, Vol. 9, No. 262, p. 1c19-25`.
  - LaTeX / BibTeX export block.
- **Citable Snippet Card:** Formatted Markdown card containing:
  - English rendering,
  - Source text in original script,
  - Immutable URN link with SHA-256 integrity hash.
- **Immutable Replay URL:** Anyone with the link can re-verify the citation against the recorded bake state.

---

## 5. Architectural Alignment with Pramāṇa Umbrella

| Product Feature | Backing Domain Engine | Surface Implementation |
|---|---|---|
| Natural Language Synthesis | `Pramana.Retrieval.Hybrid` | `PramanaWeb.SearchLive` (`/`) |
| Warrant Badges & Receipts | `Pramana.URN`, `Pramana.Guard` | `PramanaWeb.ReaderComponents` |
| Multi-Tradition Bucketing | `Pramana.Provenance.group/1` | `PramanaWeb.PassageLive` (`/passage`) |
| Rosetta Stone Popovers | `Pramana.Glossary`, `Pramana.Translators` | `PramanaWeb.ReaderComponents` |
| Textual Variant Inspector | `Pramana.Apparatus` (`compare_witnesses`) | `PramanaWeb.WorkLive` (`/works/:id`) |
| Dharma Claim Checker | `Pramana.Guard.diagnose/1`, `Pramana.Report` | `PramanaWeb.CheckLive` (`/check`) |

---

## 6. Systems Architecture: Harness, Graph, and Loop Engineering

*(Source reference: Industry architectural dispatch on agent reliability by ~marfin, referencing production patterns for autonomous systems, Claude Code harnesses, and failure diagnosis; Telegram archive: `https://t.me/+-e0O9zoaMvQ1NjAy`).*

### The Core Thesis: Three Non-Competing Production Layers

A common industry failure mode is treating **Harness Engineering**, **Graph Engineering**, and **Loop Engineering** as competing paradigms. In an authoritative epistemic system like Pramāṇa, they form three nested, interdependent layers surrounding the model:

```
┌────────────────────────────────────────────────────────────────────────┐
│                          HARNESS LAYER                                 │
│  (Environment, Sandboxes, State Persistence, Tool Caching)             │
│                                                                        │
│   ┌────────────────────────────────────────────────────────────────┐   │
│   │                         GRAPH LAYER                            │   │
│   │   (Topology, Parallel Fan-Out, Routing, Sync Joins)            │   │
│   │                                                                │   │
│   │   ┌────────────────────────────────────────────────────────┐   │   │
│   │   │                      LOOP LAYER                        │   │   │
│   │   │  (Evidence Checks, Deterministic Guards, Retry Rules)  │   │   │
│   │   │                                                        │   │   │
│   │   │   ┌────────────────────────────────────────────────┐   │   │   │
│   │   │   │                    MODEL                       │   │   │   │
│   │   │   │  (Swappable Reasoning & Synthesis Engine)       │   │   │   │
│   │   │   └────────────────────────────────────────────────┘   │   │   │
│   │   └────────────────────────────────────────────────────────┘   │   │
│   └────────────────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────────────┘
```

### The Four Anti-Patterns Addressed

| Anti-Pattern | Description | How Pramāṇa / Foundry Prevents It |
|---|---|---|
| **1. Looping on Confidence** | Relying on model text assertions ("I verified this") rather than deterministic signals. | **Invariant #1 & #8:** Model is never trusted to self-certify. Post-generation `Pramana.Guard` independently resolves URNs and byte-verifies spans against the immutable bake. |
| **2. Noisy Harness Context** | Dumping raw repositories or massive outputs into prompt context, burning tokens and inducing hallucinations. | Targeted read tools, physical pagination (Taishō line/register, Derge folio), and **Diagnostic Compacting** for test/compiler feedback. |
| **3. Unconstrained Graph Cycles** | Retry loops without hard attempt limits or escalation policies. | Hard iteration ceilings, circuit breakers, and bounded token budgets across all agent loops. |
| **4. Forcing Deterministic Work into Models** | Burning LLM tokens on string parsing, deduplication, or alignment. | **Invariant #5:** "Deterministic before probabilistic." Native Rustler NIF (`jieba-rs`) for CJK tokenization, suffix-arrays for text reuse, exact rolling windows for root-commentary alignments. |

---

### Mapping to Pramāṇa's Dual-Harness Architecture

Pramāṇa operates two distinct, specialized harnesses that both implement this 3-layer architecture:

#### A. The Product Harness (Canonical Philological Reader)
1. **Harness Layer**:
   - **Content-Addressed Bake:** Corpus immutable artifact (`sources.lock.json`, SHA-256 byte addressing).
   - **Postgres + pgvector:** Native physical edition coordinate mapping (Taishō/Derge/SC).
   - **Read-Only MCP Surface:** Read-only retrieval endpoints; models are strictly prohibited from mutating corpus state.
2. **Graph Layer (Multi-Canon Concurrency)**:
   - **Scoper Node:** Analyzes English user queries and extracts doctrinal entities.
   - **Parallel Fan-Out:** Concurrently queries 3 dedicated canonical sub-retrievers:
     - `Sub-Retriever A`: Early Pāli Canon (SuttaCentral)
     - `Sub-Retriever B`: East Asian Mahāyāna Canon (CBETA / Taishō)
     - `Sub-Retriever C`: Indo-Tibetan Vajrayāna Canon (84000 / Degé Kangyur & Tengyur)
   - **Sync Join Gate:** Aggregates multi-tradition evidence, reconciles parallels, and constructs the unified passage graph.
3. **Loop Layer**:
   - Post-synthesis citation verification via `Pramana.Guard`. If a cited span fails byte-level verification, the claim is rejected or re-routed before rendering to the user.

#### B. The Builder Harness (Foundry Agent Automation)
1. **Harness Layer**:
   - **State Persistence:** SQLite WAL with sync-fault fixtures and durable execution fences (FR-06/FR-07).
   - **Tool Read State Hashing:** SHA-256 content hashing on file reads. If a file has not changed since an agent last inspected it, returns a compact cache receipt rather than consuming context window tokens.
   - **Isolated Workspaces:** Ephemeral git worktrees per agent task to eliminate cross-agent workspace collisions.
2. **Graph Layer**:
   - OTP `DynamicSupervisor` managing agent trees, ticket dependency DAGs, and reviewer handoffs.
3. **Loop Layer**:
   - **Diagnostic Compactor:** Deterministic parser that condenses raw ExUnit/compiler failure outputs into structured, minimal diffs (failing file:line, expected vs. actual, top 5 stack frames).
   - **Adversarial Red-Team Verifier (Stage 5):** Before merging a candidate ticket or PR, an adversarial subagent actively synthesizes edge-case breaking tests (e.g., `nil` inputs, malformed URNs, empty collections) to verify the patch under attack.

---

## 7. Implementation Mechanism: The Composable Agent Middleware Pipeline ("Plug for Agents")

*(Source reference: Sydney Runkle, "How to Build a Custom Agent Harness", LangChain Blog, June 3, 2026; `https://www.langchain.com/blog/how-to-build-a-custom-agent-harness`).*

### From Theory to Mechanism: `Agent = Model + Harness`

While the tripartite taxonomy (Harness ⊃ Graph ⊃ Loop ⊃ Model) establishes the macro-architecture, the **Composable Agent Middleware Pipeline** provides the concrete software engineering pattern to implement it cleanly without turning agent runners into monolithic God objects.

The core design principle: **The base agent runner is intentionally minimal. All domain policies, guardrails, state caching, and diagnostics are injected via composable middleware modules** that intercept execution at four deterministic lifecycle hooks:

```
┌────────────────────────────────────────────────────────────────────────┐
│                        AGENT EXECUTION LIFECYCLE                       │
│                                                                        │
│   [Input Request]                                                      │
│          │                                                             │
│          ▼                                                             │
│   ┌──────────────┐   → Context Compaction, Dynamic Prompt Shaping,     │
│   │ before_model │     History Pruning                                 │
│   └──────┬───────┘                                                     │
│          ▼                                                             │
│   ┌──────────────┐                                                     │
│   │  MODEL CALL  │   → Swappable LLM Inference                         │
│   └──────┬───────┘                                                     │
│          ▼                                                             │
│   ┌──────────────┐   → Citation Extraction, Schema Guardrails,         │
│   │ after_model  │     Format Verification                             │
│   └──────┬───────┘                                                     │
│          ▼                                                             │
│   ┌──────────────┐   → Tool Call Limits, Permission Checks,            │
│   │ before_tool  │     SHA-256 State-Hash Tool Caching                 │
│   └──────┬───────┘                                                     │
│          ▼                                                             │
│   ┌──────────────┐                                                     │
│   │  TOOL EXEC   │   → Bash Command, Database Query, MCP Tool Call     │
│   └──────┬───────┘                                                     │
│          ▼                                                             │
│   ┌──────────────┐   → Diagnostic Compacting (ExUnit/Compiler Diffs),  │
│   │  after_tool  │     Error Sanitization, Cache Store                 │
│   └──────┬───────┘                                                     │
│          │                                                             │
│          ▼                                                             │
│   [Result / Loop Feedback]                                             │
└────────────────────────────────────────────────────────────────────────┘
```

### The Elixir/OTP Advantage: The "Plug" Pattern for Agents

In Python frameworks like LangChain, middleware is implemented via async callbacks or class inheritance. In the Elixir/BEAM ecosystem, this maps directly to the idiomatic **`Plug`** architecture:

```elixir
# Conceptual Foundry Agent Pipeline
defmodule PramanaFoundry.AgentPipeline do
  def run(execution_state) do
    execution_state
    |> Middleware.StateHash.call()
    |> Middleware.BudgetCap.call()
    |> Middleware.DynamicContext.call()
    |> AgentRunner.invoke_model()
    |> Middleware.DiagnosticCompactor.call()
    |> Middleware.Guardrails.call()
  end
end
```

The BEAM provides distinct production advantages over Python event loops:
1. **Fault Isolation:** If a middleware check crashes or times out, it crashes an isolated process supervised by `DynamicSupervisor`; other concurrent subagents continue unaffected.
2. **True Preemptive Concurrency:** Thousands of subagents run in parallel without the GIL or async/await blocking.
3. **Immutability:** Agent state transitions are pure data structures, ensuring replayability and audit trail integrity.

---

### Key Capabilities Enabled by Middleware in Pramāṇa

#### 1. Speculative Stream Interception in LiveView (Product Harness)
In `PramanaWeb.SearchLive`, the LLM streams English synthesis tokens directly to the user's browser.
- **The Stream Middleware:** An asynchronous stream transformer intercepts citation URNs (e.g., `[T0262 @ p0001c19]`) in flight.
- **Speculative Verification:** The moment a URN pattern is recognized in the token stream, the middleware asynchronously fires `Pramana.Guard` to byte-verify the referenced span against Postgres *while the model is still typing the rest of the sentence*.
- By the time the user finishes reading the sentence, the citation badge already displays its verified green receipt.

#### 2. Diagnostic Compacting in Developer Loops (Builder Harness)
When autonomous subagents execute tests or builds in Foundry:
- **Raw Tool Output:** `mix test` or `mix dialyzer` failures can generate 2,000+ lines of stack traces and stdout, instantly exhausting token budgets and polluting prompt context (Anti-Pattern #2).
- **The Compactor Middleware:** Intercepts non-zero shell exit codes and deterministically extracts:
  - Exact failing file and line number (`apps/pramana/lib/...:42`).
  - Expected vs. actual assertion diff.
  - Top 5 stack frames, stripping all framework noise.
  - Injects a compact, high-density 15-line diagnostic back into the model loop.

#### 3. Context Compaction & Editing Middleware (Multi-Turn Research)
- In multi-turn retrieval or code investigation, once a subagent accomplishes an intermediate milestone, the middleware compacts previous raw tool outputs into structured summary records (`"Inspected T0262; confirmed chapter 2 locator at p0005b12"`), discarding the thousands of intermediate raw JSON bytes.

#### 4. Task-Harness Fit: Pramāṇa's Epistemic Moat
As noted by Runkle, **Task-Harness Fit** is how tightly the harness matches the specific demands, failure modes, and invariants of the domain:
- Generic harnesses have zero task-harness fit for Buddhist philosophy: they do not understand Taishō line/register coordinates, Derge folios, Sanskrit diacritics, or Pāli-Chinese parallel alignments.
- Pramāṇa delivers **100% Task-Harness Fit**: the harness deterministically resolves physical coordinates, aligns cross-lingual parallels, and byte-verifies claims, relieving the model of all philological bookkeeping.

---

## 8. The 4-Layer Compounding System: Self-Improving Agent Roadmap

*(Source reference: Industry technical dispatch on autonomous agent systems, Anthropic Fable 5 launch documentation, Parameter Golf, and Continual Learning Bench 1.0 experiments; Substack: `movez.substack.com`).*

### The Core Thesis: Self-Improvement is a System Property, Not Weight Learning

True production self-improvement does not mean recursive model weight retraining (RSI). Instead: **the model remains frozen and stateless, while the environment, memory, rules, and verifiers around it compound run-over-run.** Every session writes verified facts into state, sharpens procedural skills with observed failure modes, and distills post-mortems into deterministic rules.

```
┌────────────────────────────────────────────────────────────────────────┐
│                   LAYER 4 · SELF-IMPROVEMENT LAYER                     │
│  Independent Verifier Sub-Agents, Vision UI Checks, Rule Distillation  │
│                                  │                                     │
│                                  ▼ (writes lessons back)               │
│   ┌────────────────────────────────────────────────────────────────┐   │
│   │                     LAYER 3 · MEMORY LAYER                     │   │
│   │   State Files (STATUS.md), Rules (RULES.md), Skills, Lockfiles │   │
│   │                              │                                 │   │
│   │                              ▼ (informs next session)          │   │
│   │   ┌────────────────────────────────────────────────────────┐   │   │
│   │   │               LAYER 2 · ORCHESTRATION LAYER            │   │   │
│   │   │  Goal Loops, Dynamic Workflows, Routines, Supervisors  │   │   │
│   │   │                          │                             │   │   │
│   │   │                          ▼ (dispatches)                │   │   │
│   │   │   ┌────────────────────────────────────────────────┐   │   │   │
│   │   │   │              LAYER 1 · PRIMITIVES              │   │   │   │
│   │   │   │  Models (Pro/Flash/Haiku), Worktrees, Tools    │   │   │   │
│   │   │   └────────────────────────────────────────────────┘   │   │   │
│   │   └────────────────────────────────────────────────────────┘   │   │
│   └────────────────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────────────┘
```

---

### Audit: What Pramāṇa & Foundry Already Do vs. Gaps to Close

| 14-Step Roadmap Primitive | Status in Pramāṇa / Foundry | Current Implementation & Concrete Upgrade |
|---|---|---|
| **01. Days-Long Autonomy** | 🔄 In Progress (Foundry) | Foundry uses OTP `DynamicSupervisor` and tick loops for background execution. FR-01–FR-07 establish durable state fencing. |
| **02. System Compounding** | ✅ Core Thesis | Invariant #3, #5, #8: Model is swappable; corpus artifacts, tests, and rules compound. |
| **03. 4-Layer Stack** | ✅ Active | Mapped explicitly across umbrella apps (`pramana`, `pramana_web`, `foundry`). |
| **04. Cost-Capability Routing** | ⚠️ Partial | **Upgrade:** Formally route tasks: Orchestrator (Pro) -> Workers (Flash) -> Graders/Verifiers (Flash-Lite / Haiku). |
| **05. Goal / Outcomes Criteria** | ✅ Active | Deterministic gates (`mix pramana.gate`) with ratcheted coverage thresholds and non-negotiable assertions. |
| **06. Verifier Beats Self-Critique** | ⚠️ Partial | **Upgrade:** In Foundry, separate maker from grader. A fresh verifier subagent with zero maker reasoning evaluates PR diffs against rubrics. |
| **07. Dynamic Workflows** | ✅ Active | Multi-canon parallel fan-out (Pāli, Chinese, Tibetan) joining at the cross-tradition synthesizer. |
| **08. Worktree Isolation** | ✅ Active | Rule 81 branch isolation; subagent `Workspace: :branch | :share` isolation prevents file collisions. |
| **09. Background Routines** | ✅ Active | Oban background queues for bakes and scheduled cron timers. |
| **10. 5-Stage Memory Progression** | ✅ Production Standard | **Fail → Investigate → Verify → Distill → Consult**: The foundational mechanism behind `docs/RULES.md`. |
| **11. Compounding State Files** | ✅ Production Standard | `docs/STATUS.md` (what is true now), `docs/PLAN.md` (living task list updated in same commit), `docs/RULES.md` (84 rules). |
| **12. Procedural Compounding** | ✅ Active | Rules trigger table in `AGENTS.md` and `docs/CODE_CONVENTIONS.md` updated with real post-mortem findings. |
| **13. Vision UI Self-Check** | ❌ Missing | **Upgrade:** Headless browser rendering of Phase 8 reader LiveViews checked by vision models for CJK text alignment. |
| **14. Safety & Policy Fallbacks** | ✅ Active | Read-only MCP surface; machine translations strictly prohibited from canonical citation (`method: :human` guard). |

---

### The Two Critical Upgrades Adopted

#### A. The Independent Verifier Sub-Agent (Maker != Grader)
Anthropic's empirical research confirms that a model evaluating its own work suffers from self-preferential bias: it follows its own reasoning path and overlooks blind spots.
- **The Upgrade in Foundry:** When an agent finishes drafting code for a ticket, it **cannot** mark the ticket complete.
- The coordinator spawns an **Independent Verifier Sub-Agent** with a clean context window containing *only*:
  1. The original ticket specification and acceptance criteria.
  2. The Git patch diff.
  3. The test execution command (`mix test`).
- The verifier attempts to attack edge cases and verify acceptance without exposure to the maker's exploratory narrative.

#### B. The 5-Stage Memory Progression Protocol
Pramāṇa enforces the 5-stage progression across all engineering sessions:
1. **Fail:** The system encounters a bug or test regression (e.g., `<note>` spanning line breaks).
2. **Investigate:** Isolate the failure mechanism without guessing (reproduce via isolated script).
3. **Verify:** Confirm the diagnosis with empirical measurement (e.g., 10,590 dropped lines).
4. **Distill:** Convert the finding into a general rule in `docs/RULES.md` and add it to the trigger table in `AGENTS.md`.
5. **Consult:** Every new agent session reads `AGENTS.md` and consults the trigger table *before* writing code.

---

## 9. Prompt for Multi-Model Review

When reviewing this specification with other models (Claude, Gemini, OpenAI, open-weights),
use the following prompt:

> "Review this Product Strategy, Systems Architecture, and UI/UX specification for Pramāṇa (`docs/PRODUCT_STRATEGY.md`).
> Critique it from six perspectives:
> 1. **Epistemic & Philological Rigor:** Does this design uphold the non-negotiable invariants
>    (no unattributed text, print edition coordinates, machine translations never cited as source)?
> 2. **User Experience & Cognitive Load:** Is the progressive disclosure model intuitive for an
>    English-speaking practitioner who does not know Classical Chinese or Tibetan? Where is friction introduced?
> 3. **Competitive Differentiation & Viral PMF:** Does the `/check` claim verification screen and
>    scholar export toolkit provide a defensible moat against generic frontier LLM wrappers (Perplexity, ChatGPT)
>    and existing archives (CBETA, SuttaCentral)?
> 4. **Harness, Graph, and Loop Systems Architecture:** Evaluate the tripartite separation (Harness ⊃ Graph ⊃ Loop ⊃ Model)
>    and the four anti-pattern mitigations. Does the multi-canon parallel fan-out (Pāli/Chinese/Tibetan) and the
>    adversarial red-team verification gate provide adequate protection against production agent failure modes?
> 5. **Composable Agent Middleware Pipeline:** Evaluate the adaptation of the LangChain middleware pattern ('Plug for Agents')
>    to Elixir/OTP. Are the four intercept hooks (before_model, after_model, before_tool, after_tool), the speculative
>    stream verification in LiveView, and the diagnostic compactor effectively structured for production resilience?
> 6. **Self-Improving Compounding Stack:** Evaluate the 4-layer compound architecture (Primitives -> Orchestration -> Memory -> Self-Improvement)
>    and the 5-stage memory progression (Fail -> Investigate -> Verify -> Distill -> Consult). Does the independent verifier subagent
>    and the cost-capability routing matrix effectively eliminate maker bias and token waste in long-running sessions?"
