# Report-check admission

`PramanaWeb.CheckAdmission` is the node-local capacity boundary shared by the `/check`
reader and MCP `verify_report`. It limits how many report verification/repair workers may
run concurrently on one BEAM node; it is not a distributed semaphore or a queue.

The default capacity is four. Trusted application configuration may choose another value
from 1 through 64:

```elixir
config :pramana_web, PramanaWeb.CheckAdmission, max_active: 4
```

Unknown keys, non-keyword configuration and invalid values fail startup. Client/report
arguments cannot alter this policy.

## Lease lifecycle

Admission is represented by supervised permit processes, one per admitted coordinator.
The admission server serializes capacity decisions and starts a temporary permit under a
separate `DynamicSupervisor`. A new permit begins pending: it monitors both the requesting
coordinator and the admission server and must be activated by the requester. If the reply
is lost, the admission server dies before activation, the requester dies, or activation
never arrives within the bounded handshake, the permit terminates without becoming a
long-lived leaked reservation.

After activation, the permit no longer depends on the admission server. Restarting only
the admission server therefore preserves active capacity: the replacement counts the same
live permit children before admitting more work. If a coordinator dies, its permit exits
automatically. `CheckRun` separately monitors its permit; loss of the permit supervisor is
an execution failure and remaining report work is stopped rather than continuing outside
the capacity accounting.

`CheckRun` releases its permit only after the owned verification/repair worker has been
stopped and observed. A cancellation request, timeout decision or repair failure does not
make capacity available before worker cleanup.

## Refusal semantics and limits

MCP capacity refusal returns `report_check_busy` and no report verdict. The reader keeps
its existing execution-state vocabulary and reports saturation as an execution error with
no verification result. Neither path invokes verification or repair when it was refused.
There is no automatic retry.

The bound applies only to report checks on one BEAM node. It does not bound Anubis session
queueing, other MCP/search tools, independent nodes, JSON/network latency, or already-
dispatched PostgreSQL/native work. A permit is resource accounting, not evidence that a
report is correct. Existing report deadlines, evidence states and release-identity rules
remain separate.

Rollback removes the admission children and returns to per-call deadline protection only;
it requires no schema/data conversion. Do not describe rollback as restoring historical
corpus state or cancelling work already dispatched outside the BEAM worker.
