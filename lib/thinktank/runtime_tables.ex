defmodule Thinktank.RuntimeTables do
  @moduledoc false

  use GenServer

  alias Thinktank.{RunTracker, TraceLog}

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @impl true
  def init(:ok) do
    ensure_table(RunTracker.table_name(), [:named_table, :public, :set, read_concurrency: true])

    ensure_table(TraceLog.lock_table_name(), [
      :named_table,
      :public,
      :set,
      read_concurrency: true,
      write_concurrency: true
    ])

    {:ok, %{}}
  end

  defp ensure_table(name, options) do
    case :ets.whereis(name) do
      :undefined ->
        :ets.new(name, options)
        :ok

      _ ->
        :ok
    end
  rescue
    ArgumentError -> :ok
  end
end
