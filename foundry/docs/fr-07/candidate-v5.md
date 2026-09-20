# FR-07 protected-sync candidate v5

Frozen 2026-09-13 for renewed independent review. V4 was self-withdrawn before verdict;
`candidate-v4.md` and `candidate-v4-withdrawal.md` preserve its exact identity and reason.
All earlier rejected candidates, FAIL reviews and the focused diagnosis remain history.

## Exact identity

- Base: `8aa0ebddbfb5fa834bbefa53d1f84b992e4c25bd`.
- Withdrawn v4 provenance commit/tree:
  `8d2447e73dd29fdacc797ddea7fd47ab32299efe` /
  `2c8467430faf53d0aa676048ddd963ed727296db`.
- V5 implementation commit/tree:
  `d25a51f8b219a8a49ed9e83b3d97d972058254f3` /
  `b454a2fd0f4af1669ad02d616bacfd3148630738`.
- Worktree/branch: `/private/tmp/pramana-fr07-replay`, `repair/fr07`.
- Pinned Elixir 1.20.3 / OTP 29.0.5; `exqlite == 0.40.0` with its native in-process
  SQLite engine.
- V3 review: `b5f7fe402404d8d8e9a41d55a779b56035ce1c39faf4515b82874d88cd9489e6`.
- Focused diagnosis: `5f1d7d7113a47e5db07219d933b7f60c491ef130e29054b5b36dc040e591c6f7`.
- Independent sync design: `d3c2da810a3d44068ed38fdfc878323168e34005dad3c30b0ab3fac4a6a394d7`.
- V4 withdrawal: `20c6c81fce5bdbc64919a0421803e75627b0a43da762713a0f180e2e7ef61726`.

## V5 correction and executable evidence

V5 changes both xSync cases to seed and submit complete protected
`transact_verified` bundles with intent, claim, top-level ledger generation and reservation
rows. It compares all authority-table counts and stable snapshot content, reconstructs
projections, fences post-error writes, reopens normally and after a hard process exit, and
performs the identical command retry whether the unacknowledged transaction recovered as a
complete bundle or as absent. An unrelated protected store commits while the target fault
is scoped. The fixture observes successful WAL writes before returning exactly one
`SQLITE_IOERR_FSYNC` (1034) from the target connection's WAL `xSync`.

Startup now applies an explicit typed ledger-generation semantic validator. The currently
supported FR-07 form is a version-1, revision-zero, nonnegative top-level allocation;
retained child-generation rows fence as corrupt authority. Canonical command admission,
stored body digest and input/command relational columns are also checked through
`RecordCodec`, preventing a corrupt retained request from diverging from its SQL identity.

Executed from `foundry/` with the pinned toolchain:

- Changed-path `mix format --check-formatted`: exit 0.
- `MIX_ENV=test mix compile --force --warnings-as-errors`: 87 project files, exit 0.
- Fresh focused storage/containment/checkpoint suite, seed 7733,
  `TMPDIR=/private/tmp/fr07-v5-focused.xCHdNa`: **62 passed**, exit 0.
- Fresh full model-free suite, seed 7734, `TMPDIR` and `MIX_BUILD_PATH` beneath
  `/private/tmp/fr07-v5-final-full.ogQ4ms`: **471 passed**, exit 0.

The sync conclusion remains narrow and accurate: this proves an attributed SQLite VFS
xSync-error path through the actual production Exqlite connection, checked-COMMIT
acknowledgment fencing, recovery and protected-bundle atomicity. It does not prove a kernel
`fsync(2)` syscall failed, power-loss durability or physical-media behavior. FR-19 retains
physical filesystem capacity/sync, WAL/checkpoint/compaction and maintenance conformance.
FR-08/15a/17/19/22 remain downstream; nothing is deployed or activated.

## Implementation manifest

These hashes cover every base-to-v5-implementation changed path. This candidate file is
outside its own manifest and is committed separately.

```text
33136e5c3c25e92976762c3a581380d24d3ca2771162557d9d42bb0d4cc74c83  foundry/README.md
9cf894dfb00b4caf805c1e74340f8a5390dd45bc98e6d4e0a072b978fe192d7a  foundry/docs/DURABLE-STORE.md
5dc0c7bbe8bcf21943b03b27aec092116e602ea515c319a54d7b29b995d26b9a  foundry/docs/fr-07/candidate-v2.md
00400c9d445fd96287e5a6848362e3519cad75087f19dc16c235968856b9ff6a  foundry/docs/fr-07/candidate-v3.md
20c6c81fce5bdbc64919a0421803e75627b0a43da762713a0f180e2e7ef61726  foundry/docs/fr-07/candidate-v4-withdrawal.md
8f61ce89e14cadd0827c812aa64da9cab3876ccf409d0978ea85c6262a262f65  foundry/docs/fr-07/candidate-v4.md
79a5ded644517b294a67e3e3e7a214b97f3ee518d448b8e39929e846e794b4e9  foundry/docs/fr-07/candidate.md
5f1d7d7113a47e5db07219d933b7f60c491ef130e29054b5b36dc040e591c6f7  foundry/docs/fr-07/diagnosis-v3.md
9e0e2be78603b2069961d8b363cd50715a0d58d53f48910ceaa8790f8ac92556  foundry/docs/fr-07/review-response-v2.md
bd9b1ac2c753d16d918aedf3a7ffcf817ef501a082f31960e4f64b89e503d704  foundry/docs/fr-07/review-response-v3.md
d089de9abaca36e65674218844634944cf33a082734666a8a343ce06cbb65f39  foundry/docs/fr-07/review-response.md
4dab766e7616e40630d2000499319f37ee8216851f5a73f25cf74f6a2c9e8ad4  foundry/docs/fr-07/review-v2.md
b5f7fe402404d8d8e9a41d55a779b56035ce1c39faf4515b82874d88cd9489e6  foundry/docs/fr-07/review-v3.md
bba396dd837ad06018c460a4dd68223792d536542b7fbdb53cfaea2092597f30  foundry/docs/fr-07/review.md
ebbf593cfb9acb975ff37ae12affcea5f9dae1896b2f4b679f56f83f85733182  foundry/lib/pramana_foundry/durable_store/compatibility_writer.ex
b036788a5bbfcf04605ccb29a5b0eeba6cec201d2e11d0bb7de74d9205ebdae0  foundry/lib/pramana_foundry/durable_store/database.ex
140730a723527d3e7c9f71f0e54c209f14ce4a8b74004e553f12f14ce7c987ba  foundry/lib/pramana_foundry/durable_store/encoding.ex
2c15859a1b9b41386cc24923e99404cd8925aaa29d22b975f4bb9074469077f3  foundry/lib/pramana_foundry/durable_store/gateway.ex
f61135e88c897eac263cea94c1c508d6dd2cf7526dce09a505baa56e5975130d  foundry/lib/pramana_foundry/durable_store/kernel.ex
ad298c8b55801b6355d44dc6077c4ccc7b7d26d1c2de3925c720ef85d1f567e2  foundry/lib/pramana_foundry/durable_store/legacy_import.ex
30feb79fd98e3f887efccb907ff1e61d8fa5872eb4dbc1d045213fc94e8e5f0a  foundry/lib/pramana_foundry/durable_store/owner.ex
51df369c9ea56ddab5ac3f1e7a075f017397162fca48c0717c3c5f681feb58f6  foundry/lib/pramana_foundry/durable_store/path_identity.ex
d515c960069beae97e8e67a946fa4e360d87957680ffd12e0a7cd71a692daaf1  foundry/lib/pramana_foundry/durable_store/protected_verifier.ex
37c9514f12a036078373a389d6d7b58d949e28e326318f613983cf71ce2ef45c  foundry/lib/pramana_foundry/durable_store/record_codec.ex
02735f8c61c864e003fe3ec596476cd315f8833080ee5c26e7cb152abf27fd41  foundry/lib/pramana_foundry/event_log.ex
df569423c58a67452cdb93d98259615ac0996b671dccb40089de28dce8c24caf  foundry/mix.exs
bf2a61f815533a96b2abec87b1690ae49145bec56e60703a22b4db178c56e954  foundry/mix.lock
61a0a269f24d54dd5f502149782df0e9b869d924c53d517d390ad6c60b648643  foundry/test/pramana_foundry/durable_store/gateway_test.exs
cb1ca8d04016830b8e6f90f07e18876464f9388324d4dc07d7c8be6f82e9ff68  foundry/test/pramana_foundry/durable_store/legacy_import_test.exs
2d51dc164236fb7faf2b70a4f1b79f2d6a373ceceaceb5d35ee52d3bc1d4dbc4  foundry/test/pramana_foundry/durable_store/path_identity_test.exs
549c4e8c85d7b3e593ba57e8466cdd2c7538b64853fed27c166110e650f2af55  foundry/test/pramana_foundry/durable_store/record_codec_test.exs
6d7d8276b9003ed605fa153db8db4d16d0cc08775772e6f04c75f5d352185f2e  foundry/test/pramana_foundry/durable_store/review_corrections_test.exs
9c2b3818ea3c4a2acc90780f77d63869dd27821e93b2bd2d3a55450bed62d5cc  foundry/test/pramana_foundry/durable_store/sync_fault_test.exs
59b173c1c4e4e61f39fbfe4d6b703474ce3991124e1201e0b201bec4224e0528  foundry/test/pramana_foundry/durable_store/unified_contract_test.exs
3ae8d04b40265a8c97805293201ccfc9964a88ca6916bf42cf6a7efd6b074d19  foundry/test/support/durable_store_crash_fixture.exs
a668e2c892364d0851a63abb87f92161fb10034966f57c3b73f7447bf73b376e  foundry/test/support/durable_store_owner_probe.exs
da708d3be8d15e0b29bee729868adcf5f13524b45dd62ecb036e9b25d01c2ffa  foundry/test/support/durable_store_write_fault_fixture.exs
a1af83ab98b4fbf8cd660d29430f339ed1970d03a484a2566ef15348658cf981  foundry/test/support/fr07_sync_crash_fixture.exs
508777be16e52c390aed8986ee60c005c4d5c3e2319c7423012c4e8a3f46f90d  foundry/test/support/fr07_sync_fault.c
```
