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

## 7. Prompt for Multi-Model Review

When reviewing this specification with other models (Claude, Gemini, OpenAI, open-weights),
use the following prompt:

> "Review this Product Strategy, Systems Architecture, and UI/UX specification for Pramāṇa (`docs/PRODUCT_STRATEGY.md`).
> Critique it from four perspectives:
> 1. **Epistemic & Philological Rigor:** Does this design uphold the non-negotiable invariants
>    (no unattributed text, print edition coordinates, machine translations never cited as source)?
> 2. **User Experience & Cognitive Load:** Is the progressive disclosure model intuitive for an
>    English-speaking practitioner who does not know Classical Chinese or Tibetan? Where is friction introduced?
> 3. **Competitive Differentiation & Viral PMF:** Does the `/check` claim verification screen and
>    scholar export toolkit provide a defensible moat against generic frontier LLM wrappers (Perplexity, ChatGPT)
>    and existing archives (CBETA, SuttaCentral)?
> 4. **Harness, Graph, and Loop Systems Architecture:** Evaluate the tripartite separation (Harness ⊃ Graph ⊃ Loop ⊃ Model)
>    and the four anti-pattern mitigations. Does the multi-canon parallel fan-out (Pāli/Chinese/Tibetan) and the
>    adversarial red-team verification gate provide adequate protection against production agent failure modes?"
