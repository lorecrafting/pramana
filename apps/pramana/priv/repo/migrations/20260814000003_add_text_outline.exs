defmodule Pramana.Repo.Migrations.AddTextOutline do
  use Ecto.Migration

  @moduledoc """
  A text's table of contents.

  CBETA ships one in `<cb:mulu>` — for T0262 that is 40 entries: 28 品 chapters,
  7 卷 fascicles, and 2 prefaces, each resolvable to a line anchor. The normalizer
  previously discarded these as navigation apparatus, which was correct for *body
  text* and wrong overall: an outline is what lets a caller survey a work's structure
  without pulling its text, which matters because the full canon has millions of
  segments and no context window holds one.

  Stored as jsonb on the text rather than its own table: an outline is tens of entries,
  always read whole, and never joined against.
  """

  def change do
    alter table(:texts) do
      add :outline, :map, null: false, default: %{}
    end
  end
end
