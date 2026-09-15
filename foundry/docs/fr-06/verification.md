# FR-06 verification — revision 3, 2026-09-12

Scope: revision 2 evidence below remains historical. Revision 3 is the bounded R4a
design correction requested by [independent review v2](../FR-06-DESIGN-REVIEW-V2.md).
No production repair, test implementation, host provisioning, daemon access, credentials,
model invocation, Git integration or activation. **R4a correction proposed; focused
independent verification pending. FR-07 remains blocked on that verification and FR-03.**

## Revision 3 input verification

Before editing, the v2 manifest digest was
`42817763eda93bacaa0598eda3c63cb957bce20306cfae73857f5d2c3fef075b`.
SHA-256 verification found 11 unchanged entries matching exactly. Only the two files the
v2 independent reviewer expressly changed after its verification differed:

- `foundry/docs/REPAIR-PLAN.md` was
  `2a0e464baa081e79aca382f05c4532eb58a48ecaf642a86062ce5d450ae4c8b2`;
  the manifest records `a882edd74554cc17ed929431dbb519a2c0691bd2e51b5f9d44f1c02bdd69c300`.
- `docs/PLAN.md` was
  `a6e500f3f065c38f0d7f1640361e37c95bd84ad020271ff1ccb27072535c1b84`;
  the manifest records `431e71f48e35c579de0c6ac6f6af6e81c866cccd1745e57703d96fbece390f42`.

The v2 review states that all 13 inputs and the manifest digest matched before it added
review-status passages to precisely those files. Targeted inspection found those additions:
the `ready after specified corrections; R4a open` plan status, R4a handoff/completion
entry and matching Foundry status paragraph. No other manifest input differed. This
accounts for the documented drift without treating the later status as reviewed proposal
content. Both independent reviews and `review-response-v2.md` remain unchanged.

## Input provenance verified before revision

HEAD: `a3fa302342238ae3d5a133b35bd86f4fa4f13710`. The original manifest SHA-256 was
`cb1a9b6b2136e9195149a4a6c1c6db6e4fd7fd28aadcc08966ec90a3386403cb`.
Python hashlib checks matched its workflow contract, storage script and results entries.
REPAIR-PLAN differed as documented by the reviewer; docs/PLAN also had the documented
Foundry review-status update. Every other path in the historical review's hash inventory
matched. No unexpected drift was found.

A temporary baseline snapshot and verification script reversed only these status edits
in memory; neither original nor current files were overwritten to perform the check.
The reconstructed plan hashes exactly matched the review's pre-edit inventory:

- REPAIR-PLAN: `d493019f7f57c4bc8b132cbe211fc8fd72d92fb4e50d0336c7d8beac475045a2`.
- docs/PLAN: `03d38d0065954c2eccaa84c1a47789363809b12ae591dda58651d9ab5c48fee9`.

The [v2 response](review-response-v2.md) also records their start-of-revision hashes.
Historical review and audit bytes remain unchanged, as do original storage script/results,
pre-existing README/CLI/Coordinator edits and unrelated review artifacts. Only the Foundry
entry of root docs/PLAN changed. No files were staged, committed, reset or deployed.

## Historical storage evidence, unchanged

The v1 author ran `python3 foundry/docs/fr-06/storage_spike.py`; the independent reviewer
reran it with captured output/timeout and exactly reproduced [storage-results.json](storage-results.json).
V2 read and hash-verified these inputs but **did not rerun** the experiment: it changes no
storage code/data or measured claim. SQLite remains a provisional maintenance/transaction
choice. Both arms passed the shared selected boundaries; no superiority over the full
audit failure set or performance advantage is established.

The experiment's explicit limits remain binding:

- One bundle per SQL row/journal frame; selected child `os._exit` boundaries around
  commit and lost reply. No separate-table atomicity/reducer proof or interruption
  inside commit/fsync, and no hardware power loss.
- Second child fails under held SQLite/flock writer and succeeds after release.
  Its exit code, not its exact lock error, is asserted. No external-effect fencing proof.
- SQLite `max_page_count` capacity error preserves earlier records. No filesystem
  ENOSPC, WAL/checkpoint capacity, equivalent journal capacity fault or sync failure.
- Backup assertion checks row count, not full content/replay with concurrent writes.
  Migration check rolls back PRAGMA user_version, not deployed schema/code downgrade.
- Unknown application body version refused; torn journal tail/interior checksum damage
  refused. No SQLite page/WAL corruption injection.
- Unpublished partial journal snapshot is ignored by reading the old snapshot directly;
  discovery, atomic publication, rename and directory-sync failure are not exercised.

Actual binding/platform, physical write/sync faults, full-content backup/replay, large
history/import reruns, compaction and compatible code/state rollback remain FR-07/19/17
acceptance. No broad new storage benchmark is needed for this design revision.

## V2 commands and results

- `git status --short`, `git rev-parse HEAD`: captured existing changes and HEAD above.
- Targeted `cat`, `sed`, `rg`: project orientation, agreed contract, complete review,
  proposal, tickets, evidence and relevant audit findings. Large combined reads were
  truncated; focused reads recovered the review tail, hashes, plan state and relevant
  rules. No full implementation audit or installed-harness examination occurred.
- Python hashlib comparison against original manifest and every historical review hash:
  only the two documented status edits differed. `python3 /private/tmp/fr06-verify-v1.py`
  reversed those exact edits against the saved starting inputs: exit 0, both original
  hashes reproduced. These are session-local verification helpers, not product code.
- `python3 /private/tmp/fr06-check-v2.py`: exit 0. Parsed original/current ticket sections
  and asserted every original Acceptance paragraph remains verbatim; product/authority
  contract remains verbatim. F01–F24 obligation text is unchanged, every row occurs once,
  and owner expansion/refinements preserve rather than substitute obligations.
- That check traversed the dependency graph with FR-22's range expanded: no cycle or
  unknown ticket, and FR-22 reaches every ticket including FR-15a. FR-15a now depends on
  FR-07/08; there is no edge back from those to OMP/PM/provisioning. Host feasibility is
  still a prerequisite, not proven by graph traversal.
- The same check compared saved inputs for preservation, verified root PLAN edits stay
  inside its Foundry entry, resolved changed-document file links/explicit section anchors,
  checked trailing whitespace, and asserted old isolation routing/permanent kernel
  exclusion is absent from the active contract and the re-review gate remains blocked.
- `git diff --check`: exit 0. This checks tracked diffs; direct document checks cover
  new untracked Markdown as well. Two attempted patch applications rejected mismatched
  context before writing; subsequent explicit edits were validated by the checks above.
- Python hashlib manifest generation and reread: every listed v2 SHA-256 matches current
  file bytes. Independent review/audit/storage bytes were rechecked unchanged after edits.

The protocol arguments in [review-response-v2.md](review-response-v2.md) are reasoned
case analyses, **not executable concurrency/security/lifecycle test results**. No new
probe was necessary to assess the specified interleavings. No Foundry/umbrella suite,
audit probes, provider smoke, network isolation test or credential inspection ran.

## Exact independent re-review inputs

[manifest.json](manifest.json) now identifies v2: active contract, revised repair plan,
Foundry/root plan, this verification record, response, unchanged independent review/audit,
original storage script/results, and orientation inputs. It is a flat path→SHA-256 map
using repo-relative paths. It excludes itself; its digest can be recorded separately.
The original proposal's reviewed hashes remain in the immutable v1 review.

Verify the manifest from repository root before reviewing:

```python
import hashlib, json
from pathlib import Path
for path, expected in json.loads(Path("foundry/docs/fr-06/manifest.json").read_text()).items():
    assert hashlib.sha256(Path(path).read_bytes()).hexdigest() == expected, path
```

Read v1 findings, v2 contract, response and ticket refinements together. The root product
contract is unchanged; R1–R5 are addressed proposals awaiting independent disposition.
A new reviewer must decide whether their enforcement/ordering arguments suffice and
identify remaining design blockers separately from deferred implementation acceptance.
Do not replace that verdict with these author's consistency checks. Keep FR-07 blocked.

## Revision 3 correction and checks

Revision 3 changes only the R4 launch-non-start transition, its FR-08/10/11/12 acceptance
traces, Foundry status, manifest and [response v3](review-response-v3.md). R1/R2/R3/R5,
the dependency table, operating contract, storage evidence, audit and independent reviews
were not revised. The active contract now distinguishes pre-intent waiting, proved
non-start and unknown possible start; assigns developer/reviewer/PM/other role outcomes;
and binds retries to a finite infrastructure allowance, R1 predecessor/quiescence and
R5 one-time settlement. No runtime probe was needed because R4a asks for a normative
transition absent from the unimplemented proposed kernel.

Commands and results:

- Initial Python SHA-256 comparison against the v2 manifest: 11 `MATCH`; only the two
  documented plan-status files differed with the exact hashes above. Manifest SHA-256
  matched the v2 review's `428177…075b` record.
- Targeted `sed`, `rg` and reads covered AGENTS/orientation, all of review v2, R1/R4/R5,
  FR-08/10/11/12, response v2, verification and manifest. Combined output truncation was
  followed by focused reads; no audit or production source survey was repeated.
- The prior bounded consistency helper first printed successful preservation, dependency,
  acceptance, link and whitespace checks, then exited 1 because its final assertion
  expected the obsolete literal status `independent re-review pending`. That is a stale
  helper expectation after the v2 review changed the status, not a document defect.
- A first ad hoc preservation check exited 1 because its regular expression accidentally
  double-escaped the Markdown table delimiter. It printed the review-v2 SHA-256 first;
  no file was changed. The corrected check exited 0 and found F01–F24 exactly once,
  historical evidence hashes unchanged, all required R4a clauses/status present and no
  trailing whitespace in changed documents.
- The reusable consistency helper's substantive checks before its stale final assertion
  passed: every original ticket Acceptance paragraph and governing contract retained;
  dependency graph acyclic with FR-22 reaching every ticket; review/audit/storage/source/
  README preserved; root PLAN edits confined to its Foundry entry; local links/anchors
  and whitespace valid.
- `git diff --check` exited 0. Final direct link/anchor, acceptance-text, dependency and
  manifest checks are rerun after the manifest update below.

The refreshed [manifest](manifest.json) is the exact handoff for focused independent
verification. It includes both historical reviews, responses v2/v3, active contract and
plans, this record, storage evidence and orientation inputs; it excludes itself to avoid
self-reference. Verify every entry before reviewing R4a. This author has checked document
consistency and recorded the proposed disposition but has not independently certified it.
