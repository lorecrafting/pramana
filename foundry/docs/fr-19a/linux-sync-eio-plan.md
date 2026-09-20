# FR-19A Linux physical kernel-sync fault acceptance plan

Recorded 2026-09-19, Hawaii. This is a branch-only execution plan, not acceptance
evidence. It does not change the blocked disposition in
[correction-checkpoint.md](correction-checkpoint.md). The workflow must run against its
exact committed revision and produce the required uploaded proof before the kernel-sync
obligation can be reconsidered.

Run `35495623228` at revision `6b75fa3e8954bf32f8bfeee60af2d3f82466cf8c`
was diagnostic only and is not acceptance evidence. Its uploaded artifact
`10600049347` proved the disposable loop, device-mapper `error` target, ext4 mount
and exact cleanup were available, but the raw probe exited 127 before a capability
verdict because the elevated Elixir wrapper could not resolve `erl`. The runner also
inherited shell errexit before recording the intended unavailable result. The corrected
probe therefore validates both setup-beam executable paths, passes a fixed runtime
`PATH` explicitly across sudo, and captures the capability command status inside a
conditional before the separate refusal step owns any failure.

Run `35495816592` at revision `d7031a34c4a7ed4ef2c3e040362e3c71a9c052be`
and artifact `10600459221` were also diagnostic only. The raw probe reached the exact
suspended mapper, then deadlocked by waiting synchronously for a `pwrite` that the
suspension itself prevented from completing; the run was cancelled and exact cleanup
succeeded. Both probes now start the `pwrite` in a tracked helper, establish that it is
pending, load the error table and resume before awaiting its bounded outcome. Cleanup
restores the mapper before bounded helper termination.

Run `35496300361` at revision `5d9464ea3f706e69f873498c22ddb143b2c00e05`
and artifact `10600621573` were diagnostic only. The asynchronous raw helper attempted
to use a descriptor opened by its parent and failed with `:not_on_controlling_process`;
the attempted error-table resume also returned EIO before the raw sync proof. Exact
cleanup still removed the mount, mapper and loop. The tracked helper now opens, pre-reads
and writes its own descriptor. Mapper recovery detects an already suspended map and
loads the recorded linear table before resuming; an active map is suspended with
`--noflush --nolockfs` first.

Run `35496921076` at revision `5a724b3f1c5f382e269ca4127ebf2d0778e15bb2`
and artifact `10600856081` corrected an over-narrow assumption in this branch plan. The
controlled device-mapper block fault became live, ext4 entered `emergency_ro`, the helper
write completed, and the already-open exact-path `fsync` returned kernel `EROFS`. The
authoritative FR-19A obligation is an attributable physical/kernel sync failure, not one
particular errno. This plan therefore accepts `EIO` or provenance-checked `EROFS`; this is
not a waiver and the result is never relabeled as `EIO`.

Run `35498046373` and artifact `10600583609` at revision
`97aabf406aecceba32b910221056748b24e67bc3`
proved the unchanged Gateway path returned a typed storage failure after an exact-path
`fsync` returned kernel `EIO`; recovery mode and a later protected-operation refusal also
passed. It was diagnostic rather than acceptance evidence because offline verification
was attempted while ext4 remained in `emergency_ro`, and the detached loop's
machine-readable unbound row was conservatively classified as unavailable. The corrected
sequence closes all owned descriptors, stops the Gateway, performs an ordinary unmount
and fresh mount of the same revalidated mapper, and only then verifies retained content.
It separately classifies an exact unbound loop row as absent ownership rather than a
foreign or unavailable binding.

## Boundary

The branch-only [workflow](../../../.github/workflows/fr19a-sync-eio.yml) uses an ephemeral
GitHub-hosted Ubuntu runner and `contents: read` permission. It performs no provider call,
Foundry dispatch, live-daemon operation, deployment or activation. It does not install
packages. The first stage inventories the preinstalled commands, noninteractive sudo,
`/dev/mapper/control` and the device-mapper `error` target, then requires a raw physical
sync-fault control. The Gateway stage is skipped unless every capability and the raw
control pass.

Every block resource is created beneath a unique `$RUNNER_TEMP` state directory:

1. a bounded 128 MiB sparse image;
2. one `losetup --sizelimit` loop device;
3. one uniquely named device-mapper linear table over exactly that loop;
4. one ext4 filesystem mounted at an exact owned mountpoint with
   `nodev,nosuid,noexec`.

The source database, verified baseline and recovered-source backup stay on the runner's
normal filesystem. Only the candidate backup destination is on the disposable ext4 mount.
The scripts validate the exact state-directory, image, mount, mapper name, loop identity,
sector count and observed linear table before any suspend, table replacement, restore or
cleanup operation. They never name a host root disk or use a wildcard destructive target.

## Required syscall proof

The raw capability probe and the actual Gateway fixture both:

1. open and pre-read a block from the target while the linear mapping is healthy;
2. suspend only the exact mapper;
3. start a `pwrite` of the identical cached bytes through a second valid descriptor in a
   tracked helper, and establish that it is pending rather than wait on the suspended
   device;
4. load `0 <exact-sectors> error`, resume the mapper and collect the bounded helper
   outcome;
5. invoke a real sync on an already valid descriptor. A helper-only `pwrite` EIO does not
   satisfy this obligation.

For the Gateway case, steps 1–4 run through the existing
`maintenance_fault: {:during, :during_backup_sync, fun}` seam after the verified backup is
open. Production `Gateway.sync_file/2` then calls unchanged `:file.sync`. The BEAM runs
under timestamped `strace -ff -yy` restricted to file open/write/sync/close syscalls. The
parser accepts only `fsync` or `fdatasync` on the decoded exact backup path returning
kernel `EIO`, or `EROFS` when the same evidence proves the controlled exact error table
was live and ext4 entered `emergency_ro`. An arbitrary read-only mount, unrelated `EROFS`,
`EBADF`, a failure only on `write`/`pwrite64`, an injected callback error or an unrelated
descriptor is failure, not sync acceptance. The matching descriptor must have opened the
destination before the fault phases.

The fixture also requires the public backup result to carry the same typed reason in
`{:storage_unavailable, {:backup_failed, reason}}`, gateway recovery mode, refusal of a
later protected effect, complete prior commands/events/projections/effects/claims/ledger
generations/reservations, unchanged source baseline, and retained content-verifiable
destination after restoring the exact linear table, closing the exercised descriptor and
Gateway, and ordinarily unmounting and freshly mounting the same owned filesystem. The
fresh mount must be writable and must no longer report `emergency_ro`; no fsck, mkfs,
replacement, forced/lazy unmount or other repair is permitted. The pre-unmount destination
digest must equal the post-remount and post-verification digest. This proves retained
content recovery after restoration and orderly remount, not failed-sync persistence,
power-loss survival or media durability.

## Cleanup and evidence

The raw probe has an EXIT trap. The workflow also has an `if: always()` cleanup step for
both raw and Gateway state. Cleanup restores the recorded linear table, unmounts only the
exact mount, removes only the exact mapper with retry, detaches only the loop still bound
to the exact image, and fails if any exact resource remains. Ephemeral runner teardown is
the final containment layer, not the primary cleanup mechanism.

The always-uploaded, 14-day bounded artifact contains:

- revision/tree/ref and SHA-256 values for the workflow and fixtures;
- capability inventory and device-mapper targets;
- exact setup identities, table/status and `findmnt` output;
- raw and Gateway fixture logs plus restricted strace files;
- parsed exact-path kernel-sync-fault proof and content digests;
- individual probe/restore/parser exit codes and cleanup results.

It intentionally excludes the environment, secrets, credentials and `dmesg`. A missing
capability produces an honest unavailable artifact. A green workflow is still only a
candidate evidence input: independent review must bind the exact revision, inspect the
artifact and decide whether the unwaived FR-19A sync obligation is satisfied.

This acceptance proves the exercised Gateway backup `:file.sync` failure, fencing and
retained content recovery after restoration and orderly remount only. It does not prove
failed-sync persistence, SQLite `xSync`, WAL durability, power-loss survival,
controller/cache flush or media durability.
