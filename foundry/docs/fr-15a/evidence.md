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
