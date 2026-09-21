# Subcommit 2 read-only inventory: `expected_revisions` vs `domain_reads`

Read-only against `4715c25`, unchanged since. No source edits. The correction design names reconciling these
two shapes as "part of subcommit 2, not an implementation detail"; this inventory says what
the gap concretely is.

## The two shapes

**`expected_revisions`** — the command's, checked by `Gateway.check_expected_revisions/4`
(`gateway.ex:1873`):

- A flat **map**, `%{key_string => revision}`.
- Key grammar is `RecordCodec.decode_revision_key/1` (`record_codec.ex:342`):
  `projection/<ns>/<id>`, `dependency/<ns>/<id>`, `policy/<id>`, `control/<id>`,
  `ledger/<id>` — and both `<ns>` and `<id>` are **base64url-encoded**
  (`gateway.ex:1946-1950`).
- Values are a non-negative integer or the string `"absent"`.
- Completeness is cross-checked against `required_projection_reads/1`, which derives keys
  from the proposal's own projections.

**`domain_reads`** — the plan's (`transition_plan.ex:20, 29, 38, 283-296`):

- A **list** of maps with exact keys `kind entity_id revision`.
- `kind` is drawn from the closed vocabulary `~w(state ticket objective pm)`.
- `entity_id` is a **raw** identifier, not encoded.
- Uniqueness is on `{kind, entity_id}`.
- Accompanied by a **scalar** `expected_domain_revision`.

## Four concrete mismatches

1. **Container.** Map keyed by opaque string against a list of typed records. Neither is
   derivable from the other without a stated rule.
2. **`kind` has no namespace.** `expected_revisions` keys carry a *namespace*;
   `domain_reads` carries a *kind* from a four-value domain vocabulary. **Nothing maps one
   to the other.** Namespaces in this codebase are free-form caller-supplied strings —
   `"h0-v1"` at `h0_accepted_fr07_boundary.ex:363`, `"atomic-v2"` in the bundle tests — and
   no constant anywhere declares the namespace a `ticket` or `objective` read belongs to.
   So a plan declaring `{kind: "ticket", entity_id: "T1"}` has no defined translation into
   any `projection/<ns>/<id>` key.
3. **Encoding.** Even with a namespace decided, `entity_id` is raw in `domain_reads` and
   base64url in the revision key, so the two are not directly comparable.
4. **The scalar.** `expected_domain_revision` is one number. `expected_revisions` has no
   single-domain notion, and `domain_reads` may name several entities. What the scalar
   corresponds to is unstated.

## Why this is the familiar gap class, not a detail

Three times now this codebase has shipped a vocabulary that was **declarable but not
derivable**, and each time it was found by asking whether a mechanism could express a
contract row rather than whether it was internally consistent:

- `launch_authority_v1` had no producer, so every admission slot failed closed.
- `terminal_settlement_v1` has a declared output kind, no producer and no slot.
- `reset_fact_v1` has a slot and no producer.

`domain_reads` is the same shape of defect one level up: a plan may **declare** its domain
reads, and Gateway has no path that **checks** them, because the correspondence to the
thing it does check is undefined. `decide/3` in subcommit 2 is the first caller that will
produce a plan whose `domain_reads` are the prestate the kernel actually read — so this is
the subcommit where a declaration nothing verifies becomes load-bearing.

## What subcommit 2 must settle, before writing `decide/3`

1. Whether `kind` maps to a fixed namespace per kind (and if so, name the constants), or
   whether `domain_reads` should carry the namespace directly and `kind` be dropped.
2. Whether `expected_revisions` is derived *from* `domain_reads` at plan-resolution time,
   or whether both are supplied and must agree — and if they must agree, what checks it.
3. What `expected_domain_revision` is the revision *of*.
4. An executable assertion that every `domain_read` a plan declares is one Gateway actually
   checks — the same coverage shape as the R4a slot assertions added after the codec's
   second gap, and the shape whose absence let the first two through.

**Recommendation:** settle these as a written decision before `decide/3` is written, not
during. The design already says so; this inventory is the evidence for why.
