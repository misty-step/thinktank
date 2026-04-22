defmodule Thinktank.RunInspectorTest do
  use ExUnit.Case, async: false

  alias Thinktank.{BenchSpec, RunContract, RunInspector, RunStore, RunTracker}

  defp unique_tmp_dir(prefix) do
    dir = Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    dir
  end

  defp init_run(output_dir, bench_id) do
    contract = %RunContract{
      bench_id: bench_id,
      workspace_root: File.cwd!(),
      input: %{"input_text" => "inspect this"},
      artifact_dir: output_dir,
      adapter_context: %{}
    }

    bench = %BenchSpec{id: bench_id, description: "Demo", agents: ["systems"]}

    RunStore.init_run(output_dir, contract, bench)
  end

  setup do
    log_dir = unique_tmp_dir("thinktank-run-inspector-logs")
    previous = System.get_env("THINKTANK_LOG_DIR")
    System.put_env("THINKTANK_LOG_DIR", log_dir)

    on_exit(fn ->
      if previous do
        System.put_env("THINKTANK_LOG_DIR", previous)
      else
        System.delete_env("THINKTANK_LOG_DIR")
      end

      Enum.each(RunTracker.active_runs(), fn {output_dir, _attrs} ->
        RunTracker.unregister(output_dir)
      end)
    end)

    %{log_dir: log_dir}
  end

  for {status, bench_id} <- [
        {"complete", "research/default"},
        {"degraded", "review/default"},
        {"partial", "research/default"},
        {"failed", "review/default"}
      ] do
    test "show reports #{status} terminal state" do
      output_dir =
        Path.join(unique_tmp_dir("thinktank-run-inspector-#{unquote(status)}"), "run")

      init_run(output_dir, unquote(bench_id))
      RunStore.complete_run(output_dir, unquote(status))

      assert {:ok, run} = RunInspector.show(output_dir)
      assert run.status == unquote(status)
      assert run.output_dir == Path.expand(output_dir)
      assert run.id == Path.basename(output_dir)
      assert run.bench == unquote(bench_id)
    end
  end

  test "show reports running state for an initialized active run" do
    output_dir = Path.join(unique_tmp_dir("thinktank-run-inspector-running"), "run")
    init_run(output_dir, "research/default")
    RunTracker.start(output_dir, %{"bench" => "research/default"})

    assert {:ok, run} = RunInspector.show(output_dir)
    assert run.status == "running"
    assert run.completed_at == nil
  end

  test "show resolves a run by id discovered from the global trace log" do
    run_id = "custom-run-#{System.unique_integer([:positive])}"
    parent = Path.join(System.tmp_dir!(), "custom-parent-#{System.unique_integer([:positive])}")
    File.rm_rf!(parent)
    File.mkdir_p!(parent)
    output_dir = Path.join(parent, run_id)

    init_run(output_dir, "research/default")
    RunTracker.start(output_dir, %{"bench" => "research/default"})
    RunTracker.finish(output_dir, "complete", %{"bench" => "research/default"})

    assert {:ok, run} = RunInspector.show(run_id)
    assert run.output_dir == Path.expand(output_dir)
    assert run.status == "complete"
  end

  test "list returns recent runs sorted by started_at descending" do
    first_dir = Path.join(unique_tmp_dir("thinktank-run-inspector-list-first"), "first")
    init_run(first_dir, "research/default")
    RunStore.complete_run(first_dir, "complete")
    Process.sleep(10)

    second_dir = Path.join(unique_tmp_dir("thinktank-run-inspector-list-second"), "second")
    init_run(second_dir, "review/default")
    RunStore.complete_run(second_dir, "degraded")

    assert {:ok, runs} = RunInspector.list(limit: nil)
    ids = Enum.map(runs, & &1.id)
    assert Enum.find(runs, &(&1.output_dir == Path.expand(first_dir))).status == "complete"
    assert Enum.find(runs, &(&1.output_dir == Path.expand(second_dir))).status == "degraded"
    assert Enum.find_index(ids, &(&1 == "second")) < Enum.find_index(ids, &(&1 == "first"))
  end

  test "wait blocks until the run reaches a terminal state" do
    output_dir = Path.join(unique_tmp_dir("thinktank-run-inspector-wait"), "run")
    init_run(output_dir, "research/default")
    RunTracker.start(output_dir, %{"bench" => "research/default"})

    parent = self()

    Task.start(fn ->
      Process.sleep(50)
      RunTracker.finish(output_dir, "complete", %{"bench" => "research/default"})
      send(parent, :finished)
    end)

    assert {:ok, run} = RunInspector.wait(output_dir, poll_ms: 10, timeout_ms: 1_000)
    assert run.status == "complete"
    assert_receive :finished, 1_000
  end
end
