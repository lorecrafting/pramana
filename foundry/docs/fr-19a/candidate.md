# FR-19A operational storage correction candidate

Recorded 2026-09-19, Hawaii. This is a frozen candidate for independent critical
rereview, not an acceptance verdict, integration authorization, deployment or activation.

## Immutable identity and scope

- Candidate implementation revision: `3852f0566ccf5a09f2f5eaf110df1f2d5643f886`.
- Candidate implementation tree: `2ef98a6a43d6b34a9bf98f826a372b726fb2237d`.
- Original implementation base: `4a9098d8f6d8bcfbe21c0276f14230d888d04038`.
- Branch: `repair/fr19a-correction`.
- Linux kernel-fault evidence revision: `5f4984be07c67de8515a26d953d4d5b7de907c05`,
  tree `7f6b91e6815bc19b4110e697c1d9fc6d7361ad85`.
- The only change between the kernel-fault evidence revision and this implementation
  revision is the deterministic maintenance-interruption regression in
  `operational_storage_test.exs`; production and Linux fault-harness files are identical.

This candidate owns FR-19A only. FR-19B relocation/retention work, FR-08 protected
primitives, provider execution, daemon rollout and activation remain out of scope.

## B1 and B2 corrections

The default operational-health request now has a caller deadline beyond the owned
five-second capacity-probe deadline. The probe is an individually monitored worker; probe
result, timeout, worker exit, caller exit and Gateway termination all remove its request
and terminate owned work. A production-default stalled-probe regression receives explicit
unknown/degraded capacity while ordinary owner requests remain responsive.

Maintenance classifies harmless target/preflight refusal separately from storage failure.
Checkpoint and backup engine interruption and sync/write failures enter recovery, fence
later protected effects and retain the complete prior commands, events, projections,
effects, claims, ledger generations and reservations. The in-operation interruption test
handshakes its interrupter and uses four separately committed 4 MB protected commands so
the real checkpoint and `VACUUM INTO` remain active past the first interrupt without
exceeding the public transaction deadline. Partial destinations and original authority
remain available for inspection and recovery.

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
| Operational storage, bundled-header sync fault, relocation containment and Linux harness regressions, seed 19207 | Exit 0; 24 passed |
| Complete model-free `ci/run.exs` at exact clean candidate implementation | Exit 0; 554 passed, 13 skipped, 1 excluded |
| Linux physical kernel-sync workflow | Run `35498430877`; all steps and cleanup passed |

Full CI used `/private/tmp/fr19a-candidate-ci.xDwWk8`. Provenance SHA-256 is
`b106bc4f584e432434272c3cb85fc0558aba1fe279966165319e9cc65bbc0fbc`; generated
escript SHA-256 is
`4b38c5de82f0e5baa5fd18d623a00e3d4c52cc5b80393768ee3fbbb4b3f86684`.
Preflight and postflight both identify the exact candidate implementation revision/tree
with a clean source. The sole exclusion is optional Python/tiktoken recomputation.

One initial full-CI command correctly refused ambient Homebrew ERTS 17.0.6. A later
absolute-path invocation is the counted pass. Focused seed 19199 exposed that the original
one-millisecond interrupter could lose a race to a fast backup; oversized single-command
diagnostics then hit the unrelated public transaction deadline. Neither is counted as a
pass. The committed four-command handshake correction passed the isolated matrix, focused
24-test run and complete model-free runner.

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
da3f2a67febc36cee7d23d5312821d5f23e38a8510d7c5fd4624bc0931822c7d  foundry/lib/pramana_foundry/durable_store/gateway.ex
eb4a5c8efb13a2da1f730730572f11059bf029b75a755a040673a6c259ac42bc  foundry/lib/pramana_foundry/durable_store/maintenance.ex
b6eccbbc7268f942212145c314e95612d3b7e1ca3a7ed00bea482e33feb99e9c  foundry/test/fr19a_sync_eio_orchestration_test.exs
46767edaad9cf17b7eb8624f46250883381db9f3ffa4c1435ded12a5a07e6012  foundry/test/fr19a_sync_eio_workflow_test.exs
e4a84a98739438197ccbd86a2d8e5f9ea5d5ac30e9c6f9e8148199079ce029e5  foundry/test/pramana_foundry/durable_store/operational_storage_test.exs
ec3a680c2aa8ca4a76f9bd45c7fef94d28271a247455fc9510fe666cbfbd6ba3  foundry/test/support/fr19a_linux_sync_eio_fixture.exs
1fe6c8b11015b0317333f27bcaf5c9e8b726a11a1c864bcb20b0f1495ca4f8a7  foundry/test/support/fr19a_maintenance_crash_fixture.exs
160ad28e89e51f6b2216ee2866f851a0e4bae962ca13c26182394085c73a9f04  foundry/docs/fr-19a/linux-sync-eio-plan.md
```

Independent Astra-high critical rereview must inspect the exact candidate, artifact and
limitations before any integration. No provider, credential, live daemon, deployment,
activation or shared repair status was changed.
