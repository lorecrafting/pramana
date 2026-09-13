# FR-02 candidate v1 — independent authority-boundary review

Verdict: **FAIL — two bounded validation/contract blockers.** The original
argument-to-Elixir-source injection is fixed by this candidate. The failures below
do not demonstrate renewed source execution; they prevent accepting the stronger
claim of an exact envelope and a command allowlist matching the frozen base.

Reviewer: `/root/fr02_review`, independent of implementer
`/root/fr02_investigate`. Reviewed 2026-09-12. No candidate file was edited.

## Candidate identity

Base and observed HEAD: `7aecf31c541ab1b1f3de4045ac3c487f6ef0708f`.
SHA-256 values checked before and after verification, relative to `foundry/`:

| File | SHA-256 |
|---|---|
| `bin/pramana` | `e836621bc5d92c152f7eed2f3c00a4fb93d30b55460955abdc953704a3383e54` |
| `lib/pramana_foundry/cli/rpc.ex` | `eec9bec3224207dec43df31fcc0620aae2f071572305c6b37f119bf9d7df4c59` |
| `test/pramana_foundry/cli/rpc_test.exs` | `7bb444196993fa00af64393045b9f22ca3873f17815706c6a9566ba3f94520e5` |
| `test/pramana_foundry/rpc_wrapper_test.exs` | `5b596d76f71764df51526d7418ca1de8c9c173c9e409987f5e81b3afe40ee26f` |

Reviewed AGENTS.md, coding conventions, Rules 4/8/57/63/66, FR-02 acceptance,
WORKFLOW-CONTRACT revision 3, audit F06, the frozen implementation log, wrapper,
decoder, tests, current CLI, and the base CLI. The shared worktree has unrelated
dirty CLI/Coordinator changes; these are not part of this four-file candidate.

## Blockers

### R1 — Duplicate envelope members are accepted, not rejected

`CLI.RPC.decode_json/1` at lines 79–82 uses `:json.decode/1`, which keeps the
first duplicate object member on this pinned runtime. The later `Map.keys/1`
check at lines 85–90 cannot recover the lost members. Both inputs below return
`{:ok, ["ticket", "list"]}` after canonical base64 encoding:

```json
{"version":1,"version":2,"argv":["ticket","list"]}
{"version":1,"argv":["ticket","list"],"argv":["unknown"]}
```

Reversing these duplicate members changes the result to `:invalid_envelope` or
`:unknown_command_shape`. Thus contradictory versions and multiple command arrays
can be accepted according to parser precedence, despite the exact-envelope claim.
This is a malformed-envelope validation defect, not an injection exploit or a
claim that the current wrapper encoder emits duplicate keys. Unique schema keys
are also explicit in the workflow contract's command-encoding rules.

Required correction: reject duplicate JSON object members before they are
collapsed, including equivalent escaped member spellings, and add regression
cases for both duplicate orders. Full future command-protocol implementation or
a canonical JSON serializer is not required to close this issue.

### R2 — The allowlist claims a command absent from the frozen base

`CLI.RPC.validate_command_shape/1` line 130 allows `ticket unblock TASK_ID`, and
the decoder test asserts it is supported. The base CLI has no unblock handler;
it raises `usage error` through its unknown-ticket clause. Only the unrelated
dirty CLI/Coordinator changes implement this operation.

An isolated probe compiled the exact base CLI source from `git show`, then
called this candidate's decoder and dispatcher. Observed:

```text
unblock decode: {:ok, ["ticket", "unblock", "TASK-1"]}
Unknown ticket command: unblock
Available: create, status, list, integrate
unblock dispatch on base: "usage error"
```

Required correction: remove this command from the FR-02 supported allowlist and
positive test until its implementation is an accepted prerequisite, or explicitly
change/review the candidate dependency. Do not absorb the user's dirty feature
implicitly. This is a clean-base command-contract defect; rejection downstream
means it does not introduce an execution bypass.

## Boundary findings that passed

- Shell passes original arguments as `"$@"` after Elixir's `--`. User text is read
  by `System.argv/0`, not interpolated into the encoder program. The fixed encoder
  generates JSON and unpadded URL-safe base64. The resulting alphabet contains no
  quote, backslash, interpolation marker, or shell metacharacter that can escape
  the fixed RPC string. Shell parameter expansion does not recursively execute
  payload content. The release executable and RPC expression are quoted arguments.
- The daemon verifies the encoded alphabet, encoded size, successful decode and
  canonical re-encoding, then decoded size, raw UTF-8, JSON, envelope, string argv,
  NUL exclusion and command shape before `CLI.main/1`. No atoms or source code are
  constructed from decoded arguments.
- Apart from R2, the remote handoff/review/ticket forms agree with the base CLI.
  Ticket creation restricts priorities and optional pairs to `--scope` and
  `--acceptance`, with no duplicates or incomplete pairs. Unknown commands,
  options and excess arity are rejected. `handoff block --reason` consumes the
  remaining nonempty argv tail as reason text, matching the CLI's existing
  variadic grammar; option-looking words there are data, not ignored switches.
  Semantic task-ID/path/artifact checks remain the CLI's responsibility.
- Actual-wrapper tests run `bin/pramana`; they are not helper-only. Successful
  transport tests capture its release expression and decode the token; malformed
  command tests execute that expression in an isolated Elixir process. An
  additional independent probe executed captured expressions through the real
  `RPC.run/1` and a harmless CLI dispatch recorder, checking exact argv equality.
- Quotes, apostrophes, backslashes, embedded/trailing newlines, empty values,
  literal `#{1+1}`, `$()`, backticks, shell operators, Unicode/combining characters,
  and a 60,000-byte title remained literal through the wrapper and evaluated RPC.
- Measured decoded byte limits: 65,535 and 65,536 accepted; 65,537 rejected.
  Encoded lengths were respectively 87,380, 87,382 and 87,383. Noncanonical pad
  bits (`Zh`), padding/alphabet errors, raw invalid UTF-8, lone surrogate escapes,
  escaped NUL, trailing JSON, unsupported/float versions and unknown fields reject.
  A valid surrogate pair decodes to the expected Unicode string.
- The wrapper preserves release stdout and stderr byte-for-byte and status 42
  in the independent test rerun. It does not relabel command failures as daemon
  connection failures. Oversized input returns 64 before release invocation;
  explicit missing/unexecutable release override returns 69; missing and
  unexecutable encoders return 127 and 126 without invoking the release.
- Candidate runtime/codec and regression tests use Elixir, with the existing
  shell boundary/fixtures retained. No Python dependency was added.

## Re-run commands and results

Commands ran from `foundry/`; all statuses below are actual process exit statuses.
No Foundry application was started by the focused test command.

```sh
MIX_ENV=test mise exec -- mix compile --force --warnings-as-errors
# exit 0; compiled 72 files, generated pramana_foundry app

COORDINATOR_TICK=0 HERDR_ENV=0 MIX_ENV=test mise exec -- mix test --no-start \
  test/pramana_foundry/cli/rpc_test.exs \
  test/pramana_foundry/rpc_wrapper_test.exs \
  test/pramana_foundry/cli_test.exs --seed 12092026
# exit 0; 59 passed, 4.4 seconds

bash -n bin/pramana
# exit 0

git diff --check -- bin/pramana lib/pramana_foundry/cli/rpc.ex \
  test/pramana_foundry/cli/rpc_test.exs test/pramana_foundry/rpc_wrapper_test.exs
# exit 0; note git diff does not inspect untracked file content

mise exec -- mix format --check-formatted lib/pramana_foundry/cli/rpc.ex \
  test/pramana_foundry/cli/rpc_test.exs test/pramana_foundry/rpc_wrapper_test.exs
# exit 0; explicitly includes the new files
```

Independent one-off probes used `mise exec -- elixir -pa
_build/test/lib/pramana_foundry/ebin -e '…'`, without app startup. Reproduction of
R1 and R2 (Elixir body; shell-quote as one literal argument):

```elixir
enc = fn raw -> Base.url_encode64(raw, padding: false) end
for raw <- [
  ~S({"version":1,"version":2,"argv":["ticket","list"]}),
  ~S({"version":1,"argv":["ticket","list"],"argv":["unknown"]})
] do
  IO.inspect(PramanaFoundry.CLI.RPC.decode(enc.(raw)))
end
{source, 0} = System.cmd("git", ["show",
  "7aecf31c541ab1b1f3de4045ac3c487f6ef0708f:foundry/lib/pramana_foundry/cli.ex"])
Code.compiler_options(ignore_module_conflict: true)
Code.compile_string(source)
token = enc.(~S({"version":1,"argv":["ticket","unblock","TASK-1"]}))
IO.inspect(PramanaFoundry.CLI.RPC.decode(token))
try do
  PramanaFoundry.CLI.RPC.run(token)
rescue
  error -> IO.inspect(Exception.message(error))
end
```

For the extra successful-dispatch probe, a separate ephemeral VM replaced
`CLI.main(argv)` with `Process.put(:review_received_argv, argv)`. It called the
actual wrapper using `System.cmd/3` with `PRAMANA_RELEASE=/bin/echo`, checked the
entire output against the fixed `rpc PramanaFoundry.CLI.RPC.run("TOKEN")` grammar,
evaluated that expression, and matched the recorded argv exactly against each
input listed above. All six cases passed; the process exited 0. This tests actual
shell transport and expression evaluation, not BEAM distribution or live mutation.

## Deferred work, equivalent entry points and limits

- General release `rpc` remains arbitrary evaluation authority. FR-15a explicitly
  owns replacing it with the authenticated scoped protocol; this candidate does
  not claim authorization, credential isolation or network confinement.
- Source audit of `foundry/bin`, `foundry/lib`, `foundry/rel` and repository `bin`
  found dynamic Elixir construction in `tickets_from_review.sh` and
  `test_daemon_recovery.sh`. These scripts bypass `bin/pramana`, and the wrapper
  never delegates to them. Their fixed/derived variables, direct coordinator
  calls, lifecycle/acceptance bypasses and destructive cleanup remain assigned
  to FR-03/04/05 in the implementation log. They were inspected, not executed.
  This deferral does not reopen the repaired wrapper path, but it prevents any
  project-wide claim that all executable entry points are safe.
- `integration/pipeline.ex` deliberately runs configured check strings via
  `sh -c`; the repaired wrapper does not turn its title/reason into those commands.
  Protected check/activation authority belongs to FR-13/15a and related gates.
- No daemon, provider, credentials, paid work, release deployment or destructive
  recovery script was used. Tests exercise a fake release and local Elixir
  evaluation, not a live distributed RPC connection. Real release connection and
  remote runtime exception formatting were not independently measured here;
  propagation of an executable's actual bytes/status was measured.
- Compile/tests use the shared worktree. The exact-base CLI probe isolates the
  identified dirty-feature dependency, but this review is not a full clean-tree
  release build or full lifecycle acceptance run.

Suggestions after the blockers: keep the independent duplicate/member-order,
exact-limit and successful evaluated-dispatch cases as permanent regression tests.
No larger architectural change is needed for this review's corrections.
