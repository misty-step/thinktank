defmodule Thinktank.RunInspectorTest do
  use ExUnit.Case, async: false

  alias Thinktank.{BenchSpec, Error, RunContract, RunInspector, RunStore, RunTracker}

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

  defp read_json(path), do: path |> File.read!() |> Jason.decode!()

  defp write_json(path, data) do
    File.write!(path, Jason.encode!(data, pretty: true))
  end

  defp update_json(path, fun) do
    path
    |> read_json()
    |> fun.()
    |> then(&write_json(path, &1))
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

  test "show preserves workspace_root for summary-only runs" do
    output_dir = Path.join(unique_tmp_dir("thinktank-run-inspector-summary-only"), "run")
    expected_root = File.cwd!()

    init_run(output_dir, "research/default")
    RunStore.complete_run(output_dir, "complete")

    File.rm!(Path.join(output_dir, "manifest.json"))
    File.rm!(Path.join(output_dir, "contract.json"))

    assert {:ok, run} = RunInspector.show(output_dir)
    assert run.workspace_root == expected_root
    assert run.manifest_file == nil
    assert run.trace_summary_file == Path.join(output_dir, "trace/summary.json")
  end

  test "show prefers a terminal trace summary status over a stale manifest status" do
    output_dir = Path.join(unique_tmp_dir("thinktank-run-inspector-terminal-summary"), "run")
    init_run(output_dir, "research/default")
    RunStore.complete_run(output_dir, "failed")

    update_json(Path.join(output_dir, "manifest.json"), fn manifest ->
      manifest
      |> Map.put("status", "running")
      |> Map.delete("completed_at")
    end)

    assert {:ok, run} = RunInspector.show(output_dir)
    assert run.status == "failed"
    assert run.completed_at != nil
  end

  test "list returns recent runs sorted by started_at descending" do
    first_dir = Path.join(unique_tmp_dir("thinktank-run-inspector-list-first"), "first")
    init_run(first_dir, "research/default")
    RunStore.complete_run(first_dir, "complete")

    second_dir = Path.join(unique_tmp_dir("thinktank-run-inspector-list-second"), "second")
    init_run(second_dir, "review/default")
    RunStore.complete_run(second_dir, "degraded")

    update_json(
      Path.join(first_dir, "manifest.json"),
      &Map.put(&1, "started_at", "2026-01-01T00:00:00Z")
    )

    update_json(
      Path.join(second_dir, "manifest.json"),
      &Map.put(&1, "started_at", "2026-01-02T00:00:00Z")
    )

    assert {:ok, runs} = RunInspector.list(limit: nil)
    ids = Enum.map(runs, & &1.id)
    assert Enum.find(runs, &(&1.output_dir == Path.expand(first_dir))).status == "complete"
    assert Enum.find(runs, &(&1.output_dir == Path.expand(second_dir))).status == "degraded"
    assert Enum.find_index(ids, &(&1 == "second")) < Enum.find_index(ids, &(&1 == "first"))
  end

  test "show accepts a manifest path and resolves the containing run" do
    output_dir = Path.join(unique_tmp_dir("thinktank-run-inspector-manifest"), "run")
    init_run(output_dir, "research/default")
    RunStore.complete_run(output_dir, "complete")

    assert {:ok, run} = RunInspector.show(Path.join(output_dir, "manifest.json"))
    assert run.output_dir == Path.expand(output_dir)
    assert run.status == "complete"
  end

  test "show treats an existing bare relative directory name as a path target" do
    run_id = "custom-output-#{System.unique_integer([:positive])}"
    parent = Path.join(System.tmp_dir!(), "custom-parent-#{System.unique_integer([:positive])}")
    File.rm_rf!(parent)
    File.mkdir_p!(parent)
    output_dir = Path.join(parent, run_id)

    init_run(output_dir, "research/default")

    File.cd!(parent, fn ->
      assert {:ok, run} = RunInspector.show(run_id, log_dir: nil)
      assert Path.basename(run.output_dir) == run_id
      assert Path.basename(Path.dirname(run.output_dir)) == Path.basename(parent)
      assert run.status == "running"
    end)
  end

  test "show returns a typed error for a missing run target" do
    missing = Path.join(unique_tmp_dir("thinktank-run-inspector-missing"), "missing-run")

    assert {:error, %Error{code: :run_target_not_found, message: "run not found: " <> ^missing}} =
             RunInspector.show(missing)

    assert {:error, %Error{code: :run_target_not_found, message: "run not found: no-such-run"}} =
             RunInspector.show("no-such-run")
  end

  test "show returns a typed error for a non-run directory" do
    dir = unique_tmp_dir("thinktank-run-inspector-non-run")

    assert {:error,
            %Error{code: :invalid_run_target, message: "not a ThinkTank run directory: " <> ^dir}} =
             RunInspector.show(dir)
  end

  test "show returns a typed error for an existing non-run file" do
    path =
      Path.join(
        unique_tmp_dir("thinktank-run-inspector-non-run-file"),
        "notes.txt"
      )

    File.write!(path, "not a run")

    assert {:error,
            %Error{code: :invalid_run_target, message: "not a ThinkTank run directory: " <> ^path}} =
             RunInspector.show(path)
  end

  test "show returns a typed error when the run status is unknown" do
    output_dir = Path.join(unique_tmp_dir("thinktank-run-inspector-unknown-status"), "run")
    init_run(output_dir, "research/default")

    update_json(Path.join(output_dir, "manifest.json"), &Map.put(&1, "status", "mystery"))

    assert {:error, %Error{code: :run_status_invalid, message: "unknown run status: \"mystery\""}} =
             RunInspector.show(output_dir)
  end

  test "list returns a typed error for an invalid limit option" do
    assert {:error,
            %Error{
              code: :invalid_run_list_limit,
              message: "run list limit must be a non-negative integer"
            }} =
             RunInspector.list(limit: -1)
  end

  test "show returns a typed error when multiple runs share the same id" do
    run_id = "duplicate-run-#{System.unique_integer([:positive])}"
    first_dir = Path.join(unique_tmp_dir("thinktank-run-inspector-duplicate-first"), run_id)
    second_dir = Path.join(unique_tmp_dir("thinktank-run-inspector-duplicate-second"), run_id)

    init_run(first_dir, "research/default")
    RunStore.complete_run(first_dir, "complete")
    init_run(second_dir, "review/default")
    RunStore.complete_run(second_dir, "degraded")

    assert {:error,
            %Error{
              code: :run_target_ambiguous,
              message: "multiple runs match " <> ^run_id <> "; use an explicit path"
            }} =
             RunInspector.show(run_id)
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

  test "wait returns a typed timeout error while the run is still active" do
    output_dir = Path.join(unique_tmp_dir("thinktank-run-inspector-timeout"), "run")
    init_run(output_dir, "research/default")
    RunTracker.start(output_dir, %{"bench" => "research/default"})

    assert {:error,
            %Error{
              code: :run_wait_timeout,
              message: "timed out waiting for run to finish: " <> ^output_dir
            }} =
             RunInspector.wait(output_dir, poll_ms: 5, timeout_ms: 0)
  end

  test "wait returns immediately when the trace summary is already terminal" do
    output_dir = Path.join(unique_tmp_dir("thinktank-run-inspector-terminal-wait"), "run")
    init_run(output_dir, "research/default")
    RunStore.complete_run(output_dir, "degraded")

    update_json(Path.join(output_dir, "manifest.json"), fn manifest ->
      manifest
      |> Map.put("status", "running")
      |> Map.delete("completed_at")
    end)

    assert {:ok, run} = RunInspector.wait(output_dir, poll_ms: 5, timeout_ms: 0)
    assert run.status == "degraded"
  end
end
