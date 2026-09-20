# FR-19A independent critical review — BLOCKER

Reviewed 2026-09-19, Hawaii. Verdict: **BLOCKER**. The candidate preserves useful
storage and containment behavior, but B1 and B2 below prevent FR-19A acceptance.
No implementation, integration, deployment or ticket-completion change is authorized
by this report. FR-19B remains open.

## Exact identity

- Candidate: `d1ce73ee9da548a64a447106f83d3d7f8ce1b567`.
- Candidate tree: `005ddf2ff0d241a71f4dbfe4d995c72e5983d35f`.
- Implementation: `0391468926bc8f9c1591e8a619d80d6661cf9a5d`.
- Implementation tree: `8db0157cec66fbf140a38853f6259be9d864e4be`.
- Base: `4a9098d8f6d8bcfbe21c0276f14230d888d04038`.
- Branch/worktree: `repair/fr19a-operational-storage`,
  `/Users/raymondluong/dev/pramana-fr19a`.
- [Candidate record](candidate.md) SHA-256:
  `85ad297a5b0f4cb760be54bc9c3ea35e0b58d63a5e2b1adfa95c482c291a0a04`.
- All 12 implementation-manifest hashes independently matched. HEAD/tree and clean
  source were checked again after execution, before adding this report.

Reviewed repository instructions, code conventions, shared repair requirements,
[FR-19A/B acceptance](../REPAIR-PLAN.md#fr-19--bound-storage-and-make-offline-maintenance-safe),
[workflow contract](../WORKFLOW-CONTRACT.md), accepted
[FR-07 v9 evidence](../fr-07/review-v9.md), audit F20/F21, changed source and tests.

## B1 — Default health request times out instead of returning unknown capacity

`Gateway.operational_health/1` uses the default 5,000 ms `GenServer.call` timeout
(`gateway.ex:87`). The capacity probe also defaults to 5,000 ms, and the callback
does SQLite queries before waiting for that probe (`gateway.ex:905–1017`). Thus the
public caller can expire before the owner returns its unknown-capacity result.

Independent reproduction initialized a disposable database and started a gateway
with only `capacity_probe: fn _ -> receive do :never -> :ok end end`; it did not
override the probe deadline. Three consecutive public health calls each exited at
5,001 ms with `{:timeout, {GenServer, :call, [pid, :operational_health, 5000]}}`.
After each caught exit, status remained `:ready`. This is a caller failure, not an
observed authority loss. The gateway's receive also occupies the sole callback
until the diagnostic finishes. The permanent stalled-probe test overrides the
deadline to 10 ms and therefore misses the production-default behavior.

Required correction: make the public deadline and probe lifecycle consistent,
preserve explicit unknown results under the real defaults, and verify ordinary
owner requests remain usable when diagnostic probing stalls. Add a regression
that calls the public API without shortening the production probe deadline.

## B2 — Maintenance failure acceptance remains incomplete

The new process fixture halts only after `wal_checkpoint(TRUNCATE)` has returned
success or after `VACUUM INTO` has completed. Those are useful post-operation,
pre-reply recovery boundaries. They do not exercise interruption while either
engine operation is in progress, checkpoint/backup write or sync error returns,
or a partially produced backup. The suite has no corresponding new maintenance
failure matrix with old claim/ledger rows retained and later effects fenced.

There is also a concrete untested return-path gap. Starting a disposable gateway
with `maintenance_fault: {:error, :after_backup_snapshot}` and calling backup
returns `{:error, {:injected_maintenance, :after_backup_snapshot}}`, while subsequent
status is still `%{mode: :ready, reason: nil}`. `backup_database/3` passes errors
through unchanged (`gateway.ex:1044–1065`); `transition_after_result/2` fences only
typed storage/authority errors (`gateway.ex:875`). SQLite execution errors from
the backup operation likewise reach this unclassified path. Checkpoint errors,
by contrast, are wrapped and fenced. This injected result is evidence of the
classification gap, not evidence of an actual disk or sync failure.

Required correction: distinguish harmless target/preflight refusals from actual
maintenance storage failures, enforce the documented fencing for the latter, and
exercise checkpoint/backup interruption and error-return recovery with complete
prior authority, claims, reservations and ledger evidence checked independently.
Do not substitute a successful operation followed by exit for an in-operation
failure. Keep partial destinations and source evidence available for recovery.

Physical acceptance also remains open under this blocker. FR-19A's scope explicitly
requires physical ENOSPC/sync cases deferred from FR-07; its acceptance requires full
disk, interrupted checkpoint/backup and corrupt SQLite with originals retained and
effects fenced. No operator waiver exists. The instruction to record unsupported
physical guarantees permits honest reporting, not silently treating those required
cases as passed or moving them to FR-19B.

- `max_page_count`: real SQLite logical-full behavior, not filesystem ENOSPC.
- `RLIMIT_FSIZE`: real kernel file-size-limit I/O failure, not filesystem ENOSPC.
- VFS `xSync`: injected `SQLITE_IOERR_FSYNC`, not an observed kernel `fsync(2)` failure.
- Post-operation hard VM exit: deterministic process interruption, not power loss.
- Synced byte corruption: actual damaged SQLite input, not media-failure proof.

Physical filesystem ENOSPC and kernel sync failure were unavailable and unproved.
Power loss, controller/cache flush and media durability are also unproved; this
review demands no destructive host experiment or unlimited hardware guarantee.
Required unavailable conformance remains an acceptance blocker until supplied or
explicitly revised by the governing authority.

## Credited behavior and scope

The recent-event query selects only diagnostic identities/type/sequence, orders by
the integer primary key descending and binds an enforced 1–1,000 row limit. It does
not decode or replace authority replay. No throughput or latency claim follows.
Capacity failures and malformed results retain explicit unknown values; successful
host probing and short-deadline failure handling passed, subject to B1.

Checkpoint runs through the gateway's sole connection and compares complete content
and reconstructed state before/after. Backup retains the accepted full ordered
content/replay comparison and synchronization. Offline verification acquires the
same owner lock, rejects the live source and uses the existing schema/authority
validator. The positive tests retain claim, ledger-generation and reservation
content through backup/checkpoint. Corrupt SQLite is retained and opens in recovery;
backup/checkpoint are refused there. Hard exits require explicit unclean-owner
recovery evidence, and recovered content matches the prior complete baseline.
These positives do not cover the missing B2 failure cases.

Relocation execute/resume/rollback are gated before journal mutation. The original
end-to-end mutation test and 12 generated mutating recovery cases remain present
with explicit FR-19B skips. Planning and the remaining helper coverage still run.
No wholesale deletion of useful relocation history occurred. FR-19B retention,
compaction and cross-device repair/retirement are explicitly uncompleted. No schema,
protected verifier, claim/ledger mutation protocol or provider policy was changed.

## Independently executed verification

Elixir 1.20.3 / OTP 29.0.5 / ERTS 17.0.5 via `mise exec --`. Canonical temporary root:
`/private/tmp/fr19a-review.VBjBF6`. Direct Mix commands used `MIX_ENV=test`,
`MIX_BUILD_PATH=<root>/build`,
`MIX_DEPS_PATH=/Users/raymondluong/dev/pramana/foundry/deps`, `COORDINATOR_TICK=0`,
and unset HERDR/operator/runtime-root overrides. Existing dependency sources were
reused for direct checks; the CI runner separately restored locked Hex dependencies.

| Command / check | Result |
|---|---|
| `mix compile --force --warnings-as-errors` | Exit 0; 107 project files |
| `mix format --check-formatted` | Exit 0 |
| `mix test test/pramana_foundry/durable_store/operational_storage_test.exs test/pramana_foundry/relocation_containment_test.exs --seed 1921` | Exit 0; 10 passed |
| `mix test $(rg --files test \| rg '_test.exs$' \| rg -v 'sync_fault_test.exs$') --seed 1922` | Exit 2; 540/541 passed, 13 skipped; assessor request timing assertion failed |
| `mix test test/pramana_foundry/assessor/jev_test.exs --seed 1922` | Exit 0; 13 passed on isolated rerun |
| `mix test test/pramana_foundry/durable_store/sync_fault_test.exs --seed 1923`, without header override | Exit 139 |
| Same sync command with bundled-header `CPATH` below | Exit 0; 2 passed |
| Complete canonical-temp/bundled-header CI command below | Exit 0; 542 passed, 13 skipped, 1 excluded; compile, format and escript commands passed |
| Manifest comparison and `git diff --check 4a9098d..HEAD` | Exit 0 |

The initial documentation check returned 79/80: the already tracked candidate record
was unreachable from the router. Minimal candidate/review catalog links were added
with this review so the evidence remains discoverable.
The staged-document rerun passed all 80 checks (exit 0); staged diff whitespace
validation also passed.

Full CI command, run from candidate `foundry/` before writing this report:

```sh
env TMPDIR=/private/tmp/fr19a-review.VBjBF6 \
  CPATH=/Users/raymondluong/dev/pramana/foundry/deps/exqlite/c_src \
  mise exec -- elixir ci/run.exs \
  --output /private/tmp/fr19a-review.VBjBF6/ci-artifacts
```

CI source preflight/postflight both identify the exact clean candidate and tree.
Provenance SHA-256:
`836f339dad619347a10a78a8f1c16da4a189e741eb0371b84f0f7e7826398102`.
Generated escript SHA-256:
`67862961c762455759f8653014e64e622c9bc469ad58b12073e14913493b8cc7`.
The provenance's `format_debt` field says `format-debt baseline changed` despite
the formatter command and runner exiting 0; that metadata inconsistency is not
silently treated as verified debt accounting. The runner is unchanged by FR-19A.
The one excluded test is optional Python/tiktoken recomputation, not storage.

The sync crash has an environment explanation. `compile_extension!/1` hardcodes
`deps/exqlite/c_src` relative to the checkout, ignoring external `MIX_DEPS_PATH`.
This candidate checkout lacks that directory, so the compiler falls back to the
macOS SDK SQLite 3.54.0 header instead of Exqlite's 3.53.4 header. Setting `CPATH`
to the bundled headers makes the same unchanged candidate pass. An additional
FR-07 worktree control at `50e99c98a72ad9362b2d7d61507745d9c8c80cda` passed 2/2
with a fresh separate build. This supports a fixture/header-selection defect,
not a candidate storage regression. The earlier CI failure under symlinked
`/var/folders` is likewise avoided by canonical `TMPDIR`; no path protection
was weakened. `CPATH` is an additional input recorded here because the runner's
provenance does not capture it.

## Handoff

Fix and independently re-review B1/B2 against a newly frozen candidate. Preserve
the successful evidence and the unavailable physical acceptance explicitly.
This review changed its own report and the two required catalog links; no implementation was repaired, no
candidate integrated or pushed, and no daemon/provider/deployment was operated.
