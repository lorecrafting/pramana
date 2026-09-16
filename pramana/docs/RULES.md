# Rules that generalize

Stable numbered lessons from defects. Use [activity triggers](../../docs/agents/RULE_TRIGGERS.md)
to choose what to read; do not load the entire collection into every session.
The rule bodies and their evidence are retained, including historical measurements.

## Numbered rules

| Rule | Principle |
|---|---|
| <a id="rule-1"></a>[1](rules/01-38.md#rule-1) | Any buffered element that can span a line boundary must be split at that boundary. |
| <a id="rule-2"></a>[2](rules/01-38.md#rule-2) | Reproducibility is not fidelity. |
| <a id="rule-3"></a>[3](rules/01-38.md#rule-3) | A line is only droppable if nothing was printed on it. |
| <a id="rule-4"></a>[4](rules/01-38.md#rule-4) | Never silently ignore an unknown option |
| <a id="rule-5"></a>[5](rules/01-38.md#rule-5) | Every declared filter must have a test proving it changes the result set. |
| <a id="rule-6"></a>[6](rules/01-38.md#rule-6) | Filtering an ANN index post-hoc truncates silently. |
| <a id="rule-7"></a>[7](rules/01-38.md#rule-7) | Defects that only appear at scale will not appear in the proof run. |
| <a id="rule-8"></a>[8](rules/01-38.md#rule-8) | A scripted patch that reports success may have done nothing. |
| <a id="rule-9"></a>[9](rules/01-38.md#rule-9) | `on_conflict: :nothing` on a reference row makes it write-once. |
| <a id="rule-10"></a>[10](rules/01-38.md#rule-10) | A source's own LICENSE file is not the licence. |
| <a id="rule-11"></a>[11](rules/01-38.md#rule-11) | A check constraint on an enumerated column is a contract with the registry. |
| <a id="rule-12"></a>[12](rules/01-38.md#rule-12) | A test that hardcodes a value the registry owns will fight the registry. |
| <a id="rule-13"></a>[13](rules/01-38.md#rule-13) | When a column mirrors a claim someone else made, carry how confident you are separately from the claim. |
| <a id="rule-14"></a>[14](rules/01-38.md#rule-14) | `insert_all` binds one parameter per column per row, so batch size is a function of row width. |
| <a id="rule-15"></a>[15](rules/01-38.md#rule-15) | A grouped query is not an aggregate. |
| <a id="rule-16"></a>[16](rules/01-38.md#rule-16) | A convention can be the opposite of what it looks like — check before projecting it. |
| <a id="rule-17"></a>[17](rules/01-38.md#rule-17) | An optional dependency that silently halves a system is worse than a required one. |
| <a id="rule-18"></a>[18](rules/01-38.md#rule-18) | A benchmark's first job is to be wrong in ways you can see. |
| <a id="rule-19"></a>[19](rules/01-38.md#rule-19) | A session-level `SET` does not survive a connection pool. |
| <a id="rule-20"></a>[20](rules/01-38.md#rule-20) | A cascading delete can destroy work that cost money to produce. |
| <a id="rule-21"></a>[21](rules/01-38.md#rule-21) | Positional query bindings break silently when a join is added in front of them. |
| <a id="rule-22"></a>[22](rules/01-38.md#rule-22) | A coverage figure's denominator is a claim about the corpus, not about the table you happen to be counting. |
| <a id="rule-23"></a>[23](rules/01-38.md#rule-23) | A file is a packaging unit; the work is a citation unit. |
| <a id="rule-24"></a>[24](rules/01-38.md#rule-24) | A shared helper only helps if using it is easier than not. |
| <a id="rule-25"></a>[25](rules/01-38.md#rule-25) | Proving absence is the expensive case for an index. |
| <a id="rule-26"></a>[26](rules/01-38.md#rule-26) | A `with` whose `else` discards everything turns a shape bug into an empty result. |
| <a id="rule-27"></a>[27](rules/01-38.md#rule-27) | Character data outside the text element is the library talking, not the book. |
| <a id="rule-28"></a>[28](rules/01-38.md#rule-28) | An idempotent loader makes assembly the caller's problem. |
| <a id="rule-29"></a>[29](rules/01-38.md#rule-29) | The closing check counts bytes, not units the parser defined. |
| <a id="rule-30"></a>[30](rules/01-38.md#rule-30) | A chunk size is a claim about a tokenizer, and an untested one fails silently. |
| <a id="rule-31"></a>[31](rules/01-38.md#rule-31) | A benchmark that cannot see a tradition reports it as absent, not as bad. |
| <a id="rule-32"></a>[32](rules/01-38.md#rule-32) | Refute the obvious explanation before acting on it. |
| <a id="rule-33"></a>[33](rules/01-38.md#rule-33) | A partial match between two editions is more dangerous than none. |
| <a id="rule-34"></a>[34](rules/01-38.md#rule-34) | `preload` through a join ships every column of the joined row, once per row. |
| <a id="rule-35"></a>[35](rules/01-38.md#rule-35) | Making a long run fault-tolerant is half the job; the other half is making sure the shrunken denominator cannot be read as a result. |
| <a id="rule-36"></a>[36](rules/01-38.md#rule-36) | A tokenization rule is a rule about ONE script, and the `else` branch is where the next script goes to die. |
| <a id="rule-37"></a>[37](rules/01-38.md#rule-37) | A speedup measured on one workload does not fix a timeout observed on another, even at the same line number. |
| <a id="rule-38"></a>[38](rules/01-38.md#rule-38) | `LIMIT` without `ORDER BY` turns a bad plan into an intermittent one. |
| <a id="rule-39"></a>[39](rules/39-59.md#rule-39) | When a planner abandons an index, the threshold is selectivity, not a count. |
| <a id="rule-40"></a>[40](rules/39-59.md#rule-40) | Profile the whole operation before optimising the part an error message names. |
| <a id="rule-41"></a>[41](rules/39-59.md#rule-41) | A rule written after a fix does not sweep for the other instances. |
| <a id="rule-42"></a>[42](rules/39-59.md#rule-42) | A hand-maintained column list is a defect with a test, not a fix. |
| <a id="rule-43"></a>[43](rules/39-59.md#rule-43) | A source acquired in parts must MERGE into its lockfile entry, never replace it. |
| <a id="rule-44"></a>[44](rules/39-59.md#rule-44) | Every coverage ratio needs a denominator that can see rows that do not exist. |
| <a id="rule-45"></a>[45](rules/39-59.md#rule-45) | Take one census from the SOURCE, before parsing, for every ingest. |
| <a id="rule-46"></a>[46](rules/39-59.md#rule-46) | A number a check derives from raw markup must be derived by the SAME rule the pipeline uses. |
| <a id="rule-47"></a>[47](rules/39-59.md#rule-47) | A lesson learned from one measurement does not transfer to a different one without being re-measured. |
| <a id="rule-48"></a>[48](rules/39-59.md#rule-48) | "Blank" must be defined once, as the ABSENCE of every kind of content, never as a list of the kinds someone remembered. |
| <a id="rule-49"></a>[49](rules/39-59.md#rule-49) | Measure the instrument's variance before attributing a delta to your change. |
| <a id="rule-50"></a>[50](rules/39-59.md#rule-50) | Carry what you were given; never parse it apart and rebuild it. |
| <a id="rule-51"></a>[51](rules/39-59.md#rule-51) | A collection's NAME is not its contents, and neither is its size. |
| <a id="rule-52"></a>[52](rules/39-59.md#rule-52) | A volume is not the unit of loading, and this is the second source it has bitten. |
| <a id="rule-53"></a>[53](rules/39-59.md#rule-53) | A format that is "obviously" uniform across an edition is a table, and the table is the publisher's, not yours. |
| <a id="rule-54"></a>[54](rules/39-59.md#rule-54) | Normalise by the thing doing the measuring, not by the thing being measured. |
| <a id="rule-55"></a>[55](rules/39-59.md#rule-55) | Whitespace you introduced is yours, never the edition's — do not match on it. |
| <a id="rule-56"></a>[56](rules/39-59.md#rule-56) | When a record says which files it governs, match on that — not on an identifier that usually correlates. |
| <a id="rule-57"></a>[57](rules/39-59.md#rule-57) | A safety check is not a completeness check, and the artefact needs both. |
| <a id="rule-58"></a>[58](rules/39-59.md#rule-58) | A cache keyed on existence is a cache that poisons itself. |
| <a id="rule-59"></a>[59](rules/39-59.md#rule-59) | A "reasonable" constraint on a coordinate is an assumption about an edition, and the next edition will refute it. |
| <a id="rule-60"></a>[60](rules/60-68.md#rule-60) | A capability the MCP surface cannot reach has not shipped. |
| <a id="rule-61"></a>[61](rules/60-68.md#rule-61) | A derived value must never assert more precision than the thing it was derived from. |
| <a id="rule-62"></a>[62](rules/60-68.md#rule-62) | A measurement bug reads exactly like a finding. |
| <a id="rule-63"></a>[63](rules/60-68.md#rule-63) | Judge a command by its exit code, never by grepping its output. |
| <a id="rule-64"></a>[64](rules/60-68.md#rule-64) | A derived identifier must be re-derived, or something must notice it wasn't. |
| <a id="rule-65"></a>[65](rules/60-68.md#rule-65) | `rescue` does not catch an exit, and instrumentation is where that bites. |
| <a id="rule-66"></a>[66](rules/60-68.md#rule-66) | A `mix` task edited this session runs its OLD code, and prints old output. |
| <a id="rule-67"></a>[67](rules/60-68.md#rule-67) | A pooled `Repo` call does not stay on one connection, and the sandbox hides it. |
| <a id="rule-68"></a>[68](rules/60-68.md#rule-68) | A string test against a URN encodes one edition's citation grammar, and every other edition fails it in silence. |
| <a id="rule-69"></a>[69](rules/69-75.md#rule-69) | A score that asks whether the retrieved span CONTAINS the target is a function of the target's size, and cannot be compared across populations whose targets differ in size. |
| <a id="rule-70"></a>[70](rules/69-75.md#rule-70) | An optimisation is a claim about a bottleneck, and it expires when the bottleneck moves. |
| <a id="rule-71"></a>[71](rules/69-75.md#rule-71) | Concatenating rows needs a TOTAL order, and the source's order is rarely recoverable from the address. |
| <a id="rule-72"></a>[72](rules/69-75.md#rule-72) | An undirected graph cannot answer a directed question, and excluding the obvious self-reference is not enough. |
| <a id="rule-73"></a>[73](rules/69-75.md#rule-73) | Count distinct evidence, not the rows carrying it. |
| <a id="rule-74"></a>[74](rules/69-75.md#rule-74) | A validation set drawn from an existing method inherits that method's population, not the one you are about to write to. |
| <a id="rule-75"></a>[75](rules/69-75.md#rule-75) | The restriction that makes a method work also decides what it can never find, and it will substitute rather than abstain. |
| <a id="rule-76"></a>[76](rules/76-83.md#rule-76) | A cost model fitted to one measurement is not a model. Falsify it with a case it says should be slower. |
| <a id="rule-77"></a>[77](rules/76-83.md#rule-77) | A rule that loses to a real need needs a mechanism, not a restatement. |
| <a id="rule-78"></a>[78](rules/76-83.md#rule-78) | A ratchet set at the waterline manufactures the behaviour it was built to prevent. |
| <a id="rule-79"></a>[79](rules/76-83.md#rule-79) | An invariant enforced by a crash is not enforced, and a test that bridges an inconsistency is what keeps the crash alive. |
| <a id="rule-80"></a>[80](rules/76-83.md#rule-80) | A prediction and a result measured on different populations do not subtract into an effect. |
| <a id="rule-81"></a>[81](rules/76-83.md#rule-81) | In a shared working tree, stage the files you touched. Never `git add -A`. |
| <a id="rule-82"></a>[82](rules/76-83.md#rule-82) | An experiment arm named by a mutable id is not an arm. |
| <a id="rule-83"></a>[83](rules/76-83.md#rule-83) | A constant justified by a measurement carries the population it was measured on, and the justification does not travel when a new population arrives. |
| <a id="rule-84"></a>[84](rules/84-84.md#rule-84) | The arm you treat as the reference is the one you forget to check. |

## One-off gotchas

[Historical implementation gotchas](rules/GOTCHAS.md) are separate from the stable numbered rules.

## Rules that generalize

This heading preserves the original reference. Use the numbered index above.
