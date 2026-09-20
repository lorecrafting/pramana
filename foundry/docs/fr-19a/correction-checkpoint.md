# FR-19A blocker correction checkpoint — kernel sync acceptance unavailable

Recorded 2026-09-19, Hawaii. This is a durable **blocked checkpoint**, not a frozen
candidate, review request, acceptance verdict or integration authorization. B1, B2 and
physical filesystem ENOSPC now have executable evidence. The required actual kernel sync
failure remains unavailable on this host and has no waiver, so FR-19A candidacy remains
blocked.

## Exact checkpoint

- Revision: `ba63c8c5bb17baf7d28e6af5b753cf3498178b14`.
- Tree: `375d83d8c4eaa23411a7b75d8155c8ac581763b0`.
- Branch: `repair/fr19a-correction`.
- Corrected gateway SHA-256:
  `da3f2a67febc36cee7d23d5312821d5f23e38a8510d7c5fd4624bc0931822c7d`.
- Operational-storage test SHA-256:
  `4f4983ac68e392e76e1f4ce675e0f746e5ab2bbb3847051a7bcc838872ff0ed3`.
- Base blocker review: [review.md](review.md). The rejected candidate and credited behavior
  remain preserved in [candidate.md](candidate.md).

The source correction makes the capacity probe one gateway-monitored worker with an
owner timer and caller monitor. The public health call can wait for the internal five-second
bound while unrelated gateway calls continue. Result, timeout, worker death, caller death
and gateway termination all remove the request and cancel or kill its owned worker. There
is no nested orphan probe.

Maintenance now wraps post-preflight backup failures as storage failures, fences them,
closes file and directory descriptors on every sync result, and preserves harmless target
refusals as non-fencing preflight errors. Engine-level `sqlite3_interrupt()` regressions hit
checkpoint and `VACUUM INTO` while those operations execute. Both return typed storage
failure, fence later effects, preserve any produced destination, and reopen with the exact
prior commands, events, projections, effects, claims, ledger generations and reservations.

## Physical ENOSPC evidence

The permanent Darwin cases create and attach only an owned HFS+ disk image at an explicit
temporary mountpoint. They write an owned filler until Erlang receives the real operating-
system `:enospc`; no SQLite page limit, process file limit or injected VFS is involved.

- Backup: a 12 MiB image is filled, then only 512 KiB is released beneath a source carrying
  a 4,000,000-byte protected command payload. Real `VACUUM INTO` returns SQLite
  `database or disk is full`; the gateway enters recovery, the source and baseline stay
  byte-stable, and any partial target is retained unchanged.
- Checkpoint: the source database lives on a separate owned 20 MiB image. A protected
  2,000,000-byte payload leaves a real WAL, the filesystem is filled until `:enospc`, and
  real `PRAGMA wal_checkpoint(TRUNCATE)` returns `database or disk is full`. The database
  and nonempty WAL remain. After removing only the owned filler, the reopened source and a
  new verified backup match the complete prior authority.

An additional independent 64 MiB HFS+ probe against this source checkpoint reproduced
real ENOSPC for both backup and checkpoint. Its raw SQLite control also reported OS errno
28 and recovered with `quick_check` after its owned filler was removed. That probe detached
its images and moved its temporary root to Trash; it made no repository change.

## Exact remaining blocker: actual kernel sync failure

No safe unprivileged mechanism available on this macOS host can make an otherwise valid
regular-file `fsync(2)` or `F_FULLFSYNC` reach a kernel/device durability failure:

- HFS+ and APFS disk-image exhaustion produced real errno 28 on writes, but sync and full
  sync of already dirty files succeeded.
- Force-detaching an owned HFS+ image normally flushes it cleanly. One Erlang descriptor
  path returned `EBADF` after detach; that is descriptor invalidation, not evidence that a
  valid kernel sync reached and reported a storage failure. The permanent test labels this
  only as a negative control and does not count it as sync acceptance.
- Truncating the attached image backing file was repaired by the image stack; subsequent
  sync and full sync still succeeded.
- macOS supplies no `/dev/full`, Linux `dm-flakey`/`dm-error`, or comparable safe
  unprivileged block-fault target here. Damaging a real host filesystem or controller is
  outside the authorized safe boundary.

Injected SQLite VFS `xSync`, `RLIMIT_FSIZE`, logical `max_page_count`, post-success process
exit and the negative detach control remain narrower evidence and are not substitutes.
Required kernel-sync acceptance is therefore **unproved and unwaived**. Do not freeze,
review as complete, integrate or mark FR-19A accepted until a safe real fault target is
provided or the governing acceptance authority explicitly changes the obligation.

## Executed verification

Elixir 1.20.3, OTP 29.0.5 and ERTS 17.0.5 were selected by absolute pinned tool paths;
Exqlite native fixtures used the bundled headers through `CPATH`.

| Check | Result |
|---|---|
| Format and warnings-as-errors compile | Exit 0; 107 project files |
| Operational-storage suite, seed 19197 | Exit 0; 15 passed |
| Operational storage + bundled-header sync fault + relocation containment, seed 19196 | Exit 0; 18 passed |
| Complete model-free `ci/run.exs` | Exit 0; 549 passed, 13 skipped, 1 excluded |

The first broader focused invocation omitted canonical `TMPDIR` and failed only the two
known path-symlink-sensitive native sync tests; the exact rerun with `TMPDIR=/private/tmp`
passed 18/18. An initial CI invocation used the Homebrew OTP earlier on `PATH` and stopped
at the toolchain preflight; it is not counted as a pass. The pinned rerun used
`/private/tmp/fr19a-correction-ci2.nhlEhA`, wrote provenance SHA-256
`954b6747e0fc46d2645c0960f77df16ad69a8ed973ac6cc2664d5085e640251d`, and generated
escript SHA-256
`ce29bb38d1d6be4511358a45721f5ef48251cd925e923302e67b62f74f330233`.

No provider, credential, live daemon, deployment, activation, shared repair plan or ticket
status was changed.
