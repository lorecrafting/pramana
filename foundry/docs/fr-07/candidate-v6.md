# FR-07 durable authority candidate v6 (recovered)

Frozen 2026-09-19 for fresh independent review. This candidate reconstructs the final
v6 implementation state whose isolated worktree was lost after main history advanced.
It does not convert the prior v5 FAIL into a PASS.

## Exact identity

- Current-main base: `75a56c13ebafa0ab7e67f2cf12f47ad84aad2ebc`.
- Reviewed implementation/docs commit: `940b8f710c661ef5f7ecd7c5c5ae9cc3fbed2ea6`.
- Tree: `2d1632ac183c19a50d87b74ddeb7332f9b7e6f08`.
- Branch/worktree: `repair/fr07-v6-recovered`,
  `/Users/raymondluong/dev/pramana-fr07-worktree`.
- Pinned runtime: Elixir 1.20.3 / OTP 29.0.5; `exqlite == 0.40.0`.
- V5 independent FAIL: `e5d838581d3dd76156798ec4423cba99a3b21090037afa2d90ebc653cd6811fa`.
- V6 diagnosis: `fc6013eaf46ae39c6966397d4feb1c8d9fb35b8137800e05a0dcd6d88cfea74e`.

## Recovery provenance

The source and tests were replayed from exact base
`8aa0ebddbfb5fa834bbefa53d1f84b992e4c25bd` using the surviving Codex rollout,
with successful and partially superseded edits resolved against their recorded formatting
boundaries, then validated before the bounded FR-07 commit was transplanted onto current
main. The stable rollout prefix SHA256 is
`ecf3d05e03f059d67c0b80f95bfaf8dc7589e42e8c2e32b1f9c774c1d22562d1`.
The recovered evidence bundle manifest hashes to
`c52a6a89721afeab112173aab1e44dc9ab02fb7643af2f1d6eae4adfa6356f67`.

An intermediate replay from the old base compiled with warnings as errors and passed the
durable-store suite 68/68. The transplanted result on current main was then independently
rebuilt in its own fresh temporary root and produced the same outcome.

## Executed evidence

From `foundry/` with the pinned toolchain:

- `MIX_ENV=test mix compile --force --warnings-as-errors`: exit 0, 90 project files.
- fresh `TMPDIR=/private/tmp/fr07-v6-current-main.*`,
  `mix test test/pramana_foundry/durable_store --seed 9044`: 68 passed, exit 0.
- The durable suite includes real SQLite WAL/FULL commits, engine backup and reopen,
  crash/lost-reply/idempotent retry, FULL/read-only/write failures, complete protected
  bundles, all 18 authority tables, >8 MiB streaming import, namespace/alias cases,
  reconstruction, and the test-only connection-scoped WAL VFS xSync fault.
- No live daemon, provider, credential, deployment or activation state was touched.

The xSync result is deliberately narrow: it proves a VFS xSync error returned through the
actual Exqlite connection, acknowledgment fencing and ambiguity-safe recovery. It is not a
physical kernel `fsync(2)`, power-loss or media-durability claim.

FR-08, FR-15a, FR-17, FR-19 and FR-22 remain downstream. A fresh independent reviewer must
challenge this exact candidate before FR-07 can be accepted.

## Manifest of reviewed implementation

The candidate document itself is intentionally outside this manifest and will be committed
as the freeze/provenance commit.

```text
2894b0f0e26e8dee8b485bd84638a095d105fb9dffa1b29f7cd6c0995a800802  foundry/README.md
9cf894dfb00b4caf805c1e74340f8a5390dd45bc98e6d4e0a072b978fe192d7a  foundry/docs/DURABLE-STORE.md
4563d9ba365651a787f3f4acda699ce6fdd27bfadefc56ad089b4e5dd482e3fd  foundry/docs/fr-07/candidate-v2.md
fe5467711af2cef0880b5e0285e9bcd233136a5b43dd83cff9af480fed0d1d8d  foundry/docs/fr-07/candidate-v3.md
20c6c81fce5bdbc64919a0421803e75627b0a43da762713a0f180e2e7ef61726  foundry/docs/fr-07/candidate-v4-withdrawal.md
e43ec02dacbbcb706b71f1992a4403323ddcbd3a30f5dc7fcdc514e5055bd48a  foundry/docs/fr-07/candidate-v4.md
b25bcabbf4d4a75e80db19c6b919f502e34758c68c6f4d65743a536dc3b724f4  foundry/docs/fr-07/candidate-v5.md
9b5af120979e0e44e1b47298cb9107f531ec1d0db0d9a50a88e68f3cb5ce3e73  foundry/docs/fr-07/candidate.md
fc6013eaf46ae39c6966397d4feb1c8d9fb35b8137800e05a0dcd6d88cfea74e  foundry/docs/fr-07/diagnosis-v6.md
9e0e2be78603b2069961d8b363cd50715a0d58d53f48910ceaa8790f8ac92556  foundry/docs/fr-07/review-response-v2.md
bd9b1ac2c753d16d918aedf3a7ffcf817ef501a082f31960e4f64b89e503d704  foundry/docs/fr-07/review-response-v3.md
9c1dce400f8ba4243e53ede95ed2c5e23cdc566427153de1ff35250806dd4e1f  foundry/docs/fr-07/review-response-v5.md
d089de9abaca36e65674218844634944cf33a082734666a8a343ce06cbb65f39  foundry/docs/fr-07/review-response.md
4dab766e7616e40630d2000499319f37ee8216851f5a73f25cf74f6a2c9e8ad4  foundry/docs/fr-07/review-v2.md
b5f7fe402404d8d8e9a41d55a779b56035ce1c39faf4515b82874d88cd9489e6  foundry/docs/fr-07/review-v3.md
e5d838581d3dd76156798ec4423cba99a3b21090037afa2d90ebc653cd6811fa  foundry/docs/fr-07/review-v5.md
bba396dd837ad06018c460a4dd68223792d536542b7fbdb53cfaea2092597f30  foundry/docs/fr-07/review.md
fc550b2c0fde443f833a4d8791df559a6aedd112e3bb854accdcd6407da81299  foundry/lib/pramana_foundry/durable_store/authority.ex
ebbf593cfb9acb975ff37ae12affcea5f9dae1896b2f4b679f56f83f85733182  foundry/lib/pramana_foundry/durable_store/compatibility_writer.ex
93ff01a43b6a55eb33ee71e5299ed7b5022fb88784a41698d92bdec80abe0591  foundry/lib/pramana_foundry/durable_store/database.ex
140730a723527d3e7c9f71f0e54c209f14ce4a8b74004e553f12f14ce7c987ba  foundry/lib/pramana_foundry/durable_store/encoding.ex
df0ee555f90ca4dc110a7fb04bed9af991f2724d9309afbf2cad46ac69b59950  foundry/lib/pramana_foundry/durable_store/gateway.ex
918e7efbfbaaf6f2943b1b1ce403cf08615c330b300d6e0c9e1b7b192a6406ac  foundry/lib/pramana_foundry/durable_store/kernel.ex
129d1fdd5f6d5ad27308c39f374e7f153e4a7ea5853c7cd286f877fde5a4b73d  foundry/lib/pramana_foundry/durable_store/legacy_import.ex
ddd8a5cbbbc1b40a2192cf8d24f72072ba0e824e13c527e7089f8fe1d97b0fa4  foundry/lib/pramana_foundry/durable_store/legacy_line.ex
03b1f1ddb23496a1a80b6cf0a77191c262721912f616fcb0ec0bf61523950e7b  foundry/lib/pramana_foundry/durable_store/owner.ex
f97cfd0d019d29cb6adf63ef079797f3104954cd069c00fd9faae2a88d0a252e  foundry/lib/pramana_foundry/durable_store/path_identity.ex
211bbfc57f0627262d4d06e14228943776f907670a9849a57fb53967becb095c  foundry/lib/pramana_foundry/durable_store/protected_verifier.ex
53a9be57b036c228466e16f5fb64104a6ece5420bc0adfe05b43190c72f30d6c  foundry/lib/pramana_foundry/durable_store/record_codec.ex
02735f8c61c864e003fe3ec596476cd315f8833080ee5c26e7cb152abf27fd41  foundry/lib/pramana_foundry/event_log.ex
df569423c58a67452cdb93d98259615ac0996b671dccb40089de28dce8c24caf  foundry/mix.exs
bf2a61f815533a96b2abec87b1690ae49145bec56e60703a22b4db178c56e954  foundry/mix.lock
6252aadb6e4afbbfb97c4e04c2fa6560b2df888738d73ee7dafa47ff6c5552db  foundry/test/pramana_foundry/durable_store/authority_test.exs
3cfbd6b558a9e14354e0213dfbdba22b952965790c5d88b4ab595b715f8f1c5b  foundry/test/pramana_foundry/durable_store/gateway_test.exs
1fc82748feed7249ace86d998f4f625dc144c91147ac63b4299dfc6fbb5e5eca  foundry/test/pramana_foundry/durable_store/legacy_import_test.exs
2d51dc164236fb7faf2b70a4f1b79f2d6a373ceceaceb5d35ee52d3bc1d4dbc4  foundry/test/pramana_foundry/durable_store/path_identity_test.exs
549c4e8c85d7b3e593ba57e8466cdd2c7538b64853fed27c166110e650f2af55  foundry/test/pramana_foundry/durable_store/record_codec_test.exs
da8c1128e265b271e87d18905ec57af4a7a80a2c4442a711ef2dba1fcbcfe2ae  foundry/test/pramana_foundry/durable_store/review_corrections_test.exs
298920774d6fb014d23f0a0f510264678c5681a2b1c593f77e70ad371dbb419e  foundry/test/pramana_foundry/durable_store/sync_fault_test.exs
66af1229d60bde6622e121fac4165c403f30ca6a12637fb9a0453e978f9f331d  foundry/test/pramana_foundry/durable_store/unified_contract_test.exs
3ae8d04b40265a8c97805293201ccfc9964a88ca6916bf42cf6a7efd6b074d19  foundry/test/support/durable_store_crash_fixture.exs
a668e2c892364d0851a63abb87f92161fb10034966f57c3b73f7447bf73b376e  foundry/test/support/durable_store_owner_probe.exs
da708d3be8d15e0b29bee729868adcf5f13524b45dd62ecb036e9b25d01c2ffa  foundry/test/support/durable_store_write_fault_fixture.exs
a1af83ab98b4fbf8cd660d29430f339ed1970d03a484a2566ef15348658cf981  foundry/test/support/fr07_sync_crash_fixture.exs
508777be16e52c390aed8986ee60c005c4d5c3e2319c7423012c4e8a3f46f90d  foundry/test/support/fr07_sync_fault.c
```
