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
the admission server therefore preserves active capacity: the replacement binds to the
same permit-supervisor process and counts the same live permit children before admitting
more work. If a coordinator dies, its permit exits automatically. `CheckRun` separately
monitors its permit and stops remaining report work if that permit disappears.

The permit-supervisor **generation is pinned** for the application lifetime. It is a
temporary supervision child rather than an automatically replaced capacity pool. If it
fails, its permit children disappear, admitted `CheckRun` coordinators observe permit
loss and clean up their workers, and `CheckAdmission` refuses subsequent admission as
unavailable. It does not bind to a fresh empty supervisor while old work is still
stopping. Recovery from this degraded state is a coordinated application restart.

`CheckRun` releases its permit only after the owned verification/repair worker has been
stopped and observed. A cancellation request, timeout decision or repair failure does not
make capacity available before worker cleanup.

## Refusal semantics and limits

MCP capacity refusal returns `report_check_busy` and no report verdict. The reader shows
a `busy` execution state saying that verification did not start; it preserves the pasted
report for an explicit retry. Neither path invokes verification or repair when refused.
There is no automatic retry.

The bound applies only to report checks on one BEAM node. It does not bound Anubis session
queueing, other MCP/search tools, independent nodes, JSON/network latency, or already-
dispatched PostgreSQL/native work. A permit is resource accounting, not evidence that a
report is correct. Existing report deadlines, evidence states and release-identity rules
remain separate.

Both normal web serving and `mix pramana.mcp.stdio` start the `pramana_web` application,
so the reader, Streamable HTTP MCP and stdio MCP use the same admission implementation
within their respective BEAM node. Separate BEAM nodes still have separate pools.

Rollback removes the admission children and returns to per-call deadline protection only;
it requires no schema/data conversion. Do not describe rollback as restoring historical
corpus state or cancelling work already dispatched outside the BEAM worker.
