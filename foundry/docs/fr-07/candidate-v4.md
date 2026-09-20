# FR-07 unified candidate v4

Frozen 2026-09-13 for renewed independent review. The rejected v1, v2 and v3 candidates,
all three independent FAIL records and the required focused diagnosis remain immutable
history. This candidate is not accepted until a different reviewer approves this exact
revision.

## Identity and inputs

- Base: `8aa0ebddbfb5fa834bbefa53d1f84b992e4c25bd`.
- Rejected v3: `f4a77de4ab3795716b00f807b4cd659e602654c4`.
- Unified implementation: `257671e083908901390d622b6c6bfd4df2f3b9a8`.
- Implementation tree: `ea6f7c10b19e42dea61c341f0a8ee51a40b07d09`.
- Worktree/branch: `/private/tmp/pramana-fr07-replay2`, `repair/fr07`.
- Pinned Elixir 1.20.3 / OTP 29.0.5; `exqlite == 0.40.0` using its native in-process
  SQLite implementation.
- Exact v3 review SHA-256:
  `b5f7fe402404d8d8e9a41d55a779b56035ce1c39faf4515b82874d88cd9489e6`.
- Exact focused diagnosis SHA-256:
  `5f1d7d7113a47e5db07219d933b7f60c491ef130e29054b5b36dc040e591c6f7`.
- Independent sync-design input SHA-256:
  `d3c2da810a3d44068ed38fdfc878323168e34005dad3c30b0ab3fac4a6a394d7`.
- Author response SHA-256:
  `bd9b1ac2c753d16d918aedf3a7ffcf817ef501a082f31960e4f64b89e503d704`.

## Executed acceptance evidence

All commands ran from `foundry/` with the pinned toolchain.

- `mix format --check-formatted` over changed Elixir/test paths: exit 0.
- `MIX_ENV=test mix compile --force --warnings-as-errors`: 87 project files, exit 0.
- Fresh focused suite with storage, legacy containment and checkpoint tests, seed 7728:
  **60 passed**, exit 0.
- Fresh full model-free suite, seed 7729, with
  `TMPDIR=/private/tmp/fr07-v4-final-full.39bkOm` and build output below the same fresh
  root: **469 passed**, exit 0.
- `git diff --check` is clean except the intentionally preserved trailing spaces in the
  byte-identical diagnosis input; its hash matches the required source exactly.

The focused suite covers normalization/default phase equivalence, atom/string semantic-key
collisions, unsupported values and versions, exact result semantics and relational binding,
missing/extra/reordered projection transitions, ordered same-entity updates, direct read,
lost-reply same-ID retry, clean reopen, full-content backup and reconstruction. Path tests
cover raw dot/dotdot/repeated/trailing aliases, parent/leaf symlinks, hardlinks, gateway,
initialize, migration, import and backup entry points. Prior atomicity, constraints,
multi-table failpoints, import interruption/rerun, torn/oversize input, RLIMIT_FSIZE and
process-crash fixtures remain green.

The test-only native fixture compiles without a second SQLite engine and loads into the
actual Exqlite connection. It observes successful WAL `xWrite` callbacks before returning
`SQLITE_IOERR_FSYNC` (1034) exactly once from the targeted WAL `xSync` at checked COMMIT.
Both orderly and hard-exit cases prove no success acknowledgment, immediate write fencing,
explicit owner recovery, complete content/reconstruction and ambiguity-safe same-command
retry. This is specifically VFS xSync-fault evidence, not a claim that the kernel
`fsync(2)` syscall or physical medium failed.

## Audit and downstream preservation

- F02: commit/acknowledgment, corruption/recovery, capacity, torn/oversize history and
  idempotent retry obligations are executable here; no unreadable authority becomes empty.
- F20: FR-07 establishes sequence/index/snapshot/serialized-owner foundations. FR-19 still
  owns operational retention, capacity publication and compaction scheduling/faults.
- F21: FR-07 import is offline, collision-safe, digest-verified and non-removing. FR-19
  still owns general relocation journals, cross-device movement and source-removal policy.

FR-08 full mutation routing/replay, FR-15a hostile-worker isolation, FR-17 Git activation,
FR-19 physical maintenance/fault coverage and FR-22 lifecycle acceptance are not claimed.
No live daemon, provider, credential, deployment, activation or Git integration was used.

## Implementation manifest

The following hashes cover every base-to-implementation changed path. This candidate file
is outside its own manifest and is committed separately for provenance.

```text
33136e5c3c25e92976762c3a581380d24d3ca2771162557d9d42bb0d4cc74c83  foundry/README.md
19a24043065ca9435400f62ccf3eadb4425a32ac0ff8159c9d46c99c1beb264c  foundry/docs/DURABLE-STORE.md
5dc0c7bbe8bcf21943b03b27aec092116e602ea515c319a54d7b29b995d26b9a  foundry/docs/fr-07/candidate-v2.md
00400c9d445fd96287e5a6848362e3519cad75087f19dc16c235968856b9ff6a  foundry/docs/fr-07/candidate-v3.md
79a5ded644517b294a67e3e3e7a214b97f3ee518d448b8e39929e846e794b4e9  foundry/docs/fr-07/candidate.md
5f1d7d7113a47e5db07219d933b7f60c491ef130e29054b5b36dc040e591c6f7  foundry/docs/fr-07/diagnosis-v3.md
9e0e2be78603b2069961d8b363cd50715a0d58d53f48910ceaa8790f8ac92556  foundry/docs/fr-07/review-response-v2.md
bd9b1ac2c753d16d918aedf3a7ffcf817ef501a082f31960e4f64b89e503d704  foundry/docs/fr-07/review-response-v3.md
d089de9abaca36e65674218844634944cf33a082734666a8a343ce06cbb65f39  foundry/docs/fr-07/review-response.md
4dab766e7616e40630d2000499319f37ee8216851f5a73f25cf74f6a2c9e8ad4  foundry/docs/fr-07/review-v2.md
b5f7fe402404d8d8e9a41d55a779b56035ce1c39faf4515b82874d88cd9489e6  foundry/docs/fr-07/review-v3.md
bba396dd837ad06018c460a4dd68223792d536542b7fbdb53cfaea2092597f30  foundry/docs/fr-07/review.md
ebbf593cfb9acb975ff37ae12affcea5f9dae1896b2f4b679f56f83f85733182  foundry/lib/pramana_foundry/durable_store/compatibility_writer.ex
190f8ac5a68f3186931aaf4c4a2d6ce09150de969b79b91fc879575bd8a0ddfa  foundry/lib/pramana_foundry/durable_store/database.ex
140730a723527d3e7c9f71f0e54c209f14ce4a8b74004e553f12f14ce7c987ba  foundry/lib/pramana_foundry/durable_store/encoding.ex
d5725fb6ac21a35e34b27e87a31f7f32556a173679624152bc492f273245e828  foundry/lib/pramana_foundry/durable_store/gateway.ex
f61135e88c897eac263cea94c1c508d6dd2cf7526dce09a505baa56e5975130d  foundry/lib/pramana_foundry/durable_store/kernel.ex
ad298c8b55801b6355d44dc6077c4ccc7b7d26d1c2de3925c720ef85d1f567e2  foundry/lib/pramana_foundry/durable_store/legacy_import.ex
30feb79fd98e3f887efccb907ff1e61d8fa5872eb4dbc1d045213fc94e8e5f0a  foundry/lib/pramana_foundry/durable_store/owner.ex
51df369c9ea56ddab5ac3f1e7a075f017397162fca48c0717c3c5f681feb58f6  foundry/lib/pramana_foundry/durable_store/path_identity.ex
d515c960069beae97e8e67a946fa4e360d87957680ffd12e0a7cd71a692daaf1  foundry/lib/pramana_foundry/durable_store/protected_verifier.ex
df218e6d4a9e8da1aa4843ae31b7b8993c8cab5a815393e7742ba300d05de013  foundry/lib/pramana_foundry/durable_store/record_codec.ex
02735f8c61c864e003fe3ec596476cd315f8833080ee5c26e7cb152abf27fd41  foundry/lib/pramana_foundry/event_log.ex
df569423c58a67452cdb93d98259615ac0996b671dccb40089de28dce8c24caf  foundry/mix.exs
bf2a61f815533a96b2abec87b1690ae49145bec56e60703a22b4db178c56e954  foundry/mix.lock
61a0a269f24d54dd5f502149782df0e9b869d924c53d517d390ad6c60b648643  foundry/test/pramana_foundry/durable_store/gateway_test.exs
cb1ca8d04016830b8e6f90f07e18876464f9388324d4dc07d7c8be6f82e9ff68  foundry/test/pramana_foundry/durable_store/legacy_import_test.exs
2d51dc164236fb7faf2b70a4f1b79f2d6a373ceceaceb5d35ee52d3bc1d4dbc4  foundry/test/pramana_foundry/durable_store/path_identity_test.exs
549c4e8c85d7b3e593ba57e8466cdd2c7538b64853fed27c166110e650f2af55  foundry/test/pramana_foundry/durable_store/record_codec_test.exs
6d7d8276b9003ed605fa153db8db4d16d0cc08775772e6f04c75f5d352185f2e  foundry/test/pramana_foundry/durable_store/review_corrections_test.exs
c6b7e8b764e0fac73ce10a146992f053d56a1126534b2e26968582a760993cb4  foundry/test/pramana_foundry/durable_store/sync_fault_test.exs
b46aba9ed3250796e9e12a64672b3385f42fc2f7229b8b31ffbb6c2c875b6825  foundry/test/pramana_foundry/durable_store/unified_contract_test.exs
3ae8d04b40265a8c97805293201ccfc9964a88ca6916bf42cf6a7efd6b074d19  foundry/test/support/durable_store_crash_fixture.exs
a668e2c892364d0851a63abb87f92161fb10034966f57c3b73f7447bf73b376e  foundry/test/support/durable_store_owner_probe.exs
da708d3be8d15e0b29bee729868adcf5f13524b45dd62ecb036e9b25d01c2ffa  foundry/test/support/durable_store_write_fault_fixture.exs
6171e03f39f1a7076e9a378f8483d97add34d5250021ff6ac2baf185f7b4d05a  foundry/test/support/fr07_sync_crash_fixture.exs
508777be16e52c390aed8986ee60c005c4d5c3e2319c7423012c4e8a3f46f90d  foundry/test/support/fr07_sync_fault.c
```
