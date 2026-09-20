# FR-07 corrected candidate

Frozen 2026-09-13 for renewed independent review after the exact FAIL preserved in
`review.md`.

## Identity and scope

- Base: `8aa0ebddbfb5fa834bbefa53d1f84b992e4c25bd`.
- Original rejected candidate: `d99799e46577d24ca178ac67dea12ce2b250ee87`.
- Corrected implementation: `bda425ab6666f367ef6ef1966a6d688d2bd6127f`.
- Corrected implementation tree: `610136117fe4edb5990f9769fa308d329759cf93`.
- Worktree/branch: `/private/tmp/pramana-fr07-replay`, `repair/fr07`.
- Runtime: pinned Elixir 1.20.3 / OTP 29.0.5; `exqlite == 0.40.0` with its native
  in-process SQLite engine. No Python implementation was added.
- Untracked fetched `foundry/deps/` directories are excluded. No live state, provider,
  credential, root-worktree CLI/Coordinator change, deployment or activation is included.

The candidate retains FR-08 (complete mutation routing and one replay/apply reducer),
FR-15a (hostile kernel process/account isolation), FR-17 (Git integration/activation),
FR-19 (operational retention/checkpoint/relocation/physical fault matrix) and FR-22
(lifecycle acceptance) as downstream obligations.

## Review disposition

`review-response.md` maps R1–R9 to corrected behavior and tests. The prior independent
FAIL remains immutable. This author record does not claim renewed independent review.
The one explicit unresolved acceptance item is a specifically failed fsync syscall:
Exqlite 0.40.0 and this host expose no controlled VFS/test-control hook. Actual SQLite
FULL, read-only refusal and OS-limited COMMIT/write I/O failure are passed, but none is
relabeled as a failed fsync.

## Acceptance evidence

All commands used the pinned Elixir/OTP PATH. No provider was invoked.

- `MIX_ENV=test mix compile --force --warnings-as-errors`: 85 files, exit 0.
- `mix format --check-formatted` over all owned changed Elixir/test paths: exit 0.
- Focused storage plus containment/checkpoint suite, seed 424207: 44 passed, exit 0.
- Final fresh-root full suite with `TMPDIR=/tmp/fr07-corrected-final.K9S1qH` and a build
  below that root: 452/453 passed. The sole failure was the unrelated pre-existing
  Telemetry scheduler assertion at `telemetry_test.exs:123`; immediate isolated rerun
  under another fresh TMPDIR passed 1/1. No FR-07/persistence test failed.

Executable corrections cover bounded pending intent types and exact effect digest;
transactional dependency/policy/control revision checks and rejected/no-mutation;
same-ID lookup before changed current facts; malformed/unknown-version/FK recovery
fencing; resolved import aliases, immutable archive input, exclusive offline ownership,
interruption and publication rerun; same-VM and separate-OS exclusive gateways with
ambiguous-owner recovery evidence; complete authority/import/metadata backup hashes and
reconstruction digest; failpoints after every bundle-table stage; complete protected
hard-crash bundles; transactional schema creation and migration rerun; exact lowercase
control encoding; actual max-page FULL, read-only and RLIMIT_FSIZE SQLite commit failure.

## Corrected implementation manifest

These hashes describe the 22 paths changed from the base through corrected implementation
commit `bda425a`; this candidate file is intentionally outside that self-contained list.

```text
33136e5c3c25e92976762c3a581380d24d3ca2771162557d9d42bb0d4cc74c83  foundry/README.md
c41998ae08fcc27b650420c693f4f09f0104e72e6b05cd52696a32b24fab9846  foundry/docs/DURABLE-STORE.md
79a5ded644517b294a67e3e3e7a214b97f3ee518d448b8e39929e846e794b4e9  foundry/docs/fr-07/candidate.md
d089de9abaca36e65674218844634944cf33a082734666a8a343ce06cbb65f39  foundry/docs/fr-07/review-response.md
bba396dd837ad06018c460a4dd68223792d536542b7fbdb53cfaea2092597f30  foundry/docs/fr-07/review.md
ebbf593cfb9acb975ff37ae12affcea5f9dae1896b2f4b679f56f83f85733182  foundry/lib/pramana_foundry/durable_store/compatibility_writer.ex
8eb631d184a88d43ed607afe905909cacfe20def21bc7ffafa2ba051f4d7a7da  foundry/lib/pramana_foundry/durable_store/database.ex
140730a723527d3e7c9f71f0e54c209f14ce4a8b74004e553f12f14ce7c987ba  foundry/lib/pramana_foundry/durable_store/encoding.ex
b14897be86028e1dcca4e7d5711c932321614e597dc6f5e5800533ccc39fa787  foundry/lib/pramana_foundry/durable_store/gateway.ex
5dfa4a36f141b4db27b2259444bd499a7299a8a77b7003f5feac63cc88418dee  foundry/lib/pramana_foundry/durable_store/kernel.ex
a4c06b0e94f343b66aba5ede2ae97b533756c00a11a3aa027dd6cdcd1eee52e1  foundry/lib/pramana_foundry/durable_store/legacy_import.ex
5e3f62511e81e986305ca4983a795a5cd865e961f7f65f4e39a1e4f75fbd1eec  foundry/lib/pramana_foundry/durable_store/owner.ex
06ba30e55aa1e46d854b8a10b844cc6e791030fb47de3002bda83b1739b01d69  foundry/lib/pramana_foundry/durable_store/protected_verifier.ex
02735f8c61c864e003fe3ec596476cd315f8833080ee5c26e7cb152abf27fd41  foundry/lib/pramana_foundry/event_log.ex
df569423c58a67452cdb93d98259615ac0996b671dccb40089de28dce8c24caf  foundry/mix.exs
bf2a61f815533a96b2abec87b1690ae49145bec56e60703a22b4db178c56e954  foundry/mix.lock
2bbfd5ad42607ea85f55beaa2af130b3e9a2e9d4d936fdad07034b7d5511ffc8  foundry/test/pramana_foundry/durable_store/gateway_test.exs
860747cd8a8625df6da6bad38c38f604ef97831b4ebc8d9068ebeabf128d9483  foundry/test/pramana_foundry/durable_store/legacy_import_test.exs
0137a3cd4d5e904216e6a585921d5aeac60bdd367a50e550f03e51f9312ff089  foundry/test/pramana_foundry/durable_store/review_corrections_test.exs
20b59692b06a7c8f523236bfdf8ffe820719045559c8c7d4ff33a86962c5e724  foundry/test/support/durable_store_crash_fixture.exs
0d29d28859a31276e61347a7e3bbaf59e84a75886c0efa776cce1fcb91c29839  foundry/test/support/durable_store_owner_probe.exs
d7d7cea70d5bc8163bd373b8619475d83ddacac210a9547b5097e3ed6815b216  foundry/test/support/durable_store_write_fault_fixture.exs
```
