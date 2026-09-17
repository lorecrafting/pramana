# Public deployment boundary

This repository publishes a pipeline, not automatic redistribution rights to every
source it can ingest. Source and translation license metadata are policy inputs;
publication requires checking the actual applicable rights and conditions.

## Separate the public dataset

A public database must contain only data intended and permitted for that public surface.
Do not rely on a search filter alone: direct URN resolution is a different route.
The implemented [publishing guard](../apps/pramana/lib/pramana/publishing/guard.ex)
and public bake/check tasks support this boundary; inspect them before deployment.
A successful metadata check is not independent legal clearance.

The following commands **create/mutate a separate target database**. Review the target
and source terms first. The database server must already provide required extensions.

```bash
PRAMANA_DATABASE=pramana_public mix ecto.create
PRAMANA_DATABASE=pramana_public mix ecto.migrate
PRAMANA_DATABASE=pramana_public mix pramana.public.bake --dry-run
# After reviewing the dry run and explicitly approving the import:
PRAMANA_DATABASE=pramana_public mix pramana.public.bake
PRAMANA_DATABASE=pramana_public mix pramana.public.check
```

The public bake is not a universal all-source ingestion command. Inspect its actual
source list and outcomes. Query embeddings and indexed coverage require their own
artifacts; an empty vector set is not a configured semantic-search deployment.

## Release configuration

From the Git root use `docker build -f pramana/Dockerfile -t pramana:local pramana`.
From `pramana/`, use `docker build -t pramana:local .`.
The [Dockerfile](../Dockerfile) builds the application release; it does not bundle the
research corpus. [runtime.exs](../config/runtime.exs) owns production configuration.
Set `DATABASE_URL` to the intended public database, provide a strong `SECRET_KEY_BASE`,
and configure host, network exposure and TLS appropriately for the hosting environment.
`PRAMANA_PUBLIC=1` enables the public-data guard during application startup.

A release without Mix has a smaller administrative surface. It is **not physically
incapable of database mutation**: database privileges, application code and credentials
remain security boundaries. Use least-privilege runtime credentials, protected admin
operations, backups, restore tests and an explicit deployment/rollback procedure.

## Acceptance is broader than build success

Run the relevant [checks](../../docs/TESTING.md) against the actual candidate and target database.
Inspect `/inventory`, source visibility, direct URN resolution, the reader and MCP
surfaces. Test query limits and capacity before exposing them. Read-only endpoints can
still consume expensive resources and are not automatically safe from abuse.

Recorded `bake_id` and `release_id` values have [specific limits](ARCHITECTURE.md#identity-and-replay).
A source lockfile alone does not back up mutable translation/index data, local-only
assets, operator configuration or database state. Preserve what a restore actually needs.

No production deployment or live licensing gate was run as part of the documentation
audit. [Historical deployment notes and price tables](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/deployment-notes.md) are
retained as a record, not a current hosting recommendation.

## Historical section bookmarks

These bookmarks open the retained pre-cleanup revision in Git history, not current instructions.
See [retired files](../../docs/RETIRED_FILES.md) for recovery and offline-access limits.

| Earlier section |
|---|
| <a id="deploying-a-public-pramāṇa"></a>[Deploying a public Pramāṇa](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/deployment-notes.md#deploying-a-public-pramāṇa) |
| <a id="the-three-properties-that-make-this-safe"></a>[The three properties that make this safe](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/deployment-notes.md#the-three-properties-that-make-this-safe) |
| <a id="one-route-to-decide-about-before-a-public-deploy--check"></a>[One route to decide about before a public deploy — `/check`](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/deployment-notes.md#one-route-to-decide-about-before-a-public-deploy--check) |
| <a id="build-it"></a>[Build it](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/deployment-notes.md#build-it) |
| <a id="what-it-costs-to-host-honestly"></a>[What it costs to host, honestly](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/deployment-notes.md#what-it-costs-to-host-honestly) |
| <a id="what-it-cannot-do-yet"></a>[What it cannot do yet](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/deployment-notes.md#what-it-cannot-do-yet) |

## Reports from an earlier retrieval release

Keep the original reply's `bake_id` and `release_id` beside each declared replay. The report
checker is read-only: it refuses a known mismatched or unavailable identity rather than
stamping, selecting history, or calling the old claim false. It also checks returned
receipts for release-bound records. Its `checked_identity` is the selection at check entry,
not an attestation of unchanged data during execution.

Do not edit a report's identity or stamp the current database merely to erase a warning.
A historical release row is not a backup. Inspect/restore the actual required inputs and
database separately, and retain the documented code/default/runtime limitations. Old
bake-only reports remain supported with a visible warning that no retrieval release was
recorded. This change has no migration, alters no historical identity rows, and requires
no Foundry operation; rolling code back loses the new report check, not stored data.
