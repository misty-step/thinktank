defmodule Thinktank.SignalHandlerTest do
  use ExUnit.Case, async: false

  test "installs the ThinkTank signal handler on erl_signal_server" do
    assert :ok == Thinktank.SignalHandler.install()
    assert :ok == Thinktank.SignalHandler.install()

    handlers = :gen_event.which_handlers(:erl_signal_server)

    assert Thinktank.SignalHandler in handlers
    assert :erl_signal_handler in handlers
  end

  test "install adds the handler when no ThinkTank handler is present" do
    if Thinktank.SignalHandler in :gen_event.which_handlers(:erl_signal_server) do
      assert :ok == :gen_event.delete_handler(:erl_signal_server, Thinktank.SignalHandler, :ok)
    end

    on_exit(fn ->
      assert :ok == Thinktank.SignalHandler.install()
    end)

    refute Thinktank.SignalHandler in :gen_event.which_handlers(:erl_signal_server)
    assert :ok == Thinktank.SignalHandler.install()
    assert Thinktank.SignalHandler in :gen_event.which_handlers(:erl_signal_server)
  end

  test "signal actions finalize runs and delegate the terminal side effect" do
    parent = self()

    deps = %{
      finalize: fn reason -> send(parent, {:finalize, reason}) end,
      halt: fn -> send(parent, :halt) end,
      halt_with_message: fn message -> send(parent, {:halt_with_message, message}) end,
      log: fn message -> send(parent, {:log, message}) end,
      stop: fn -> send(parent, :stop) end
    }

    assert :ok == Thinktank.SignalHandler.run_signal_action(:sigterm, deps)
    assert_receive {:log, ~c"SIGTERM received - finalizing ThinkTank runs before shutdown~n"}
    assert_receive {:finalize, :sigterm}
    assert_receive :stop

    assert :ok == Thinktank.SignalHandler.run_signal_action(:sigquit, deps)
    assert_receive {:finalize, :sigquit}
    assert_receive :halt

    assert :ok == Thinktank.SignalHandler.run_signal_action(:sigusr1, deps)
    assert_receive {:finalize, :sigusr1}
    assert_receive {:halt_with_message, "Received SIGUSR1"}
  end

  test "non-terminating callbacks remain no-ops or pass through" do
    assert {:ok, %{}} == Thinktank.SignalHandler.handle_event(:siginfo, %{})
    assert {:ok, %{}} == Thinktank.SignalHandler.handle_info(:tick, %{})
    assert {:ok, :ok, %{}} == Thinktank.SignalHandler.handle_call(:ping, %{})
    assert {:ok, %{}} == Thinktank.SignalHandler.code_change(:old, %{}, %{})
    assert :ok == Thinktank.SignalHandler.terminate(:normal, %{})
    assert :ok == Thinktank.SignalHandler.run_signal_action(:siginfo, %{})
  end
end
