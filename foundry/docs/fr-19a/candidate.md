# FR-19A operational storage correction candidate

Recorded 2026-09-19, Hawaii. This is a frozen candidate for independent critical
rereview, not an acceptance verdict, integration authorization, deployment or activation.

## Immutable identity and scope

- Candidate implementation revision: `6c1e5acb29b10e0cd40c692de87f05f1155804c8`.
- Candidate implementation tree: `0392ee329922c63a5b3f97bf441dc52719f19c6f`.
- Original implementation base: `4a9098d8f6d8bcfbe21c0276f14230d888d04038`.
- Branch: `repair/fr19a-correction`.
- The prior correction candidate `ad455a8137b9cafbbec1670a3f683aa9364d5789`
  and Astra-high BLOCKER rereview `7ce0c65c0a4f72ec146abdbb26d8f0381f5e96d4`
  are superseded only by the B1/B2 correction recorded here.
- Linux kernel-fault evidence revision: `5f4984be07c67de8515a26d953d4d5b7de907c05`,
  tree `7f6b91e6815bc19b4110e697c1d9fc6d7361ad85`.
- The Linux workflow, host helpers, parser, fixture, backup sync implementation and
  attributed `:during_backup_sync` seam are unchanged. This correction changes the
  health worker lifecycle and wraps only the checkpoint SQL and `VACUUM INTO` calls in
  an operation-scoped test-fault finalizer. The credited run is not relabelled as an
  execution of this later revision; independent rereview must confirm that its narrow
  sync-path evidence remains applicable.

This candidate owns FR-19A only. FR-19B relocation/retention work, FR-08 protected
primitives, provider execution, daemon rollout and activation remain out of scope.

## B1 and B2 corrections

The default operational-health request waits beyond the owned five-second capacity-probe
deadline. Each request now has an independent controller that monitors the Gateway, owns
its own timer, and owns and joins the actual probe. Probe result, timeout, worker exit,
caller exit, ordinary termination and untrappable Gateway death all terminate owned work.
The probe receives no authority connection or protected capability, and a unique request
token makes a stale result inert. The permanent owner-kill regression observes the caller,
probe and controller all terminate within one second, then performs an explicitly evidenced
restart and successful health request. The existing production-default stalled-probe test
continues to prove explicit unknown capacity while ordinary owner requests remain responsive.

Maintenance classifies harmless target/preflight refusal separately from storage failure.
Checkpoint and backup engine interruption and sync/write failures enter recovery, fence
later protected effects and retain the complete prior commands, events, projections,
effects, claims, ledger generations and reservations. The interruption regression disables
automatic WAL checkpointing on the real Gateway connection, commits four separately
protected 4 MB commands, and derives the exact WAL frame count from the observed WAL size,
32-byte header, live SQLite page size and 24-byte frame headers. It requires positive,
integral frames immediately before `PRAGMA wal_checkpoint(TRUNCATE)`.

The test-only fault finalizer now surrounds only the unchanged checkpoint SQL or
`VACUUM INTO` call. It captures that exact call's result, stops and joins the phase-scoped
interrupter, and only then permits later verification. Both cases require the captured
operation result itself to contain `interrupt`; a successful `{:ok, [[0, 0, 0]]}` checkpoint
or an interruption of a later `Authority.read/2` therefore fails the regression. The
checkpoint case also requires the original database inode and nonempty WAL inode to remain;
both cases prove recovery fencing, baseline immutability, partial-target retention when one
exists, complete recovered authority and offline replay verification. The interrupter
monitors its Gateway, and exceptional operation cleanup invokes its finalizer before reraising.

## Physical filesystem ENOSPC

Darwin acceptance uses only disposable owned HFS+ images and fills them until Erlang
receives real operating-system `:enospc`. Backup then returns SQLite `database or disk is
full`, enters recovery, retains any partial target, and preserves byte-stable source and
baseline authority. Checkpoint runs with a real nonempty WAL on the owned full filesystem,
returns the same physical-full failure, retains the database and WAL, and after removing
only the owned filler produces a verified backup with the complete prior authority.

This is physical filesystem ENOSPC. It does not relabel `max_page_count`, `RLIMIT_FSIZE`
or an injected VFS error as ENOSPC.

## Physical kernel sync evidence

GitHub Actions run `35498430877`, artifact `10601228576`, executed the branch-restricted
workflow with `contents: read` on the exact Linux evidence revision/tree above.

- The raw control produced `fsync(...raw-sync.bin) = -1 EIO` with the exact disposable
  device-mapper `error` table live.
- The real unchanged Gateway backup path opened descriptor 25 before the fault and
  produced `fsync(25</.../backup.sqlite3>) = -1 EIO`; that descriptor then closed
  successfully.
- The public result was `{:error, {:storage_unavailable, {:backup_failed, :eio}}}`. The
  Gateway entered recovery and refused a later protected operation.
- The exact linear map was restored. After the dirty helper joined and the Gateway
  stopped, an ordinary unmount and fresh mount of the same revalidated ext4 mapper cleared
  `emergency_ro` without fsck, mkfs, replacement, forced or lazy unmount.
- The retained destination was 188,416 bytes. Its pre-remount, post-remount and
  post-verification SHA-256 remained
  `ccb2b4d029ac200f013abb2ea07ad949484bcadcb645bd8938116a538760b852`, matching the
  baseline. Full content and replay matched, including claims, ledger generations and
  reservations; the unaffected source produced a separately verified recovered backup.
- Both raw and Gateway mounts, mappers and exact owned loops were removed. The independent
  cleanup result was `exact_resources_remaining=false` and workflow cleanup exited zero.

The uploaded parsed proof explicitly claims only real Gateway kernel sync failure,
fencing, and retained-content recovery after restoration and orderly remount. It does not
claim failed-sync persistence, SQLite `xSync`, WAL durability, power-loss survival,
controller/cache flush or media durability.

## Executed verification

Pinned Elixir 1.20.3, OTP 29.0.5 and ERTS 17.0.5 were selected by absolute paths;
canonical temporary roots and Exqlite bundled headers were used.

| Check | Result |
|---|---|
| Host identity/error-table shell regressions | Exit 0 |
| Workflow/orchestration focused tests | Exit 0; 5 passed |
| Operational storage file including Darwin physical cases, seed 19231 | Exit 0; 16 passed |
| Operational storage, bundled-header sync fault, relocation containment and Linux harness regressions, seed 19233 | Exit 0; 25 passed |
| Complete model-free `ci/run.exs` at exact clean candidate implementation | Exit 0; 555 passed, 13 skipped, 1 excluded |
| Linux physical kernel-sync workflow | Run `35498430877`; all steps and cleanup passed |

Full CI used `/private/tmp/fr19a-final-ci2.8H8oFe`. Provenance SHA-256 is
`c9b03cc1804a706ae82515f23e6aeb0c0e5602b35fb47eb4a464e66de2f86ff6`; generated
escript SHA-256 is
`e76c695efeaef36e294fb5dd49d84ddaa6f133a0d2305596c480b6405e628972`.
Preflight and postflight both identify the exact candidate implementation revision/tree
with a clean source. The sole exclusion is optional Python/tiktoken recomputation.

The first clean run of this correction exposed a real test-timing condition: after the
untrappable owner death and process `DOWN`, release of the dead process's SQLite NIF lock
can finish slightly later. It returned 554/555 with only the immediate restart assertion
failing. The permanent regression now retries only that exact transient locked status for
at most two seconds, rejects every other recovery reason, and still requires a ready,
usable restart. That failed run is not counted as a pass. The second clean run on the exact
revision/tree above is the counted pass.

## Implementation manifest

The candidate record itself and historical review/checkpoint reports are excluded.

```text
509d5cc6fd05b8010f3dfc984ae74ef89212961e4d1305cf5ce27d8565e0a7be  .github/workflows/fr19a-sync-eio.yml
6b52a7bfc5eb6eedcf6b7a66e59c3d886c7ff95067f66775bd925414ce2235a5  foundry/ci/fr19a_raw_sync_eio.exs
73df7def305e669b0daebfb99ce6cb61656d8e2c68cc6fec2d5948d93f3292ff  foundry/ci/fr19a_sync_eio_host.sh
fd7ded768160a29015cc98b87d829335665b78262406feaee926b52e89a99646  foundry/ci/fr19a_sync_eio_host_test.sh
c0bda610f10121c4cc9593be6894212557fbed67f864690b1529a8d7c8e5e94b  foundry/ci/fr19a_sync_eio_orchestration.exs
34cfbdbb1ac27215555bf8b64bdb022cdf89e74df8bbdd41f5dd63fcd0518524  foundry/ci/fr19a_sync_eio_parse.exs
6017979eb873e6bb6de287bd67ac201b4c440f3decfd710aacde2721c98b20e3  foundry/lib/pramana_foundry/durable_store/capacity.ex
b92ce0e674b4cf51710322cf1809ceac658c313222ec4b7ba84ee9d7c49450b9  foundry/lib/pramana_foundry/durable_store/gateway.ex
eb4a5c8efb13a2da1f730730572f11059bf029b75a755a040673a6c259ac42bc  foundry/lib/pramana_foundry/durable_store/maintenance.ex
b6eccbbc7268f942212145c314e95612d3b7e1ca3a7ed00bea482e33feb99e9c  foundry/test/fr19a_sync_eio_orchestration_test.exs
46767edaad9cf17b7eb8624f46250883381db9f3ffa4c1435ded12a5a07e6012  foundry/test/fr19a_sync_eio_workflow_test.exs
3cfafc1b7f2e86c9b528175ecdfa065296e93178bfe4c1b7ff998f7fb8965427  foundry/test/pramana_foundry/durable_store/operational_storage_test.exs
ec3a680c2aa8ca4a76f9bd45c7fef94d28271a247455fc9510fe666cbfbd6ba3  foundry/test/support/fr19a_linux_sync_eio_fixture.exs
1fe6c8b11015b0317333f27bcaf5c9e8b726a11a1c864bcb20b0f1495ca4f8a7  foundry/test/support/fr19a_maintenance_crash_fixture.exs
160ad28e89e51f6b2216ee2866f851a0e4bae962ca13c26182394085c73a9f04  foundry/docs/fr-19a/linux-sync-eio-plan.md
```

Independent Astra-medium focused critical rereview must inspect the exact candidate,
operation-local B1/B2 evidence, preserved physical artifact and limitations before any
integration. No provider, credential, live daemon, deployment, activation or shared repair
status was changed.
