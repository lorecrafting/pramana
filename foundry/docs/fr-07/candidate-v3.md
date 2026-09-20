# FR-07 corrected candidate v3

Frozen 2026-09-13 for renewed independent review. The rejected v1/v2 candidates and both
independent FAIL records remain immutable history.

## Identity and evidence

- Base: `8aa0ebddbfb5fa834bbefa53d1f84b992e4c25bd`.
- Rejected v2: `b88918dd54094e657f8c6aae839878327c75e4d6`.
- Corrected implementation: `5f3af472a3c59f2ad3dcbaae6d448145869ba9ca`.
- Implementation tree: `d7e6f4e40b64ce2f972b852414e865807af1cbf6`.
- Worktree/branch: `/private/tmp/pramana-fr07-replay2`, `repair/fr07`.
- Pinned Elixir 1.20.3 / OTP 29.0.5; `exqlite == 0.40.0` and native in-process SQLite.
- `MIX_ENV=test mix compile --force --warnings-as-errors`: 85 files, exit 0.
- Focused storage/containment/checkpoint suite, seed 7726: 49 passed, exit 0.
- Fresh full suite, seed 7726, `TMPDIR=/tmp/fr07-v3-full.Qk57BZ` with build beneath
  that fresh root: 458 passed, exit 0.
- Exact changed-path formatter check and `git diff --check`: exit 0.

`review-response-v2.md` maps each renewed finding to code and executable regressions.
Admission/reopen/read shape equivalence, corruption fencing on ordinary and protected
idempotent retries, durable stale rejection replay, child-ledger refusal, symlink/hardlink
ownership exclusion, ordered create/update projection reconstruction, same-count semantic
corruption detection, prior protected history at every insertion/hard-crash boundary, and
complete content comparison around the real SQLite COMMIT I/O failure all pass.

The specifically attributed failed-fsync syscall remains unavailable and **unpassed**:
Exqlite 0.40.0 exposes no controlled VFS/test hook on this host. Actual FULL, read-only and
`RLIMIT_FSIZE` COMMIT/write failures are not relabeled as fsync evidence. FR-08/15a/17/19/22
scope remains downstream; nothing here is deployed or activated.

## Implementation manifest

These 25 hashes cover every base-to-implementation changed path. This candidate file is
outside its own self-contained manifest.

```text
33136e5c3c25e92976762c3a581380d24d3ca2771162557d9d42bb0d4cc74c83  foundry/README.md
5b7e8df367a9134b29fa494928cd583f80591eea5582d1bc6e70e07863ca3cd4  foundry/docs/DURABLE-STORE.md
5dc0c7bbe8bcf21943b03b27aec092116e602ea515c319a54d7b29b995d26b9a  foundry/docs/fr-07/candidate-v2.md
79a5ded644517b294a67e3e3e7a214b97f3ee518d448b8e39929e846e794b4e9  foundry/docs/fr-07/candidate.md
9e0e2be78603b2069961d8b363cd50715a0d58d53f48910ceaa8790f8ac92556  foundry/docs/fr-07/review-response-v2.md
d089de9abaca36e65674218844634944cf33a082734666a8a343ce06cbb65f39  foundry/docs/fr-07/review-response.md
4dab766e7616e40630d2000499319f37ee8216851f5a73f25cf74f6a2c9e8ad4  foundry/docs/fr-07/review-v2.md
bba396dd837ad06018c460a4dd68223792d536542b7fbdb53cfaea2092597f30  foundry/docs/fr-07/review.md
ebbf593cfb9acb975ff37ae12affcea5f9dae1896b2f4b679f56f83f85733182  foundry/lib/pramana_foundry/durable_store/compatibility_writer.ex
33ebf4bed851ed2075053c3be175034385f4ce48b9cfb202a7fb3e7e48198686  foundry/lib/pramana_foundry/durable_store/database.ex
140730a723527d3e7c9f71f0e54c209f14ce4a8b74004e553f12f14ce7c987ba  foundry/lib/pramana_foundry/durable_store/encoding.ex
4262d0598d05d8e1f212cb626b55868628a06c6e37022293108a2f0ebd8bd50f  foundry/lib/pramana_foundry/durable_store/gateway.ex
800e8bd004c101eb9ab6f47adda0cbdb22c5d35def9c154afc5f44a296f1305a  foundry/lib/pramana_foundry/durable_store/kernel.ex
a4c06b0e94f343b66aba5ede2ae97b533756c00a11a3aa027dd6cdcd1eee52e1  foundry/lib/pramana_foundry/durable_store/legacy_import.ex
a6072c38c080cc82bdbd3484440b8d9ce036f5b75711f374901056ca99563216  foundry/lib/pramana_foundry/durable_store/owner.ex
d515c960069beae97e8e67a946fa4e360d87957680ffd12e0a7cd71a692daaf1  foundry/lib/pramana_foundry/durable_store/protected_verifier.ex
02735f8c61c864e003fe3ec596476cd315f8833080ee5c26e7cb152abf27fd41  foundry/lib/pramana_foundry/event_log.ex
df569423c58a67452cdb93d98259615ac0996b671dccb40089de28dce8c24caf  foundry/mix.exs
bf2a61f815533a96b2abec87b1690ae49145bec56e60703a22b4db178c56e954  foundry/mix.lock
61a0a269f24d54dd5f502149782df0e9b869d924c53d517d390ad6c60b648643  foundry/test/pramana_foundry/durable_store/gateway_test.exs
860747cd8a8625df6da6bad38c38f604ef97831b4ebc8d9068ebeabf128d9483  foundry/test/pramana_foundry/durable_store/legacy_import_test.exs
337dae0aa01d414bcf4c597ea588f028f448f03a87195e16d4d38ce4f3e4d3fc  foundry/test/pramana_foundry/durable_store/review_corrections_test.exs
3ae8d04b40265a8c97805293201ccfc9964a88ca6916bf42cf6a7efd6b074d19  foundry/test/support/durable_store_crash_fixture.exs
a668e2c892364d0851a63abb87f92161fb10034966f57c3b73f7447bf73b376e  foundry/test/support/durable_store_owner_probe.exs
da708d3be8d15e0b29bee729868adcf5f13524b45dd62ecb036e9b25d01c2ffa  foundry/test/support/durable_store_write_fault_fixture.exs
```
