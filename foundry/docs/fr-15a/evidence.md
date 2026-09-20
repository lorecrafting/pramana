# FR-15aA candidate evidence

**Specification candidate:** `ca4094e2d43212c3399ab5458e9af64c40640c14`

**Tree:** `8b027b4ef29c830215461cd7e3a89df81e8f4971`

**Base:** `f5067d96d67a9ec3193a9b8bbadfa54c16525aa3`

This record binds the FR-15aA specification/validator candidate and provider-free checks.
It does not record host provisioning, principal creation, network policy, credentials,
provider/model execution, a live daemon, Herdr operation, FR-15aB isolation or FR-09
installed-harness conformance. OMP remains governing and Pi remains unselected.

## Candidate files

| SHA-256 | Path |
|---|---|
| `a3f039d0bfba79fbf5c83d0b15954d5b852371dfd6a765876ede2c2f2b62b297` | `foundry/ci/validate_fr15aa.exs` |
| `c8a0f96761d22420afb0e1090bea5de5129b68737459610d0328fd212b4e5201` | `foundry/docs/README.md` |
| `3ceecfc0bf5b4cd9de7c390cc1356334325563e4a57396a3843954057254739e` | `foundry/docs/fr-15a/provisioning-manifest.exs` |
| `e6f90482419617e58cb14bba4dde27e75d5daa21e6792bb8813c793fde35e448` | `foundry/docs/fr-15a/provisioning-specification.md` |
| `8ff186e13332bc6da9b25f8b7039fb144c2956132ccaafaabb7c21a246e39d17` | `foundry/test/pramana_foundry/repair/fr15aa_provisioning_test.exs` |

## Commands and results

Commands ran in `/private/tmp/pramana-fr15aa` unless a `cd foundry` is shown.

```text
git rev-parse HEAD
  ca4094e2d43212c3399ab5458e9af64c40640c14
git rev-parse HEAD^{tree}
  8b027b4ef29c830215461cd7e3a89df81e8f4971

cd foundry
elixir ci/validate_fr15aa.exs
  FR-15aA provisioning manifest: valid
  exit 0

mix format --check-formatted ci/validate_fr15aa.exs \
  docs/fr-15a/provisioning-manifest.exs \
  test/pramana_foundry/repair/fr15aa_provisioning_test.exs
  exit 0

MIX_ENV=test elixir -r test/test_helper.exs \
  test/pramana_foundry/repair/fr15aa_provisioning_test.exs
  seed 982154; 5 passed; exit 0

cd ..
elixir bin/check_docs.exs
  seed 136571; 80 passed; exit 0

git diff --cached --check
  no output; exit 0
```

The ordinary focused Mix command was also attempted before the dependency-free ExUnit
run:

```text
cd foundry
mix test test/pramana_foundry/repair/fr15aa_provisioning_test.exs --seed 0
  exit 1 before compilation: locked Hex packages exqlite and owl were not present
```

No dependency fetch or software installation was performed. The standalone test is valid
for this validator because it requires only repository files, Elixir and ExUnit. It proves
the complete manifest passes and four hostile mutations fail: omitted Git route, missing
network mapping, fail-open unsupported route and silent Pi selection.

## Reused provider-free useful-path evidence

No Pi/provider probe was rerun. This candidate reuses the accepted checkpoint-F evidence
at exact corrected candidate `148476c93497653abbbc52fb040cf76927478d3f`, tree
`e23217f94f295c115b893ac936c86ab719331647`, with independent PASS review
`ca8c6d0b5edc9a5cfb9c265e710b29f3210f5cbe`. Its probe SHA-256 is
`c9a91bad8417314ce3ba0080562de4574425211d4fe25d3e68447a535cd83eea`.
The probe observed Pi's direct RPC Bash run `elixir bin/check_docs.exs` with `80 passed`,
along with raw lifecycle behavior and the explicit extension/environment/FD/process/Git/
direct-bearer failures carried into this specification. That is useful raw feasibility,
not isolated build/test conformance.

## Remaining work

- FR-08A/B must implement the protected R1 claim and R5 reservation/settlement primitives
  used by the request handshake.
- FR-15aB must implement, provision under operator/root authority and test the root,
  launcher, auth, harness, presentation, fetch, slot, build and runtime principals;
  protected paths/sockets; packet-filter policy; fixed launcher; gateway/bridge/fetch
  artifacts; cleanup/quarantine; and every denial/positive probe in the specification.
- FR-09 must prove installed governing OMP request routing, subscription entitlement,
  quota/fallback/hidden-retry behavior, remote tool separation and Herdr presentation. A
  separately authorized bounded real subscription smoke remains necessary.
- Pi remains a blocked candidate. Selecting it requires actual conformance, an explicit
  FR-06/FR-09 contract revision and fresh independent review.
- Full Foundry CI was not run from this fresh worktree because its locked dependencies
  were absent and this ticket prohibited installation/acquisition. No runtime source was
  changed. The exact docs/validator/test checks above are the candidate evidence.

## B1–B3 correction candidate

The independent blocker review at
`edd22b21fe548bdf32818f78bc9119e205109a65` reproduced three bounded A-level defects.
Correction commit `5a7eb4633a0c63a12cd1bbf84c87be7ad9ef03a9`, tree
`a4110079973c4bfdd81c44257f530f77a6daf0b6`, changes only the manifest,
specification, validator and focused test:

| SHA-256 | Corrected path |
|---|---|
| `2277ad95d53a698899c71686af2303190e539737ca1a7e5e1f74279b63678dc1` | `foundry/ci/validate_fr15aa.exs` |
| `3e63d13a563fa0663b2250a4a6ad494947559e93753671101c1a67beff7a730e` | `foundry/docs/fr-15a/provisioning-manifest.exs` |
| `3348b298e12056d10af2f4c14859377d8c64c6399dab75aed2be58760fec304a` | `foundry/docs/fr-15a/provisioning-specification.md` |
| `d5408a9113eb07b6ba6b18b131cede926390aec84265df4cea1e558753f39c58` | `foundry/test/pramana_foundry/repair/fr15aa_provisioning_test.exs` |

B1 is corrected at specification level by a distinct `_pramana_kernel` principal,
blocked exact kernel artifact, protected `kernel.sock`, structured
`fr06-r3-bundle/v1` operation/forbidden-field/root-check profile, host provisioning and
rollback identity, and positive/forged/stale-epoch acceptance probes. Root still never
loads candidate kernel code. No kernel artifact or isolation was implemented.

B2 is corrected by exact validation of source/specification and host profiles, distinct
principal account/trust/login tuples, channel transport/path/server/callers, kernel
protocol, nonzero frozen pin digests and repository bytes, blocked adapter disposition,
and complete per-route executable dependencies. The seven reviewer mutations are now
maintained negative tests, including root account collapse, erased channels, unsupported
promotion, root/auth shell reassignment, missing provenance, zero digests and package-lock-
only dependencies.

B3 is corrected by separate source/specification roots, explicit user and group-name plus
numeric-ID collision checks, present/absent/unknown observer semantics, a durable
preexisting/created/modified/backup attempt ledger, and rollback limited to resources
proved newly created by that exact attempt. Pure tests retain the earlier-live/final-absent,
observer-error and ownership-contradiction cases without host mutation.

Post-commit commands and results:

```text
cd /private/tmp/pramana-fr15aa/foundry
elixir ci/validate_fr15aa.exs
  FR-15aA provisioning manifest: valid; exit 0

mix format --check-formatted ci/validate_fr15aa.exs \
  docs/fr-15a/provisioning-manifest.exs \
  test/pramana_foundry/repair/fr15aa_provisioning_test.exs
  exit 0

MIX_ENV=test elixir -r test/test_helper.exs \
  test/pramana_foundry/repair/fr15aa_provisioning_test.exs
  seed 838389; 16 passed; exit 0

cd /private/tmp/pramana-fr15aa
elixir bin/check_docs.exs
  seed 904468; 80 passed; exit 0

git diff f5067d96d67a9ec3193a9b8bbadfa54c16525aa3..HEAD --check
  no output; exit 0
```

The review reproduction script remains historical evidence for candidate `ca4094e`; its
old expectation that hostile mutations return `:ok` is deliberately not an acceptance
gate. The maintained focused tests now require those mutations to return errors. No Mix
dependency fetch, full Foundry CI, provider/model, credential read, daemon/Herdr operation,
host account, sudo/network change, provisioning, installation or deployment occurred.
FR-15aB still owns actual principal/channel/network denial and useful conformance; FR-09
still owns governing installed OMP/subscription/presentation conformance. Pi remains
unselected.
