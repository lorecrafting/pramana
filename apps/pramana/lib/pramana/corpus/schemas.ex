defmodule Pramana.Corpus.Source do
  @moduledoc "A pinned upstream corpus source and its license class."
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:id, :string, autogenerate: false}
  schema "sources" do
    field :name, :string
    field :upstream_url, :string
    field :pin_type, :string, default: "git"
    field :pin_ref, :string
    field :retrieved_at, :utc_datetime_usec
    field :files_sha256, :string
    field :file_count, :integer
    field :license_spdx, :string
    field :license_class, :string, default: "unknown"
    field :commercial_use, :boolean, default: false
    field :redistributable, :boolean, default: false

    timestamps(type: :utc_datetime_usec)
  end
end

defmodule Pramana.Corpus.Witness do
  @moduledoc "A physical or printed edition (Taishō, Koryŏ, Derge, ...)."
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:id, :string, autogenerate: false}
  schema "witnesses" do
    field :name, :string
    field :description, :string
    timestamps(type: :utc_datetime_usec)
  end
end

defmodule Pramana.Corpus.Work do
  @moduledoc """
  The abstract text, carrying the provenance axes.

  Provenance is several orthogonal columns, never a single `source` string — that is
  what makes "exclude Japanese-composed commentary" a SQL predicate rather than a
  heuristic. See `docs/ARCHITECTURE.md`, "The provenance model".
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:id, :string, autogenerate: false}
  schema "works" do
    field :title, :string
    field :title_original, :string

    field :composition_origin, :string
    field :text_role, :string
    field :division, :string
    field :division_en, :string
    field :attributed_author, :string
    field :attribution_confidence, :string
    field :date_start, :integer
    field :date_end, :integer

    field :meta, :map, default: %{}
    timestamps(type: :utc_datetime_usec)
  end
end

defmodule Pramana.Corpus.Text do
  @moduledoc "A work as it appears in one witness, from one source."
  use Ecto.Schema

  @type t :: %__MODULE__{}

  alias Pramana.Corpus.Source
  alias Pramana.Corpus.Witness
  alias Pramana.Corpus.Work

  schema "texts" do
    belongs_to :work, Work, type: :string
    belongs_to :witness, Witness, type: :string
    belongs_to :source, Source, type: :string

    field :urn_prefix, :string
    field :volume, :string
    field :body, :string
    field :body_sha256, :string
    field :meta, :map, default: %{}
    field :outline, :map, default: %{}

    has_many :segments, Pramana.Corpus.Segment

    timestamps(type: :utc_datetime_usec)
  end
end

defmodule Pramana.Corpus.Segment do
  @moduledoc """
  The citable atom: one edition-anchored span, addressable by URN.

  `char_start`/`char_end` are offsets into `texts.body`, and `content_sha256` covers
  `content`. Together they let any citation be re-resolved and byte-compared without
  trusting the model that produced it (`CLAUDE.md` invariant #1).
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  alias Pramana.Corpus.Text

  schema "segments" do
    belongs_to :text, Text

    field :urn, :string
    field :juan, :integer
    field :page, :string
    field :register, :string
    field :line, :integer
    field :ordinal, :integer
    field :kind, :string, default: "prose"
    field :content, :string
    field :content_sha256, :string
    field :char_start, :integer
    field :char_end, :integer
    field :byte_start, :integer
    field :byte_end, :integer
    field :meta, :map, default: %{}

    timestamps(type: :utc_datetime_usec)
  end
end

defmodule Pramana.Corpus.Bake do
  @moduledoc "An immutable corpus snapshot: sha256(lockfile + pipeline version + config)."
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:id, :string, autogenerate: false}
  schema "bakes" do
    field :pipeline_version, :string
    field :sources_lock_sha256, :string
    field :config, :map, default: %{}
    field :built_at, :utc_datetime_usec
    field :stats, :map, default: %{}
    timestamps(type: :utc_datetime_usec)
  end
end

defmodule Pramana.Corpus.Chunk do
  @moduledoc """
  A retrieval chunk: a window over consecutive segments, and the unit that gets
  embedded.

  Segments are printed lines averaging 18 characters, which is too small and too
  typographic to embed meaningfully. A chunk's `urn` is a RANGE of real citation
  anchors, so a semantic hit stays verifiable by the same guard as a direct lookup.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  alias Pramana.Corpus.Text

  schema "chunks" do
    belongs_to :text, Text

    field :urn, :string
    field :first_ordinal, :integer
    field :last_ordinal, :integer
    field :segment_count, :integer
    field :juan, :integer
    field :content, :string
    field :content_sha256, :string
    field :char_start, :integer
    field :char_end, :integer
    field :byte_start, :integer
    field :byte_end, :integer

    field :embedding, Pgvector.Ecto.Vector
    field :embedding_model, :string
    field :embedded_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end
end

defmodule Pramana.Corpus.WorkRelation do
  @moduledoc """
  A typed, directional claim that one work explains, translates or quotes another.

  `method` and `confidence` are part of the claim, not metadata about it: a catalogue
  assertion and an LLM inference are different evidence and must stay distinguishable all
  the way into an answer (`CLAUDE.md` invariant #5). See `Pramana.Relations`.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  alias Pramana.Corpus.Work

  schema "work_relations" do
    belongs_to :source_work, Work, type: :string
    belongs_to :target_work, Work, type: :string

    # A target that is not (yet) in the corpus. A manifest may assert that a commentary
    # explains a work we have not ingested, and dropping the assertion until then would
    # lose real information.
    field :target_work_ref, :string

    field :relation, :string
    field :scope, :string, default: "whole_work"
    field :target_urn, :string
    field :confidence, :string, default: "asserted"
    field :method, :string
    field :evidence, :map, default: %{}

    timestamps(type: :utc_datetime_usec)
  end

  @fields ~w(source_work_id target_work_id target_work_ref relation scope target_urn
             confidence method evidence)a

  @doc false
  def changeset(relation, attrs) do
    relation
    |> cast(attrs, @fields)
    |> validate_required([:source_work_id, :relation, :method])
    |> check_constraint(:relation, name: :work_relations_relation_known)
    |> check_constraint(:scope, name: :work_relations_scope_known)
    |> check_constraint(:confidence, name: :work_relations_confidence_known)
    |> check_constraint(:method, name: :work_relations_method_known)
    |> check_constraint(:target_work_id, name: :work_relations_has_target)
    |> check_constraint(:target_urn, name: :work_relations_passage_needs_urn)
    |> check_constraint(:source_work_id, name: :work_relations_no_self_reference)
  end
end

defmodule Pramana.Corpus.GlossaryTerm do
  @moduledoc """
  One pinned term rendering.

  `notes` is verbatim because the reasoning is the valuable part, `rejected_forms`
  because a decision recorded is not a decision applied, and `reading_status` because a
  reading that could not be verified must be representable rather than silently absent.
  See `Pramana.Glossary`.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  alias Pramana.Corpus.Source

  schema "glossary_terms" do
    belongs_to :source, Source, type: :string

    field :term, :string
    field :pinyin, :string
    field :canonical_english, :string
    field :notes, :string
    field :category, :string
    field :rejected_forms, {:array, :string}, default: []
    field :reading_status, :string, default: "not_applicable"
    field :language_origin, :string

    timestamps(type: :utc_datetime_usec)
  end
end

defmodule Pramana.Corpus.TextAnchor do
  @moduledoc """
  A SuttaCentral text id resolved to the Taishō passage it names.

  Their `volpage` — "T ii 001a06" — is the same coordinate system our URNs use, so
  `sa1` is not merely related to something in our corpus, it *is* a passage in it.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:uid, :string, autogenerate: false}
  schema "text_anchors" do
    field :work_id, :string
    field :urn, :string
    field :acronym, :string
    field :volpage, :string

    timestamps(type: :utc_datetime_usec)
  end
end

defmodule Pramana.Corpus.TextParallel do
  @moduledoc """
  One hand-curated parallel between two texts, at SuttaCentral's own ids.

  `relation` is a claim about strength — a `full` parallel and a passing `mentions` are
  not the same evidence — and is never flattened into "related". See `Pramana.Parallels`.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "text_parallels" do
    field :source_uid, :string
    field :target_uid, :string
    field :relation, :string
    field :partial, :boolean, default: false
    field :source_urn, :string
    field :target_urn, :string
    field :source_work_id, :string
    field :target_work_id, :string

    timestamps(type: :utc_datetime_usec)
  end
end
