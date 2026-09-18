# Chinese pilot participant protocol and study data governance

**Status:** frozen pre-recruitment protocol; no participant recruitment or data collection is authorized.
**Decision date:** 2026-09-17
**Pilot:** `chinese-commentary-v1`
**Machine-readable companion:** [`pilot_participants.json`](pilot_participants.json)

[Pilot charter](PILOT_CHARTER.md) · [pilot acceptance](PILOT_ACCEPTANCE.md) ·
[pilot preflight](PILOT_PREFLIGHT.md) · [validation](VALIDATION.md)

This protocol turns the charter's privacy promises into a concrete measured-pilot contract.
It does not create an account-history product, a research notebook, a public dataset or a
general permission to retain Dharma questions.

The default product boundary remains the charter's D5 rule:

- full questions, answers and private notes are not retained server-side after an ordinary
  non-study task;
- minimal non-content operational telemetry may exist;
- **measured participant records require explicit study consent**; and
- evidence export is user-controlled.

A person may use or inspect the product without becoming a measured study participant.
Declining study retention means their task does not enter the pilot denominator.

This is Pramāṇa's product-research protocol, **not** an IRB/human-subjects-regulatory
determination. If an institution or organization runs the study, it must obtain whatever
review/approval its own policies and applicable requirements demand. This protocol also
authorizes no participant compensation, recruitment spend or outreach.

Pilot v1 is **adult-only (18+)** by self-attestation. Do not collect date of birth merely
to establish eligibility, and do not enroll minors under this protocol.

# 1. Consent before collection

A measured participant record may be created only after the participant receives the
frozen protocol version and affirmatively consents.

## Required disclosures

Before the first measured task, explain plainly that:

1. this is a **feasibility study**, not spiritual direction, realization assessment,
   medical advice or a claim to doctrinal authority;
2. the search scope is a bounded Chinese pilot corpus and may omit relevant Buddhist texts;
3. the Chinese witness is authoritative textual evidence; human/generated English and the
   answer synthesis are separate layers;
4. any model/provider actually used, and the applicable source-data boundary, must be
   disclosed once separately authorized;
5. the study will retain the participant's full measured task record, including question
   text and generated answer, for the declared evaluation purpose;
6. the retention deadline and deletion rule are fixed below;
7. the participant may skip a question, mark a task private/excluded or withdraw without
   penalty;
8. evidence export is controlled by the participant;
9. sharing an individual question, answer or feedback publicly is **not** included in
   ordinary study consent; and
10. there is no penalty for declining or withdrawing; and
11. the fourteen-day repeat-use signal is **unprompted**: the participant is told the
    observation window in advance, but the study does not remind/nudge them to return merely
    to manufacture a repeat task.

The consent presentation must not imply that source verification proves interpretation,
that the corpus is exhaustive or that generated English is canonical evidence.

## Required study consents

A task can enter the participant-pilot denominator only when the participant has
affirmatively consented to all of these:

- participation in the feasibility study;
- retention of the full task record for evaluation;
- qualified evaluator review of the task record;
- the current-alternative intake described below; and
- self-attestation that the participant is at least 18 years old.

These are one measured-study bundle because each is necessary to evaluate the frozen pilot
decision. A participant who declines any required item may still use an ordinary
non-study path, but their task is not silently included in the study.

The consent receipt itself is pseudonymous. It records only:

- a random `consent_receipt_id`;
- pseudonymous `participant_id`;
- protocol revision;
- consent timestamp;
- required and optional consent values; and
- the 18+ self-attestation.

It contains no direct identity fields. Any contact/identity roster remains separate from
both the consent receipt and the study task dataset.

## Optional consent remains separate

The following default to **off**:

- public sharing of an anonymized/de-identified individual example;
- public quotation of participant feedback; and
- logistical follow-up contact beyond what is necessary to schedule/operate the study.

Neither may be bundled into study participation. Consent to retain a task for internal
evaluation is not consent to publish it.

No audio, video or screen recording is part of pilot v1.

# 2. Identity separation

Study analysis uses random pseudonymous identifiers:

- `participant_id`;
- `task_id`; and
- `evaluator_id`.

The study dataset must not contain the participant's name, email address, telephone number,
account credentials or an identity-linkage key.

A scheduling/logistics roster may temporarily map contact information to the pseudonymous
participant ID, but it is a **separate access-controlled roster**, not part of the task
dataset or consent receipt. It is deleted under the shorter contact-retention rule below.
It may not be used to nudge a participant to create the repeat-use event being measured.

The pilot does not collect:

- passwords, API keys or account credentials;
- payment information;
- government identifiers;
- precise location;
- unrelated contact lists;
- audio/video/screen recordings; or
- free-form private notes outside the declared task record.

The study does not attempt to infer demographic, religious, medical or other sensitive
attributes that the participant did not explicitly provide for the study's defined purpose.

# 3. What one retained task record contains

A consented measured task record contains enough information to evaluate the product and
reproduce the study decision without creating a personal research notebook.

## Required record

Each retained measured task records:

- protocol revision;
- pseudonymous participant and task IDs;
- audience stratum;
- task class;
- exact question text;
- submission time;
- declared corpus/scope identity;
- system/release identity;
- query-planning receipt;
- retrieval receipt;
- selected evidence identifiers;
- generated answer;
- rendering/generation metadata applicable to the task;
- outcome state and failure category;
- time to useful evidence;
- whether the task was commentary-eligible and whether commentary was opened;
- evidence-packet traceability result;
- comprehension-check result; and
- the consent-receipt ID.

The record does **not** store direct identity fields.

## Optional record fields

The participant may additionally provide:

- task-specific feedback;
- a short optional note about their current alternative workflow; and
- an evaluation copy of the evidence packet **only when both study consent and source
  rights permit that copy**.

The current-alternative optional note is capped at **500 characters**. It must not be used
to solicit passwords, account details, private correspondence or unrelated personal data.

# 4. Current-alternative intake

The pilot compares Pramāṇa with what the participant actually does today rather than an
invented competitor.

Before or at the first measured task, collect one structured current-alternative record.

The participant may select any of:

- web search;
- canon/archive search;
- general chat model;
- specialist Buddhist tool;
- books/manual research;
- teacher or study community;
- other; or
- none.

Also record coarse buckets for:

- frequency of use;
- usual time required; and
- main friction category.

Exact product/service names are not required for the decision metric. The optional
500-character note may capture context when useful.

Never request login credentials, paid-account status, API keys or private account details
for another service.

# 5. Sensitive or unexpectedly personal questions

Dharma questions can be personal even when they are not secrets. Personal subject matter
does **not** create permission for secondary use.

Before each measured task, remind participants not to submit:

- passwords or credentials;
- confidential third-party material;
- secrets they do not want a study evaluator to inspect; or
- unnecessary highly personal information.

A participant may mark a task **private / exclude from study** before or after submission.
That removes its full content from research use and from the study denominator. This right
belongs to the participant: the operator/evaluator may not suggest exclusion, deletion or
"privacy" reclassification because the system performed badly. Every such exclusion is
counted/reported separately and must be replenished before the pilot decision.

If an operator/evaluator discovers accidental sensitive content that should not have been
retained:

1. stop research use of that task;
2. delete the full content promptly;
3. exclude the task from participant metrics unless a clean replacement task is completed;
4. retain only the minimum non-content incident receipt needed to establish that the
   protocol action occurred; and
5. do not copy the sensitive text into an incident log.

Sensitive-content handling never changes the source or rights policies for CBETA, DILA,
human translations or generated material.

# 6. Retention and deletion

The pilot intentionally uses **two deletion caps** so study data cannot remain indefinitely
because a study decision drifts.

For a full measured task record, delete the individual content and pseudonymous per-task
record by the **earlier** of:

- **30 calendar days after the pilot continue/iterate/stop decision is recorded**; or
- **90 calendar days after that task was collected**.

After that deadline:

- no question text, answer text, participant feedback or individual evaluation content
  remains;
- no pseudonymous participant/task-level metadata remains merely for convenience; and
- only non-reconstructive aggregate metrics and the public/maintained decision record may
  remain.

The separate logistics/contact roster is deleted no later than **7 calendar days after the
participant's fourteen-day observation window ends**, or sooner on withdrawal. Contact
during that window may be used only for necessary logistics—not to request, remind or
prompt the voluntary repeat task.

A participant withdrawal request triggers deletion of their individual study records
within **7 calendar days maximum**.

Deletion must include working copies, evaluator copies and study export copies under the
operator's control. A deletion process that leaves an ordinary backup capable of silently
restoring the participant record is not complete; any exceptional immutable backup must
have a documented expiry and may not be used for study analysis.

# 7. Purpose boundaries

Consent for this study does **not** authorize the retained task record to become:

- model-training or fine-tuning data;
- a canonical corpus/source record;
- Foundry memory or agent-training material;
- a general user-profile/history store;
- marketing/audience profiling data; or
- an unrelated future research dataset.

Operational non-content telemetry is not retroactively converted into study consent.
Likewise, study consent is not converted into broader operational or training permission.

Any materially different secondary use requires a new explicit consent and its own
rights/privacy review.

# 8. Evidence packet handling

Evidence export remains participant-controlled.

The study does **not** require the server to retain a copy of an exported evidence packet.

For evaluation, retain by default only:

- the packet/content hash;
- source IDs;
- the independent reviewer's traceability result; and
- the applicable rights disposition.

A packet-body copy may be retained inside the consented study record only when:

1. the participant consented to measured full-record retention; and
2. every included source/rendering excerpt is permitted to be retained for that operation.

A local user export is not itself permission for the project to retain or publish a second
copy.

# 9. Evaluator separation

Participants and evaluators have separate pseudonymous identifiers and roles.

A qualified Buddhist-Chinese evaluator may also be a member of the participant pool, but:

- they cannot provide the **independent qualified source judgment for their own task**;
- their usability response as a participant remains separate from later evaluator scoring;
- disagreements between qualified evaluators are preserved rather than averaged away; and
- adjudication, when needed, records the original judgments and the reason for the final
  classification.

If no independent qualified judgment is available for a measured task, that task cannot be
represented as independently source-reviewed merely because its participant is bilingual.

This protocol does not satisfy the separate `bilingual_evaluators` gate; actual qualified
people still have to be identified.

# 10. Task outcomes and denominator rules

Eligibility must not be decided by whether the system happened to succeed.

A task enters the attempted-task denominator when a consented participant **submits a
natural measured task** under the frozen protocol.

These outcomes remain in the denominator:

- `success_supported`;
- `success_scoped_unsupported`;
- `failure_retrieval_miss`;
- `failure_wrong_evidence`;
- `failure_comprehension`;
- `failure_timeout`;
- `failure_technical`; and
- `abandoned_after_start`.

### Success on a supported question

A supported question can succeed only when the task satisfies the charter/acceptance
criteria for useful source-backed evidence, source-role honesty and comprehension.

A retrieval miss on a question later confirmed to have adequate in-scope evidence is a
failure. It may not be reclassified as "out of scope" after seeing the system fail.

### Success on a genuinely unsupported/out-of-scope question

A natural unsupported question may count as a successful task **only** when qualified
review confirms the declared pilot scope does not support the requested evidence and the
system gives a correct scoped unsupported/refusal result without a false exhaustiveness
claim.

Thus "we cannot support this from this declared scope" can succeed; "Buddhism has no such
teaching" cannot.

### Failures stay visible

Timeouts, technical failures and participant abandonment after task start count as failed
eligible attempts. They are not deleted from the denominator because retrieval did not run
to completion.

The following are excluded and reported separately:

- participant withdrawal from the study;
- a task the participant marks private/excluded;
- a protocol-invalid event rejected before task start;
- rehearsal/training/calibration cases; and
- a duplicate record that was not an independently attempted natural task.

After exclusions/withdrawals, the pilot must still contain:

- at least **24 eligible tasks**;
- at least **6 eligible tasks per user stratum**; and
- at least **6 commentary-eligible tasks**.

Removed tasks are replaced with new natural participant tasks; the denominator is never
reduced to preserve a favorable percentage. Participant-initiated privacy withdrawal is
always honored, but operator/evaluator staff may not invite exclusion after seeing an
unfavorable result.

# 11. Withdrawal

A participant may withdraw from the measured study without penalty until the pilot decision
is recorded.

On withdrawal:

1. stop new research use of that participant's records immediately;
2. delete individual retained records within 7 calendar days;
3. remove their tasks from participant denominators;
4. recompute any pre-decision aggregates that included them; and
5. do not make new public example use of their task or feedback.

A previously merged/published aggregate decision record that contains no reconstructive
individual content may remain after later deletion, but it must not be used as a route to
recover the withdrawn participant's task.

If withdrawal/exclusion reduces any cohort/task minimum below the charter floor, collect
replacement natural tasks before making the pilot decision.

# 12. Public sharing

Public sharing defaults **off** for individual task material.

Aggregate results may be reported when they do not contain task content. Because the cohort
is small, every public aggregate/example review must consider whether combinations of
audience stratum, exact question, dates or distinctive feedback could re-identify a person.

Publishing any individual question, answer, screenshot, evidence packet or participant
feedback requires the separate optional consent recorded for that purpose.

Participant consent cannot override source-text/rendering rights: source excerpts remain
subject to the Chinese pilot rights matrix.

# 13. Incident handling

The following are study-data incidents:

- unauthorized retention beyond the frozen deadline;
- unauthorized disclosure/access;
- secondary use without consent;
- sensitive content retained against this protocol;
- leakage of the identity/contact mapping into the study dataset; or
- retention/sharing of rights-restricted evidence-packet content.

For an incident:

1. stop the affected study processing;
2. contain access;
3. delete or quarantine data as required;
4. record a **non-content** incident receipt;
5. notify the operator and affected participant when appropriate; and
6. resolve the affected path before resuming it.

Do not reproduce the sensitive/private text in the incident record merely to prove that the
incident occurred.

A privacy/retention breach maps to the frozen acceptance taxonomy's
`CF11_privacy_or_retention_violation`.

# 14. Preflight disposition

This document plus `pilot_participants.json` freezes:

- participant disclosures and required study consent;
- purpose separation;
- study-record fields;
- pseudonymous identity handling;
- current-alternative intake;
- sensitive-task behavior;
- retention/deletion and withdrawal deadlines;
- evidence-packet study handling;
- evaluator/participant role separation;
- denominator/outcome rules; and
- public-sharing/incident rules.

That is sufficient for `participant_protocol` to become **ready as a frozen protocol
specification**.

It does **not** mean:

- anyone has been recruited;
- anyone has consented;
- the bilingual evaluator requirement is satisfied;
- the corpus scope is frozen;
- rights/provider/inference gates are satisfied; or
- participant execution may begin before all remaining mandatory gates are ready.

No real participant data is needed to validate this protocol.

## Next independent handoff

Once this protocol is accepted, the strongest next technical preparation remains the exact
pilot-scope materializer:

accepted release → demand-weighted 14-work seed → typed commentary/subcommentary traversal
→ passage-alignment census → release-bound immutable scope artifact.

That work can be built before G0, but `pilot_scope` must remain blocked until the
materializer actually runs against the accepted live release and the result is reviewed.
