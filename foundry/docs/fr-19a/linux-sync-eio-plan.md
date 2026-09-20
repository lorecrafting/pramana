# FR-19A Linux kernel-sync EIO acceptance plan

Recorded 2026-09-19, Hawaii. This is a branch-only execution plan, not acceptance
evidence. It does not change the blocked disposition in
[correction-checkpoint.md](correction-checkpoint.md). The workflow must run against its
exact committed revision and produce the required uploaded proof before the kernel-sync
obligation can be reconsidered.

## Boundary

The branch-only [workflow](../../../.github/workflows/fr19a-sync-eio.yml) uses an ephemeral
GitHub-hosted Ubuntu runner and `contents: read` permission. It performs no provider call,
Foundry dispatch, live-daemon operation, deployment or activation. It does not install
packages. The first stage inventories the preinstalled commands, noninteractive sudo,
`/dev/mapper/control` and the device-mapper `error` target, then requires a raw sync-EIO
control. The Gateway stage is skipped unless every capability and the raw control pass.

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
3. `pwrite` the identical cached bytes through a second valid descriptor, leaving logical
   content unchanged while making the inode dirty;
4. load `0 <exact-sectors> error` and resume the mapper;
5. invoke a real sync on an already valid descriptor.

For the Gateway case, steps 1–4 run through the existing
`maintenance_fault: {:during, :during_backup_sync, fun}` seam after the verified backup is
open. Production `Gateway.sync_file/2` then calls unchanged `:file.sync`. The BEAM runs
under `strace -ff -yy` restricted to file open/write/sync/close syscalls. The parser accepts
only `fsync` or `fdatasync` on the decoded exact backup path returning `-1 EIO`. `EBADF`,
an EIO only on `write`/`pwrite64`, an injected callback error or an unrelated descriptor is
failure, not sync acceptance.

The fixture also requires the public backup result to be typed
`{:storage_unavailable, {:backup_failed, :eio}}`, gateway recovery mode, refusal of a later
protected effect, complete prior commands/events/projections/effects/claims/ledger
generations/reservations, unchanged source baseline, and retained content-verifiable
destination after restoring the exact linear table.

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
- parsed exact-path sync-EIO proof and content digests;
- individual probe/restore/parser exit codes and cleanup results.

It intentionally excludes the environment, secrets, credentials and `dmesg`. A missing
capability produces an honest unavailable artifact. A green workflow is still only a
candidate evidence input: independent review must bind the exact revision, inspect the
artifact and decide whether the unwaived FR-19A sync obligation is satisfied.
