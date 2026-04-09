defmodule Thinktank.ApplicationTest do
  use ExUnit.Case, async: false

  alias Thinktank.{BenchSpec, RunContract, RunStore, RuntimeTables, RunTracker, TraceLog}

  defp unique_tmp_dir(prefix) do
    dir = Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    dir
  end

  defp read_json(path), do: path |> File.read!() |> Jason.decode!()

  defp init_run(output_dir) do
    contract = %RunContract{
      bench_id: "research/quick",
      workspace_root: File.cwd!(),
      input: %{"input_text" => "trace this"},
      artifact_dir: output_dir,
      adapter_context: %{}
    }

    bench = %BenchSpec{id: "research/quick", description: "Research", agents: ["systems"]}

    RunStore.init_run(output_dir, contract, bench)
  end

  setup do
    on_exit(fn ->
      Enum.each(RunTracker.active_runs(), fn {output_dir, _attrs} ->
        RunTracker.unregister(output_dir)
      end)
    end)

    :ok
  end

  test "start returns already_started when the supervisor is already running" do
    assert {:error, {:already_started, pid}} = Thinktank.Application.start(:normal, [])
    assert is_pid(pid)
  end

  test "attach_signal_handler stops the supervisor when install fails" do
    parent = self()
    {:ok, pid} = Supervisor.start_link([], strategy: :one_for_one)

    assert {:ok, ^pid, %{}} =
             Thinktank.Application.attach_signal_handler(
               pid,
               fn -> {:error, :install_failed} end,
               fn message -> send(parent, {:warn, message}) end
             )

    assert_receive {:warn, message}
    assert message =~ "install_failed"
    assert Process.alive?(pid)
    assert :ok == Supervisor.stop(pid)
  end

  test "stop finalizes active runs before shutdown completes" do
    output_dir = Path.join(unique_tmp_dir("thinktank-application-stop"), "run")
    init_run(output_dir)

    RunTracker.start(output_dir, %{"bench" => "research/quick"})

    assert :ok == Thinktank.Application.stop(%{})

    manifest = read_json(Path.join(output_dir, "manifest.json"))
    assert manifest["status"] == "failed"
    assert is_binary(manifest["completed_at"])
    assert RunTracker.active_runs() == []
  end

  test "runtime tables are owned by the supervised runtime process" do
    runtime_tables = Process.whereis(RuntimeTables)
    assert is_pid(runtime_tables)

    assert :ets.info(RunTracker.table_name(), :owner) == runtime_tables
    assert :ets.info(TraceLog.lock_table_name(), :owner) == runtime_tables
  end

  test "short-lived callers do not own the run tracker table" do
    output_dir = Path.join(unique_tmp_dir("thinktank-application-runtime-table"), "run")

    worker =
      spawn(fn ->
        RunTracker.start(output_dir, %{"bench" => "research/quick"})
      end)

    ref = Process.monitor(worker)
    assert_receive {:DOWN, ^ref, :process, ^worker, _reason}

    assert :ets.whereis(RunTracker.table_name()) != :undefined
    assert :ets.info(RunTracker.table_name(), :owner) == Process.whereis(RuntimeTables)
    assert [{expanded_output_dir, %{"bench" => "research/quick"}}] = RunTracker.active_runs()
    assert expanded_output_dir == Path.expand(output_dir)

    RunTracker.unregister(output_dir)
  end
end
