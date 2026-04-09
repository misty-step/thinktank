defmodule Thinktank.SignalHandler do
  @moduledoc false

  @behaviour :gen_event

  alias Thinktank.RunTracker

  @spec install() :: :ok | {:error, term()}
  def install do
    handlers = :gen_event.which_handlers(:erl_signal_server)

    if __MODULE__ in handlers do
      :ok
    else
      :gen_event.add_handler(:erl_signal_server, __MODULE__, [])
    end
  end

  @impl true
  def init(_args), do: {:ok, %{}}

  @impl true
  def handle_event(:sigusr1, state) do
    run_signal_action(:sigusr1)
    {:ok, state}
  end

  def handle_event(:sigquit, state) do
    run_signal_action(:sigquit)
    {:ok, state}
  end

  def handle_event(:sigterm, state) do
    run_signal_action(:sigterm)
    {:ok, state}
  end

  def handle_event(_signal, state), do: {:ok, state}

  @doc false
  @spec run_signal_action(atom(), map()) :: :ok
  def run_signal_action(signal, deps \\ default_deps())

  def run_signal_action(:sigusr1, deps) do
    deps.finalize.(:sigusr1)
    deps.halt_with_message.("Received SIGUSR1")
    :ok
  end

  def run_signal_action(:sigquit, deps) do
    deps.finalize.(:sigquit)
    deps.halt.()
    :ok
  end

  def run_signal_action(:sigterm, deps) do
    deps.log.(~c"SIGTERM received - finalizing ThinkTank runs before shutdown~n")
    deps.finalize.(:sigterm)
    deps.stop.()
    :ok
  end

  def run_signal_action(_signal, _deps), do: :ok

  @impl true
  def handle_info(_message, state), do: {:ok, state}

  @impl true
  def handle_call(_request, state), do: {:ok, :ok, state}

  @impl true
  def terminate(_reason, _state), do: :ok

  @impl true
  def code_change(_old_vsn, state, _extra), do: {:ok, state}

  defp default_deps do
    %{
      finalize: &RunTracker.finalize_active_runs/1,
      halt: &:erlang.halt/0,
      halt_with_message: &:erlang.halt/1,
      log: &:error_logger.info_msg/1,
      stop: &:init.stop/0
    }
  end
end
