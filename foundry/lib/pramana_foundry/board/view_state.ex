defmodule PramanaFoundry.Board.ViewState do
  @moduledoc """
  Durable view state and pure functional navigation for PramanaFoundry.Board.
  Maintains active column, selected cards per column, detail view expansion,
  scroll offsets, and terminal dimensions.
  """

  alias PramanaFoundry.Board.View

  @columns View.columns()

  defstruct active_column: 0,
            selected_rows: %{0 => 0, 1 => 0, 2 => 0, 3 => 0, 4 => 0, 5 => 0, 6 => 0, 7 => 0},
            detail_task_id: nil,
            detail_scroll_offset: 0,
            width: 120,
            height: 30,
            quit?: false

  @type t :: %__MODULE__{
          active_column: non_neg_integer(),
          selected_rows: %{non_neg_integer() => non_neg_integer()},
          detail_task_id: String.t() | nil,
          detail_scroll_offset: non_neg_integer(),
          width: pos_integer(),
          height: pos_integer(),
          quit?: boolean()
        }

  @doc """
  Initializes a new ViewState.
  """
  def new(opts \\ []) do
    %__MODULE__{
      active_column: Keyword.get(opts, :active_column, 0),
      width: Keyword.get(opts, :width, 120),
      height: Keyword.get(opts, :height, 30)
    }
  end

  @doc """
  Returns the canonical columns.
  """
  def columns, do: @columns

  @doc """
  Resizes the view state dimensions.
  """
  def resize(%__MODULE__{} = state, width, height) do
    %__MODULE__{state | width: max(30, width), height: max(8, height)}
  end

  @doc """
  Handles a key event and returns {:ok, updated_state} or {:quit, updated_state}.
  """
  def handle_key(%__MODULE__{} = state, key, data \\ %{}) do
    case key do
      # Navigation: Left
      k when k in [:left, "h", "H", "\e[D"] ->
        {:ok, move_column(state, -1)}

      # Navigation: Right
      k when k in [:right, "l", "L", "\e[C"] ->
        {:ok, move_column(state, 1)}

      # Navigation: Up
      k when k in [:up, "k", "K", "\e[A"] ->
        {:ok, move_card_or_scroll(state, -1, data)}

      # Navigation: Down
      k when k in [:down, "j", "J", "\e[B"] ->
        {:ok, move_card_or_scroll(state, 1, data)}

      # Enter: Open/close detail
      k when k in [:enter, "\r", "\n"] ->
        {:ok, toggle_detail(state, data)}

      # Dismiss / Close detail
      k when k in [:esc, "\e", "\e\e"] ->
        {:ok, dismiss(state)}

      # Quit or dismiss
      k when k in ["q", "Q"] ->
        if state.detail_task_id do
          {:ok, dismiss(state)}
        else
          {:quit, %__MODULE__{state | quit?: true}}
        end

      # Refresh (signal is ok, caller reloads data)
      k when k in ["r", "R"] ->
        {:ok, state}

      _other ->
        {:ok, state}
    end
  end

  # Move between columns
  defp move_column(%__MODULE__{detail_task_id: nil} = state, delta) do
    new_col = max(0, min(state.active_column + delta, length(@columns) - 1))
    %__MODULE__{state | active_column: new_col}
  end

  defp move_column(state, _delta), do: state

  # Move card selection up/down or scroll detail view
  defp move_card_or_scroll(%__MODULE__{detail_task_id: nil} = state, delta, data) do
    col_idx = state.active_column
    col_name = Enum.at(@columns, col_idx)

    tickets =
      (data[:tickets] || [])
      |> Enum.filter(fn t -> t[:status] == col_name end)

    count = length(tickets)
    cur_row = Map.get(state.selected_rows, col_idx, 0)
    new_row = if count == 0, do: 0, else: max(0, min(cur_row + delta, count - 1))

    new_rows = Map.put(state.selected_rows, col_idx, new_row)
    %__MODULE__{state | selected_rows: new_rows}
  end

  defp move_card_or_scroll(%__MODULE__{} = state, delta, _data) do
    new_offset = max(0, state.detail_scroll_offset + delta)
    %__MODULE__{state | detail_scroll_offset: new_offset}
  end

  # Toggle detail view
  defp toggle_detail(%__MODULE__{detail_task_id: nil} = state, data) do
    col_idx = state.active_column
    col_name = Enum.at(@columns, col_idx)

    tickets =
      (data[:tickets] || [])
      |> Enum.filter(fn t -> t[:status] == col_name end)

    selected_row = Map.get(state.selected_rows, col_idx, 0)
    ticket = Enum.at(tickets, selected_row)

    if ticket do
      %__MODULE__{state | detail_task_id: ticket[:task_id], detail_scroll_offset: 0}
    else
      state
    end
  end

  defp toggle_detail(%__MODULE__{} = state, _data) do
    %__MODULE__{state | detail_task_id: nil, detail_scroll_offset: 0}
  end

  # Dismiss
  defp dismiss(%__MODULE__{} = state) do
    %__MODULE__{state | detail_task_id: nil, detail_scroll_offset: 0}
  end
end
