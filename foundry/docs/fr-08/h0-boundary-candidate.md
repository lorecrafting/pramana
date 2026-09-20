# H0 accepted-FR-07 public-boundary corrected candidate

Refrozen 2026-09-19 (Hawaii) after the exact independent blocker review at
`b5abb5eab4d16c0075e5e2180a5ff059b51c9a70`. The correction supplies canonical
cross-VM receipts and verifies both source blobs and loaded BEAM identities before
crediting accepted-v9 behavior.

The H0 checkpoint remains an honest **blocked** inventory: 4 capabilities pass,
0 fail and 3 are unavailable; `FR08HandoffGate.ready?/1` is false. This candidate
requires renewed independent review. It does not implement FR-08A, authorize FR-08B,
or enable a daemon, provider, credential, deployment or activation path.

## Exact identity

- Accepted FR-07 v9 implementation: `af0c51b4682c50080e67194dd853fbaa1eebace7`,
  tree `e4aed492d5973d185a7e772d1b764e1117df11c1`.
- Accepted independent FR-07 review: `8d7223b79cb237d3406f156c7d1a06a8bcb48d81`,
  tree `894e47756305f1b0fb615c6471f2dfdc644f16f3`.
- Corrected H0 adapter/probe revision: `a23482de566dcd7be567dff49985ff8c97536df9`,
  tree `939c8f96f451594fb391ffc17ed9073a6531f5ad`.
- Blocking review: `b5abb5eab4d16c0075e5e2180a5ff059b51c9a70`; report SHA-256
  `0c95ee9fdcfaaf2c2d170ba7f727c0f5f574c3a530e01eb6262ccb71eef0c583`.
- Supplied base: `25e109730bdb31fa475215813030d9b01ec43675`.
- Branch/worktree: `repair/h0-fr07-boundary`,
  `/Users/raymondluong/dev/pramana-h0`.
- Corrected frozen report SHA-256:
  `c6806ec25a43b4f921501769c433cd98eacd77f6e5dcccaefd85df2f01ced6fd`.

## B1 correction — canonical receipts and fresh BEAM reproduction

Positive receipts now hash a documented `pramana-foundry-h0-receipt/v1` envelope.
Its encoding is UTF-8 JSON with recursively byte-sorted string keys and no insignificant
whitespace. Accepted values are strings, integers, booleans, nulls, proper lists and
string-keyed plain maps; unsupported values and non-string keys raise instead of silently
acquiring an unstable representation. No receipt uses `term_to_binary/1`.

The corrected tests launch two separate BEAM processes through `mix run --no-start
--no-compile`. One preloads the four accepted API modules in normal order and the other
in reverse order. Each independently executes all real public probes and renders the
report. Both outputs are byte-identical to each other and to the committed frozen report:

```text
c6806ec25a43b4f921501769c433cd98eacd77f6e5dcccaefd85df2f01ced6fd  normal.txt
c6806ec25a43b4f921501769c433cd98eacd77f6e5dcccaefd85df2f01ced6fd  reverse.txt
c6806ec25a43b4f921501769c433cd98eacd77f6e5dcccaefd85df2f01ced6fd  foundry/docs/fr-08/h0-accepted-fr07-report.txt
```

The test also resolves the adapter/probe revision from the frozen report and requires
`git show` at that revision to reproduce the current provider, provider test and both
fresh-process fixtures byte-for-byte.

## B2 correction — checked source plus loaded-code binding

Before every probe, the provider checks all four exercised FR-07 modules using two
independent identities:

| Accepted module | Source SHA-256 | Loaded BEAM MD5 |
|---|---|---|
| `Gateway` | `71742ca574ccc21806eb5cd6fb211946bad18a5049f1048bf9bde5c655723247` | `545016e2a46e4810b9c275683ca82c33` |
| `Kernel` | `918e7efbfbaaf6f2943b1b1ce403cf08615c330b300d6e0c9e1b7b192a6406ac` | `e43949e9a2658ebbd12afabdf2f30086` |
| `LegacyImport` | `158a8419cc59ee7e3998f2e497308d2a03a88871f79c1e031849cfcfef24a322` | `c91b85e002244d83b85410de3c2f666b` |
| `RecordCodec` | `8bd05827b932e00dffbeeda84383d509a61d1cbc4be3fa58943ecfbef2930131` | `be95460c6e50de9cdb4bd85945413708` |

The source is read from each loaded module's compile metadata. The report records
`implementation_binding=verified|source-sha256+beam-md5/v1` only when every source and
loaded module matches. Each isolated gate callback repeats the check immediately before
its probe, so changing loaded code after the outer report check cannot retain a positive
result.

The fresh-process negative control recompiles the real `Gateway` source in memory with a
new public `command/2` sentinel clause and proves that behavior executes. The source blob
still matches, but the loaded MD5 does not. The resulting report records a mismatched
implementation binding and all seven capabilities become unavailable with reason
`h0:loaded_accepted_api_identity_mismatch`: 0 pass, 0 fail, 7 unavailable, blocked and
not ready. The process prints `identity_mismatch_refused` and exits 0. No source, BEAM,
database or frozen artifact is modified by the negative control.

## Preserved public capability disposition

Only documented `Gateway` operations and offline `LegacyImport.run/4` are used. There is
no SQL, private table mutation, `Authority`, `Database`, `ProtectedVerifier`, extracted
connection or `transact_verified/6` use.

| Capability | Result | Public evidence or limitation |
|---|---|---|
| Same-command lookup before revision | passed | A real projection command is committed and then retried with an invalid empty proposal. The original result returns before stale validation. Different actor and changed-payload retries conflict. Receipt `4cbbe09bbb851b0f1d11753a319e73cce9c24acc77c6642adb866f3f989bf2f8`. |
| Complete read-set CAS | unavailable | The public API cannot evolve policy, control or allocation state; projection CAS alone is insufficient. |
| Atomic authority commit | unavailable | No public receipt/lease creation, claim issuance/settlement or ledger-evolution operation exists. |
| Revision and inbox facts | unavailable | Projection revisions exist, but no public authenticated inbox sequence/seal operation exists. |
| Protected-field boundary | passed | Atom and string forms of nine protected fields produce 18 rejected public proposals and zero public counts: claims, receipts, leases, ledger generations, policy/control revisions, artifact references, balances and accepted refs. Receipt `5b5c41709ccd3d3a4dcfe53da64af33cd504dda2f58cec4e08429a18a2b3db07`. |
| Fail-closed recovery | passed | A missing store reports `:not_initialized`, refuses transaction/count access and creates no database. Receipt `2ef5038948954752da48914f343f3cbabe97ae6e6aac61b3da23fdb112af8129`. |
| Immutable legacy import | passed | One unsupported-version and one malformed row remain explicit invalid evidence, archive bytes match, and command/event counts remain zero. Receipt `0aaf6f672436c16b3dd6943821585e13d6687143541fc5e1cdd3fa45e02a10fd`. |

Empty tables, generic table names and private protected test helpers are not positive
lifecycle evidence. The three unavailable facts remain assigned to FR-08A.

## Candidate path manifest

This candidate record is excluded to avoid a recursive self-hash.

```text
c6806ec25a43b4f921501769c433cd98eacd77f6e5dcccaefd85df2f01ced6fd  foundry/docs/fr-08/h0-accepted-fr07-report.txt
0c95ee9fdcfaaf2c2d170ba7f727c0f5f574c3a530e01eb6262ccb71eef0c583  foundry/docs/fr-08/h0-boundary-review.md
a44d68288cb009db68b21d79fcdc89ae77aca3eecbab7ecdb315673d31bfdc73  foundry/lib/pramana_foundry/repair/h0_accepted_fr07_boundary.ex
ff377fd82466b49742393015bc02b2e06b38f7182c2610156e147470650757b5  foundry/test/pramana_foundry/repair/h0_accepted_fr07_boundary_test.exs
baf1dd140f819af0d85e6913ae45904a69cd96e6bfb5e1778c2800ec54dcf6c2  foundry/test/support/h0_report_fixture.exs
89e559f1833b75abed9089c3beb93d43e46b58b9ce2d65c942a2de57395f14ba  foundry/test/support/h0_identity_negative_fixture.exs
0c7df443707d245c5c61d57b084ff23972c49c880e1c2642fb4b6c46b4c99691  foundry/docs/README.md
0d6efa392267c550038c316ec12fbd122fdb52b38ac507a616539a445d33eefb  docs/CATALOG.md
710f42d0467e97f58540342ba1c566959d995f1d561242c275f88eab2017228b  foundry/lib/pramana_foundry/repair/fr08_handoff_gate.ex
513bead9e36322a0f2d09a59124fd717d2bc3a3945d065eb58e75e941bece591  foundry/test/pramana_foundry/repair/fr08_handoff_gate_test.exs
df569423c58a67452cdb93d98259615ac0996b671dccb40089de28dce8c24caf  foundry/mix.exs
bf2a61f815533a96b2abec87b1690ae49145bec56e60703a22b4db178c56e954  foundry/mix.lock
```

## Verification and limitations

Pinned Elixir 1.20.3 / OTP 29.0.5 was used with isolated build and canonical temporary
roots, `MIX_ENV=test`, `COORDINATOR_TICK=0`, and provider/runtime overrides removed.

- `mix compile --force --warnings-as-errors`: exit 0; 106 project files.
- Corrected H0 provider, separate-process regressions and unchanged gate tests at seed
  9242: exit 0; 19 passed.
- Two explicit fresh-BEAM artifact invocations plus `cmp`: exit 0; exact report digest
  `c6806ec25a43b4f921501769c433cd98eacd77f6e5dcccaefd85df2f01ced6fd`.
- Fresh-BEAM changed-loaded-Gateway negative control: exit 0;
  `identity_mismatch_refused`.
- DurableStore/public hostile suite excluding the independent VFS sync-fault file, plus
  containment, checkpoint, corrected H0 and gate tests at seed 9243: exit 0; 109 passed.
  Log SHA-256 `1a9b525d06210becdbf2033534371824b9e552c7fc124833638d4408de39c366`.

The earlier full-CI/native limitation remains separate and unchanged. Canonical CI passed
dependency, compile and format stages before the BEAM exited 139 in the VFS sync-fault
area; `sync_fault_test.exs` alone reproduced exit 139. This correction does not touch
DurableStore or that test. No green full-CI or new VFS recovery claim is made.

The candidate and blocking review are now routed from both the Foundry documentation
index and shared catalog. A renewed independent review must verify this corrected freeze
before H0 is accepted.
