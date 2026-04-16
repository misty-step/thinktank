defmodule Thinktank.RunTrackerTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  alias Thinktank.{BenchSpec, RunContract, RunStore, RunTracker}

  defp unique_tmp_dir(prefix) do
    dir = Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    dir
  end

  defp read_json(path), do: path |> File.read!() |> Jason.decode!()

  defp read_jsonl(path) do
    path
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.map(&Jason.decode!/1)
  end

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

  test "finish updates the manifest and writes a terminal run event" do
    output_dir = Path.join(unique_tmp_dir("thinktank-run-tracker-finish"), "run")
    init_run(output_dir)

    RunTracker.start(output_dir, %{"bench" => "research/quick"})

    RunTracker.finish(output_dir, "failed", %{
      "bench" => "research/quick",
      "steps" => [%{"name" => :capture}, :done],
      "phase" => "shutdown",
      "error" => %{"category" => "shutdown", "reason" => "test"}
    })

    manifest = read_json(Path.join(output_dir, "manifest.json"))
    summary = read_json(Path.join(output_dir, "trace/summary.json"))
    events = read_jsonl(Path.join(output_dir, "trace/events.jsonl"))

    assert manifest["status"] == "failed"
    assert is_binary(manifest["completed_at"])
    assert summary["status"] == "failed"
    assert is_binary(summary["completed_at"])

    assert Enum.any?(events, fn event ->
             event["event"] == "run_completed" and event["status"] == "failed" and
               event["phase"] == "shutdown" and event["error"]["reason"] == "test"
           end)

    assert Enum.any?(events, fn event ->
             event["event"] == "run_completed" and
               event["steps"] == [%{"name" => "capture"}, "done"]
           end)

    assert RunTracker.active_runs() == []
  end

  test "application shutdown finalizes active runs" do
    output_dir = Path.join(unique_tmp_dir("thinktank-run-tracker-shutdown"), "run")
    init_run(output_dir)

    RunTracker.start(output_dir, %{"bench" => "research/quick"})
    assert %{} == Thinktank.Application.prep_stop(%{})

    manifest = read_json(Path.join(output_dir, "manifest.json"))
    summary = read_json(Path.join(output_dir, "trace/summary.json"))
    events = read_jsonl(Path.join(output_dir, "trace/events.jsonl"))

    assert manifest["status"] == "partial"
    assert is_binary(manifest["completed_at"])
    assert summary["status"] == "partial"
    assert File.exists?(Path.join(output_dir, "summary.md"))

    assert Enum.any?(events, fn event ->
             event["event"] == "run_completed" and event["status"] == "partial" and
               event["phase"] == "shutdown" and
               event["error"]["reason"] == "application_shutdown"
           end)

    assert RunTracker.active_runs() == []
  end

  test "shutdown reasons are preserved for string and inspected values" do
    first_output_dir = Path.join(unique_tmp_dir("thinktank-run-tracker-string-reason"), "run")
    init_run(first_output_dir)
    RunTracker.start(first_output_dir, %{"bench" => "research/quick"})

    assert :ok == RunTracker.finalize_active_runs("sigterm")

    first_events = read_jsonl(Path.join(first_output_dir, "trace/events.jsonl"))

    assert Enum.any?(first_events, fn event ->
             event["event"] == "run_completed" and event["error"]["reason"] == "sigterm"
           end)

    second_output_dir = Path.join(unique_tmp_dir("thinktank-run-tracker-inspect-reason"), "run")
    init_run(second_output_dir)
    RunTracker.start(second_output_dir, %{"bench" => "research/quick"})

    assert :ok == RunTracker.finalize_active_runs(%{signal: :sigterm})

    second_events = read_jsonl(Path.join(second_output_dir, "trace/events.jsonl"))

    assert Enum.any?(second_events, fn event ->
             event["event"] == "run_completed" and
               event["error"]["reason"] == "%{signal: :sigterm}"
           end)
  end

  test "shutdown finalization fails open when artifacts cannot be updated" do
    output_dir = Path.join(unique_tmp_dir("thinktank-run-tracker-broken"), "blocked")
    File.write!(output_dir, "not a directory")

    RunTracker.start(output_dir, %{"bench" => "research/quick"})

    log =
      capture_log(fn ->
        assert :ok == RunTracker.finalize_active_runs(:sigterm)
      end)

    assert log =~ "run finalization failed"
    assert RunTracker.active_runs() == []
  end

  test "finish keeps the run registered when terminal artifacts cannot be written" do
    output_dir = Path.join(unique_tmp_dir("thinktank-run-tracker-finish-broken"), "blocked")
    File.write!(output_dir, "not a directory")

    RunTracker.start(output_dir, %{"bench" => "research/quick"})

    assert_raise File.Error, fn ->
      RunTracker.finish(output_dir, "failed", %{"bench" => "research/quick"})
    end

    assert [{expanded_output_dir, %{"bench" => "research/quick"}}] = RunTracker.active_runs()
    assert expanded_output_dir == Path.expand(output_dir)
  end
end
