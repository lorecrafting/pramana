# FR-02 candidate v2 — narrow independent recheck

Verdict: **PASS.** Candidate v2 resolves both blockers from the v1 review. Duplicate
JSON object keys are rejected before map collapse, including decoded-equivalent escaped
spellings and keys nested inside objects or arrays. `ticket unblock` is no longer an
accepted transport shape and the candidate no longer depends on the dirty CLI/Coordinator
feature. No new blocker was found in the frozen four-file scope.

Reviewer: `/root/fr02_v2_review`, independent of implementer
`/root/fr02_investigate`. Reviewed 2026-09-12. No candidate source or test file was
edited; this review artifact is the only write.

## Candidate identity

Base and observed HEAD: `7aecf31c541ab1b1f3de4045ac3c487f6ef0708f`.
SHA-256 values matched the frozen v2 implementation log before and after verification,
relative to `foundry/`:

| File | SHA-256 |
|---|---|
| `bin/pramana` | `c1c92fe1c25402d67e0ce6173e196e640e71b47c528878bb164f0318c83e5250` |
| `lib/pramana_foundry/cli/rpc.ex` | `617fb1dc018a70abb9ffd7f97bc7e886db6d217c16ae06ea15ef233d5829b11d` |
| `test/pramana_foundry/cli/rpc_test.exs` | `083f11bf59e6f3954e168d8f939c0fe9aa8fbb165e59daf66894d7b95d366617` |
| `test/pramana_foundry/rpc_wrapper_test.exs` | `77ccefd68a73ac180723591fbaf3c0075e7c9f8bcb5716061c05c8259ee6e761` |

The v1 review SHA-256 was also confirmed as
`911baf8618cc3853268e383b302bb9dc009e2a33460e0e89e0e126af7ba15340`.

## Prior blockers

### R1 — resolved: duplicate JSON members reject before dispatch

`decode_json/1` uses OTP `:json.decode/3` object callbacks. Every object start creates
its own `{map, seen_keys}` accumulator. `json_object_push/3` tests the decoded binary key
against that object's key set before `Map.put/3`, and throws the private exact tag
`{PramanaFoundry.CLI.RPC, :duplicate_json_key}` on repetition. `decode_json/1` catches
only that throw as `:duplicate_json_key`; decoder errors remain `:invalid_json`.

The callback accumulator is total for the relevant JSON nesting forms. OTP saves the
parent accumulator on its parser stack before `object_start`; `object_finish` returns
the completed map together with that exact saved accumulator. Default array callbacks
likewise return to the surrounding object accumulator. Empty objects, nested objects,
objects inside arrays and arrays inside objects therefore neither lose parent keys nor
share a sibling's seen-key set. Because duplicate comparison happens after JSON string
decoding, `"argv"` and `"\u0061rgv"`, for example, compare as the same binary.

Committed regressions cover duplicate `version` and `argv` in both orders,
escaped-equivalent spellings, nested objects and objects in arrays. Independent probes
additionally checked escaped slash equivalence, deeply nested array/object combinations,
duplicates whose values are empty composites, unique nested composites, a root array,
and malformed nested JSON. Every duplicate returned
`{:error, :duplicate_json_key}`; unique but invalid envelopes reached
`:invalid_envelope`; malformed syntax reached `:invalid_json`. A recorder-backed
`RPC.run/1` probe confirmed rejection occurs with no dispatch.

### R2 — resolved: `ticket unblock` removed from the supported grammar

The only accepted ticket forms are `create`, `status`, `list`, and `integrate`, matching
the exact base CLI. `ticket unblock TASK-1` is now a committed negative case. An
independent `RPC.run/1` probe returned `unknown_command_shape` and left its dispatch
recorder unset. Compiling the CLI directly from base
`7aecf31c541ab1b1f3de4045ac3c487f6ef0708f` independently confirmed that the clean-base
CLI reports `unblock` as unknown and raises `usage error`.

## Regression conclusions

- The source-injection correction remains intact. The shell passes original arguments
  as `"$@"` after Elixir's `--`; the encoder reads `System.argv/0`, emits JSON and
  canonical unpadded URL-safe base64, and inserts only that restricted alphabet into the
  fixed `PramanaFoundry.CLI.RPC.run("TOKEN")` expression. Decoded strings are validated
  as data and dispatched without atom or source construction.
- Actual-wrapper tests still cover quotes, apostrophes, backslashes, newlines, empty
  values, literal interpolation syntax, shell-looking text, Unicode and a 60,000-byte
  title. The focused suite also retains evaluated-wrapper dispatch and server-side
  rejection coverage, so the v2 decoder change did not regress literal argv transport.
- Release stdout and stderr remain byte-preserved and status 42 remains status 42.
  Oversized encoder input returns 64 before release invocation; invalid release override
  returns 69; missing and unexecutable Elixir return 127 and 126. Command errors are not
  relabeled as daemon connection failures.
- Runtime encoding, decoding, validation and duplicate detection are Elixir/OTP only.
  No Python runtime or new dependency appears in the frozen candidate. Shell remains the
  existing wrapper boundary, and test-only shell fixtures exercise that boundary.

## Verification

All commands ran from `foundry/` and exited zero unless a probe explicitly asserted a
rejection status:

```sh
MIX_ENV=test mise exec -- mix compile --force --warnings-as-errors
# compiled 72 files

COORDINATOR_TICK=0 HERDR_ENV=0 MIX_ENV=test mise exec -- mix test --no-start \
  test/pramana_foundry/cli/rpc_test.exs \
  test/pramana_foundry/rpc_wrapper_test.exs \
  test/pramana_foundry/cli_test.exs --seed 12092026
# 62 passed

bash -n bin/pramana

mise exec -- mix format --check-formatted \
  lib/pramana_foundry/cli/rpc.ex \
  test/pramana_foundry/cli/rpc_test.exs \
  test/pramana_foundry/rpc_wrapper_test.exs

git diff --check -- bin/pramana lib/pramana_foundry/cli/rpc.ex \
  test/pramana_foundry/cli/rpc_test.exs \
  test/pramana_foundry/rpc_wrapper_test.exs
```

A separate trailing-whitespace scan covered the three untracked Elixir/test files,
which `git diff --check` cannot inspect. Shell syntax, formatting, whitespace, compile,
focused tests, clean-base command comparison, adversarial decoder probes and final hashes
all passed.

## Limitations and deferred authority work

- This PASS is for FR-02's temporary inert argument transport, not for a general secure
  remote-control protocol. The release's general `rpc` command still carries arbitrary
  evaluation authority. Authentication, authorization, credential/network isolation and
  replacement with a scoped local protocol remain FR-15a obligations; this review neither
  implements nor accepts them.
- Equivalent dynamic construction in `tickets_from_review.sh` and
  `test_daemon_recovery.sh` remains routed to FR-03/04/05 as documented. Those entry
  points do not pass through this wrapper and were not executed. This PASS is not a
  project-wide claim about every RPC or script entry point.
- No daemon, provider, credentials, deployment, paid execution or destructive recovery
  path was used. Tests use a fake release and isolated local Elixir evaluation, not a live
  distributed node. Real daemon connectivity and remote exception presentation remain
  unmeasured here.
- Compile and tests used the shared dirty worktree. The four candidate hashes were frozen
  and rechecked, and the exact-base CLI source isolated R2, but this was not a detached
  clean-tree release build or full lifecycle acceptance run.
