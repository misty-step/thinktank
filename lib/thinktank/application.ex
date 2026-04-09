defmodule Thinktank.Application do
  @moduledoc false

  use Application
  require Logger

  alias Thinktank.{RuntimeTables, RunTracker, SignalHandler}

  @impl true
  def start(_type, _args) do
    children = [
      RuntimeTables,
      {Task.Supervisor, name: Thinktank.AgentSupervisor}
    ]

    opts = [strategy: :one_for_one, name: Thinktank.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        attach_signal_handler(pid)

      other ->
        other
    end
  end

  @doc false
  @spec attach_signal_handler(pid(), (-> :ok | {:error, term()}), (String.t() -> term())) ::
          {:ok, pid(), map()} | {:error, term()}
  def attach_signal_handler(
        pid,
        installer \\ &SignalHandler.install/0,
        warn \\ &Logger.warning/1
      )
      when is_pid(pid) do
    case installer.() do
      :ok ->
        {:ok, pid, %{}}

      {:error, reason} ->
        warn.(
          "ThinkTank signal handler installation failed; continuing without signal hooks: " <>
            inspect(reason)
        )

        {:ok, pid, %{}}
    end
  end

  @impl true
  def prep_stop(state) do
    RunTracker.finalize_active_runs(:application_shutdown)
    state
  end

  @impl true
  def stop(_state) do
    RunTracker.finalize_active_runs(:application_shutdown)
    :ok
  end
end
