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
    # CC's fourth switch. `commercial_use` and `redistributable` govern who may RECEIVE
    # the text; this governs what may be MADE from it, which is a different question and
    # the one a pipeline that segments, embeds and translates has to be able to ask.
    field :derivatives, :boolean, default: true

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

    has_many :vectors, Pramana.Corpus.ChunkVector

    timestamps(type: :utc_datetime_usec)
  end
end

defmodule Pramana.Corpus.ChunkVector do
  @moduledoc """
  One embedding of one chunk — of the passage itself, or of a rendering of it.

  A chunk carries several, because cross-lingual retrieval **into** Literary Chinese is
  the weakest axis of this system and a second vector in the query's own language is the
  main available mitigation. Vectors live in one table rather than one column per kind so
  that every filter, coverage count and ANN scan has a single implementation; the two
  filter bugs this project has already had both came from two paths that were supposed to
  agree and quietly did not.

  Each row carries **its own** `content` and `content_sha256`, not the chunk's. A
  translation vector's text is not in `chunks` at all, and a self-describing row is what
  lets the export/import round trip prove a vector still matches the words it was computed
  from.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  alias Pramana.Corpus.Chunk

  schema "chunk_vectors" do
    belongs_to :chunk, Chunk

    field :kind, :string
    # The language of the EMBEDDED TEXT, which for a translation is not the language of
    # the passage.
    field :lang, :string
    field :translator_id, :string

    field :content, :string
    field :content_sha256, :string

    field :embedding, Pgvector.Ecto.Vector
    field :embedding_model, :string
    # The token window the vector was produced with. A chunk longer than this was
    # embedded as a PREFIX, so two vectors of the same chunk at different windows
    # describe different amounts of text. Recorded from what the producer reports, not
    # from what this side assumes.
    field :embedding_max_length, :integer
    field :embedded_at, :utc_datetime_usec

    # Where this vector's text came from: the parallel a gloss was taken from, or the
    # model and prompt a generated one was produced by. Without it a gloss is
    # unauditable — and a gloss whose provenance cannot be checked is exactly the kind
    # of derived content this project refuses to serve.
    field :meta, :map, default: %{}

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

defmodule Pramana.Corpus.GlossaryEntry do
  @moduledoc """
  One term as a named translator glossed it in a named text.

  Evidence, not policy — `Pramana.Corpus.GlossaryTerm` is the other thing, a pinned
  rendering decision for one commentary. Each language carries its own attestation
  because most of the Sanskrit here is reconstructed rather than quoted; see the
  migration.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  alias Pramana.Corpus.Source
  alias Pramana.Corpus.Work

  schema "glossary_entries" do
    belongs_to :source, Source, type: :string
    belongs_to :work, Work, type: :string

    field :gloss_id, :string

    field :english, :string
    field :english_alternatives, {:array, :string}, default: []

    field :sanskrit, :string
    field :sanskrit_attestation, :string
    field :tibetan, :string
    field :wylie, :string
    field :tibetan_attestation, :string
    field :chinese, :string
    field :chinese_attestation, :string
    field :pali, :string

    field :definition, :string
    field :meta, :map, default: %{}

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

defmodule Pramana.Corpus.Translation do
  @moduledoc """
  One rendering of one source anchor, by one translator, in one language.

  A human translator and a model are the same kind of row here — `docs/TRANSLATION.md`
  makes multiplicity first-class rather than picking a winner, and the Chinese canon
  already forced that decision by carrying 2–6 translations of the same work.

  `anchor_urn` points at a segment: a translation is a layer, never a document, and is
  addressed as `<anchor>#tr:<lang>/<translator_id>`. See `Pramana.Translations`.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "translations" do
    field :anchor_urn, :string
    field :work_id, :string
    field :lang, :string

    field :translator_id, :string
    field :translator_name, :string
    field :tier, :string
    field :method, :string

    field :text, :string
    field :text_sha256, :string

    field :model_id, :string
    field :prompt_version, :string
    field :glossary_id, :string
    field :bake_id, :string

    field :review_state, :string, default: "raw"
    field :glossary_compliance, :float
    field :consensus_score, :float
    field :confidence, :float

    field :license_spdx, :string
    field :license_class, :string
    field :redistributable, :boolean, default: false
    field :attribution, :string

    field :source_file, :string
    field :meta, :map, default: %{}

    timestamps(type: :utc_datetime_usec)
  end
end

defmodule Pramana.Corpus.ReadingException do
  @moduledoc """
  A form whose Buddhist reading differs from its ordinary one.

  Readings are computed at render time, not stored per character; only the exceptions
  live here. 般若 is *bōrě* rather than *bānruò*, and a general pinyin library will get
  it confidently wrong in exactly the passages a reader most wants help with.

  A row with `status: "unverified"` and a null `reading` is meaningful: it records that
  the ordinary reading is wrong without inventing a replacement.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "reading_exceptions" do
    field :form, :string
    field :lang, :string
    field :scheme, :string
    field :reading, :string
    field :note, :string
    field :status, :string, default: "unverified"
    field :authority, :string
    field :source_id, :string

    timestamps(type: :utc_datetime_usec)
  end
end

defmodule Pramana.Corpus.CharacterReading do
  @moduledoc """
  What a character is read as on its own, and what it is ever read as.

  `reading` is Unihan's commonest reading — for 佛 that is *fú*, which is why a
  per-character renderer calls the Buddha *fú* through half a million occurrences.
  `attested` is every reading Unihan records for the character anywhere, and a reading
  asserted for any form must appear in it. The Buddhist readings are already in Unicode;
  what needs saying is which one applies where.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:character, :string, []}
  schema "character_readings" do
    field :reading, :string
    field :attested, {:array, :string}, default: []
    field :authority, :string

    timestamps(type: :utc_datetime_usec)
  end
end

defmodule Pramana.Corpus.Quotation do
  @moduledoc """
  One verbatim reuse: the same run of characters in two different works.

  Deliberately two ends rather than a source and a target. Identical characters say
  nothing about who quoted whom — that is a judgement about dates and transmission, and
  the scan cannot make it. See `Pramana.Quotations`.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  alias Pramana.Corpus.Text

  schema "quotations" do
    field :text, :string
    field :text_sha256, :string
    field :length, :integer

    belongs_to :a_text, Text
    field :a_work_id, :string
    field :a_urn, :string
    field :a_char_start, :integer
    field :a_char_end, :integer

    belongs_to :b_text, Text
    field :b_work_id, :string
    field :b_urn, :string
    field :b_char_start, :integer
    field :b_char_end, :integer

    field :bake_id, :string
    field :meta, :map, default: %{}

    timestamps(type: :utc_datetime_usec)
  end
end
