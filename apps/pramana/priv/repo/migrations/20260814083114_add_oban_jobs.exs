defmodule Pramana.Repo.Migrations.AddObanJobs do
  use Ecto.Migration

  @moduledoc """
  Oban's job table.

  The bake is a finite set of ~5,000 files, so what we need is durability and
  resumability, not stream backpressure: a bake that dies at file 4,000 must resume at
  4,000, and one malformed TEI file must fail one job rather than the run.

  Note the roadmap said "Broadway + Oban". Broadway earns its place when a slow stage
  must exert backpressure on an upstream *stream*; here the input is a known static
  list. Oban alone is the right tool. Broadway may return for the Phase 1 embedding
  stage, where a slow sidecar genuinely needs to throttle producers.
  """

  def up, do: Oban.Migration.up(version: 14)
  def down, do: Oban.Migration.down(version: 1)
end
