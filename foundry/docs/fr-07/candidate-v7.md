# FR-07 candidate v7

Date: 2026-09-19

## Immutable identity

- Candidate implementation revision: `ca3445bcbd34833f1ece0c624e59c8a05ae71cbf`.
- Candidate implementation tree: `ededaf9951cfb2ad5d353f1dd6089b0eb6490b6f`.
- Current-main base: `75a56c13ebafa0ab7e67f2cf12f47ad84aad2ebc`.
- Branch: `repair/fr07-v6-recovered`.
- Worktree: `/Users/raymondluong/dev/pramana-fr07-worktree`.
- Failed independent v6 review: `review-v6.md`, SHA-256
  `7151d544e1d64e757d75f33428e361d668c84356631b09fed1d3daeda491f35f`.
- Implementation response: `review-response-v6.md`, SHA-256
  `a8fe0475b04d74eafdf96c0b9ce986b9de71f22de4b87c6aa9e88db49ccf8ad4`.

This candidate corrects review blockers B1–B6. The full disposition and exact boundary
changes are in `review-response-v6.md`. No coordinator plan/log, CLI, live daemon,
provider, credential, deployment or activation state was changed.

## Executed evidence

Pinned Elixir 1.20.3 / OTP 29.0.5, fresh private temporary roots, and external runtime
variables removed:

- `MIX_ENV=test mix compile --force --warnings-as-errors`: exit 0; 90 files.
- `mix test test/pramana_foundry/durable_store --seed 9141`: exit 0; 75 passed.
- `mix test --seed 9142`: exit 2; 507/508 passed. The sole failure is
  `test/pramana_foundry/projections/benchmark_test.exs:16`; Python cannot import
  `tiktoken`, so fallback token counts differ from the committed benchmark. This is a
  recorded non-FR-07 environment exclusion, not a full-suite pass.

The focused suite includes the review's projection rewind, missing owner/result
projection and ledger reads, orphan effect/FK source backup, total protected facts and
lookup ingress, mismatched and matching import staging evidence, exact index/FK/schema
contracts, and an executable query-plan assertion for the bounded projection index. It
also retains the complete prior durability, import, backup, recovery and WAL xSync
evidence.

FR-08, FR-15a, FR-17, FR-19 and FR-22 remain downstream. This implementation-owner freeze
makes no independent review or acceptance claim.

## Candidate path manifest

The candidate document itself is intentionally outside this manifest.

```text
2894b0f0e26e8dee8b485bd84638a095d105fb9dffa1b29f7cd6c0995a800802  foundry/README.md
fb43078bb6ee966f5e88059ee896f5d13baa6f3ea9684a9d889a71c7ba3a2f16  foundry/docs/DURABLE-STORE.md
4563d9ba365651a787f3f4acda699ce6fdd27bfadefc56ad089b4e5dd482e3fd  foundry/docs/fr-07/candidate-v2.md
fe5467711af2cef0880b5e0285e9bcd233136a5b43dd83cff9af480fed0d1d8d  foundry/docs/fr-07/candidate-v3.md
20c6c81fce5bdbc64919a0421803e75627b0a43da762713a0f180e2e7ef61726  foundry/docs/fr-07/candidate-v4-withdrawal.md
e43ec02dacbbcb706b71f1992a4403323ddcbd3a30f5dc7fcdc514e5055bd48a  foundry/docs/fr-07/candidate-v4.md
b25bcabbf4d4a75e80db19c6b919f502e34758c68c6f4d65743a536dc3b724f4  foundry/docs/fr-07/candidate-v5.md
2fa7ea6390031b53ad6b4f833b4b5612e808dcad1b3d8e3e1832f9a554316690  foundry/docs/fr-07/candidate-v6-supplement.md
06a0d33720e024dae2a322030c831d111dd3672d0b67d8a473fc732214def7c4  foundry/docs/fr-07/candidate-v6.md
9b5af120979e0e44e1b47298cb9107f531ec1d0db0d9a50a88e68f3cb5ce3e73  foundry/docs/fr-07/candidate.md
5f1d7d7113a47e5db07219d933b7f60c491ef130e29054b5b36dc040e591c6f7  foundry/docs/fr-07/diagnosis-v3.md
fc6013eaf46ae39c6966397d4feb1c8d9fb35b8137800e05a0dcd6d88cfea74e  foundry/docs/fr-07/diagnosis-v6.md
9e0e2be78603b2069961d8b363cd50715a0d58d53f48910ceaa8790f8ac92556  foundry/docs/fr-07/review-response-v2.md
bd9b1ac2c753d16d918aedf3a7ffcf817ef501a082f31960e4f64b89e503d704  foundry/docs/fr-07/review-response-v3.md
9c1dce400f8ba4243e53ede95ed2c5e23cdc566427153de1ff35250806dd4e1f  foundry/docs/fr-07/review-response-v5.md
a8fe0475b04d74eafdf96c0b9ce986b9de71f22de4b87c6aa9e88db49ccf8ad4  foundry/docs/fr-07/review-response-v6.md
d089de9abaca36e65674218844634944cf33a082734666a8a343ce06cbb65f39  foundry/docs/fr-07/review-response.md
4dab766e7616e40630d2000499319f37ee8216851f5a73f25cf74f6a2c9e8ad4  foundry/docs/fr-07/review-v2.md
b5f7fe402404d8d8e9a41d55a779b56035ce1c39faf4515b82874d88cd9489e6  foundry/docs/fr-07/review-v3.md
e5d838581d3dd76156798ec4423cba99a3b21090037afa2d90ebc653cd6811fa  foundry/docs/fr-07/review-v5.md
7151d544e1d64e757d75f33428e361d668c84356631b09fed1d3daeda491f35f  foundry/docs/fr-07/review-v6.md
bba396dd837ad06018c460a4dd68223792d536542b7fbdb53cfaea2092597f30  foundry/docs/fr-07/review.md
3fecc313366aab6f895e109835c0cd956e28237ce8bcca9c92091bc0816d560b  foundry/lib/pramana_foundry/durable_store/authority.ex
ebbf593cfb9acb975ff37ae12affcea5f9dae1896b2f4b679f56f83f85733182  foundry/lib/pramana_foundry/durable_store/compatibility_writer.ex
b8669c88b639a4573ac44734266561396719cea0e8b8cf6d8960674e7f4296b2  foundry/lib/pramana_foundry/durable_store/database.ex
140730a723527d3e7c9f71f0e54c209f14ce4a8b74004e553f12f14ce7c987ba  foundry/lib/pramana_foundry/durable_store/encoding.ex
71742ca574ccc21806eb5cd6fb211946bad18a5049f1048bf9bde5c655723247  foundry/lib/pramana_foundry/durable_store/gateway.ex
918e7efbfbaaf6f2943b1b1ce403cf08615c330b300d6e0c9e1b7b192a6406ac  foundry/lib/pramana_foundry/durable_store/kernel.ex
158a8419cc59ee7e3998f2e497308d2a03a88871f79c1e031849cfcfef24a322  foundry/lib/pramana_foundry/durable_store/legacy_import.ex
ddd8a5cbbbc1b40a2192cf8d24f72072ba0e824e13c527e7089f8fe1d97b0fa4  foundry/lib/pramana_foundry/durable_store/legacy_line.ex
03b1f1ddb23496a1a80b6cf0a77191c262721912f616fcb0ec0bf61523950e7b  foundry/lib/pramana_foundry/durable_store/owner.ex
f97cfd0d019d29cb6adf63ef079797f3104954cd069c00fd9faae2a88d0a252e  foundry/lib/pramana_foundry/durable_store/path_identity.ex
1e999ca8c310ec479973e310392fba23d0a68e07686e99d7b13d50d92d8fd7b8  foundry/lib/pramana_foundry/durable_store/protected_verifier.ex
8bd05827b932e00dffbeeda84383d509a61d1cbc4be3fa58943ecfbef2930131  foundry/lib/pramana_foundry/durable_store/record_codec.ex
02735f8c61c864e003fe3ec596476cd315f8833080ee5c26e7cb152abf27fd41  foundry/lib/pramana_foundry/event_log.ex
df569423c58a67452cdb93d98259615ac0996b671dccb40089de28dce8c24caf  foundry/mix.exs
bf2a61f815533a96b2abec87b1690ae49145bec56e60703a22b4db178c56e954  foundry/mix.lock
2103f312d2418faa0e10f01292ece199ec5b0b85b7722f16315d2ba30f2b35d7  foundry/test/pramana_foundry/durable_store/authority_test.exs
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
