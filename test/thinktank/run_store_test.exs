defmodule Thinktank.RunStoreTest do
  use ExUnit.Case, async: true
  import Bitwise

  alias Thinktank.{BenchSpec, RunContract, RunStore}

  defp unique_tmp_dir(prefix) do
    dir = Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    dir
  end

  defp read_json(path), do: path |> File.read!() |> Jason.decode!()

  test "stores run artifacts inside a private output directory" do
    output_dir = Path.join(unique_tmp_dir("thinktank-run-store"), "run")

    contract = %RunContract{
      bench_id: "research/default",
      workspace_root: File.cwd!(),
      input: %{},
      artifact_dir: output_dir,
      adapter_context: %{}
    }

    bench = %BenchSpec{id: "research/default", description: "Demo", agents: ["systems"]}

    RunStore.init_run(output_dir, contract, bench)

    assert (File.stat!(output_dir).mode &&& 0o777) == 0o700
  end

  test "rejects artifact paths that escape the output directory" do
    output_dir = unique_tmp_dir("thinktank-run-store-paths")

    assert_raise ArgumentError, fn ->
      RunStore.write_text_artifact(output_dir, "escape", "../escape.txt", "nope")
    end
  end

  test "returns a compact result envelope for CLI output" do
    output_dir = Path.join(unique_tmp_dir("thinktank-run-store-envelope"), "run")

    contract = %RunContract{
      bench_id: "research/default",
      workspace_root: File.cwd!(),
      input: %{input_text: "hello"},
      artifact_dir: output_dir,
      adapter_context: %{}
    }

    bench = %BenchSpec{id: "research/default", description: "Demo", agents: ["systems"]}

    RunStore.init_run(output_dir, contract, bench)
    RunStore.record_agent_result(output_dir, "systems", "hello", %{status: :ok})
    RunStore.write_text_artifact(output_dir, "summary", "summary.md", "content")
    RunStore.complete_run(output_dir, "complete")

    envelope = RunStore.result_envelope(output_dir)
    assert envelope.output_dir == output_dir
    assert envelope.bench == "research/default"
    assert envelope.status == "complete"
    assert is_binary(envelope.started_at)
    assert is_binary(envelope.completed_at)
    assert is_integer(envelope.duration_ms)
    assert Enum.any?(envelope.agents, &(&1["name"] == "systems"))
    assert Enum.any?(envelope.artifacts, &(&1["name"] == "summary"))
  end

  test "updates manifest with dynamically planned agents" do
    output_dir = Path.join(unique_tmp_dir("thinktank-run-store-planned"), "run")

    contract = %RunContract{
      bench_id: "review/default",
      workspace_root: File.cwd!(),
      input: %{input_text: "review"},
      artifact_dir: output_dir,
      adapter_context: %{}
    }

    bench = %BenchSpec{id: "review/default", description: "Review", agents: ["trace", "guard"]}

    RunStore.init_run(output_dir, contract, bench)
    RunStore.set_planned_agents(output_dir, ["trace"])

    manifest = output_dir |> Path.join("manifest.json") |> File.read!() |> Jason.decode!()
    assert manifest["planned_agents"] == ["trace"]
  end

  test "result_envelope includes synthesis content and content_type on artifacts" do
    output_dir = Path.join(unique_tmp_dir("thinktank-run-store-envelope-enriched"), "run")

    contract = %RunContract{
      bench_id: "research/default",
      workspace_root: File.cwd!(),
      input: %{input_text: "hello"},
      artifact_dir: output_dir,
      adapter_context: %{}
    }

    bench = %BenchSpec{id: "research/default", description: "Demo", agents: ["systems"]}

    RunStore.init_run(output_dir, contract, bench)
    RunStore.record_agent_result(output_dir, "systems", "hello", %{status: :ok})
    RunStore.write_text_artifact(output_dir, "synthesis", "synthesis.md", "Synthesized content")
    RunStore.write_text_artifact(output_dir, "summary", "summary.md", "Summary content")
    RunStore.complete_run(output_dir, "complete")

    envelope = RunStore.result_envelope(output_dir)

    # synthesis field should inline the synthesis artifact content
    assert envelope.synthesis == "Synthesized content"

    # artifacts should have content_type
    Enum.each(envelope.artifacts, fn artifact ->
      assert Map.has_key?(artifact, "content_type")
    end)

    synth_artifact = Enum.find(envelope.artifacts, &(&1["name"] == "synthesis"))
    assert synth_artifact["content_type"] == "text/markdown"
    assert synth_artifact["type"] == "text"

    json_artifact = Enum.find(envelope.artifacts, &(&1["name"] == "contract"))
    assert json_artifact["content_type"] == "application/json"
  end

  test "aggregates usd cost totals and per-model usage into the result envelope" do
    output_dir = Path.join(unique_tmp_dir("thinktank-run-store-pricing"), "run")

    contract = %RunContract{
      bench_id: "research/default",
      workspace_root: File.cwd!(),
      input: %{input_text: "hello"},
      artifact_dir: output_dir,
      adapter_context: %{}
    }

    bench = %BenchSpec{id: "research/default", description: "Demo", agents: ["systems", "proof"]}

    RunStore.init_run(output_dir, contract, bench)

    RunStore.record_agent_result(output_dir, "systems", "first", %{
      instance_id: "systems-1",
      model: "openai/gpt-5.4-mini",
      status: :ok,
      usage: %{"input" => 100, "output" => 20, "cacheRead" => 40}
    })

    RunStore.record_agent_result(output_dir, "proof", "second", %{
      instance_id: "proof-1",
      model: "openai/gpt-5.4-mini",
      status: :ok,
      usage: %{"input" => 30, "output" => 10}
    })

    envelope = RunStore.result_envelope(output_dir)
    model = envelope.usd_cost_by_model["openai/gpt-5.4-mini"]

    assert envelope.pricing_gaps == []
    assert_in_delta envelope.usd_cost_total, 0.0002355, 1.0e-12
    assert model["input_tokens"] == 130
    assert model["output_tokens"] == 30
    assert model["cache_read_tokens"] == 40
    assert model["cache_write_tokens"] == 0
    assert model["total_tokens"] == 200
    assert_in_delta model["usd_cost"], 0.0002355, 1.0e-12
    assert model["pricing_gap"] == nil
  end

  test "marks run totals unavailable and logs a warning when pricing is unknown" do
    output_dir = Path.join(unique_tmp_dir("thinktank-run-store-pricing-gap"), "run")

    contract = %RunContract{
      bench_id: "research/default",
      workspace_root: File.cwd!(),
      input: %{input_text: "hello"},
      artifact_dir: output_dir,
      adapter_context: %{}
    }

    bench = %BenchSpec{id: "research/default", description: "Demo", agents: ["systems"]}

    RunStore.init_run(output_dir, contract, bench)

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        RunStore.record_agent_result(output_dir, "systems", "first", %{
          instance_id: "systems-1",
          model: "unknown/model",
          status: :ok,
          usage: %{"input" => 10, "output" => 5}
        })
      end)

    envelope = RunStore.result_envelope(output_dir)
    model = envelope.usd_cost_by_model["unknown/model"]

    assert log =~ "pricing unavailable for unknown/model"
    assert envelope.usd_cost_total == nil
    assert envelope.pricing_gaps == ["unknown/model"]
    assert model["usd_cost"] == nil
    assert model["pricing_gap"] == "no price table entry for unknown/model"
  end

  test "result_envelope inlines review summaries for review benches" do
    output_dir = Path.join(unique_tmp_dir("thinktank-run-store-review-envelope"), "run")

    contract = %RunContract{
      bench_id: "review/default",
      workspace_root: File.cwd!(),
      input: %{input_text: "review this branch"},
      artifact_dir: output_dir,
      adapter_context: %{}
    }

    bench = %BenchSpec{id: "review/default", description: "Review", agents: ["trace"]}

    RunStore.init_run(output_dir, contract, bench)
    RunStore.record_agent_result(output_dir, "trace", "grounded finding", %{status: :ok})
    RunStore.write_text_artifact(output_dir, "summary", "summary.md", "Review summary")
    RunStore.write_text_artifact(output_dir, "review", "review.md", "Synthesized review")
    RunStore.complete_run(output_dir, "complete")

    envelope = RunStore.result_envelope(output_dir)

    assert envelope.synthesis == "Synthesized review"
  end

  test "result_envelope synthesis is nil when no synthesis artifact exists" do
    output_dir = Path.join(unique_tmp_dir("thinktank-run-store-no-synth"), "run")

    contract = %RunContract{
      bench_id: "research/default",
      workspace_root: File.cwd!(),
      input: %{input_text: "hello"},
      artifact_dir: output_dir,
      adapter_context: %{}
    }

    bench = %BenchSpec{id: "research/default", description: "Demo", agents: ["systems"]}

    RunStore.init_run(output_dir, contract, bench)
    RunStore.record_agent_result(output_dir, "systems", "hello", %{status: :ok})
    RunStore.complete_run(output_dir, "complete")

    envelope = RunStore.result_envelope(output_dir)
    assert envelope.synthesis == nil
  end

  test "ensure_partial_summary writes a best-effort partial summary from scratchpads" do
    output_dir = Path.join(unique_tmp_dir("thinktank-run-store-partial"), "run")

    contract = %RunContract{
      bench_id: "research/default",
      workspace_root: File.cwd!(),
      input: %{input_text: "inspect this repo"},
      artifact_dir: output_dir,
      adapter_context: %{}
    }

    bench = %BenchSpec{
      id: "research/default",
      kind: :research,
      description: "Demo",
      agents: ["systems"]
    }

    RunStore.init_run(output_dir, contract, bench)

    RunStore.init_agent_scratchpad(output_dir, "systems", "systems-eafe895e-1", %{bench: bench.id})

    RunStore.append_agent_note(output_dir, "systems-eafe895e-1", "attempt 1 started")
    RunStore.append_agent_output(output_dir, "systems-eafe895e-1", "partial finding\n")
    RunStore.ensure_partial_summary(output_dir)
    RunStore.complete_run(output_dir, "partial")

    assert File.read!(Path.join(output_dir, "summary.md")) =~ "Partial Result"
    assert File.read!(Path.join(output_dir, "summary.md")) =~ "partial finding"
    assert File.exists?(Path.join(output_dir, "synthesis.md"))
  end

  test "initializes trace artifacts and updates trace summary on completion" do
    output_dir = Path.join(unique_tmp_dir("thinktank-run-store-trace"), "run")

    contract = %RunContract{
      bench_id: "research/default",
      workspace_root: File.cwd!(),
      input: %{input_text: "trace this"},
      artifact_dir: output_dir,
      adapter_context: %{}
    }

    bench = %BenchSpec{id: "research/default", description: "Demo", agents: ["systems"]}

    RunStore.init_run(output_dir, contract, bench)

    manifest = read_json(Path.join(output_dir, "manifest.json"))

    assert Enum.any?(manifest["artifacts"], fn artifact ->
             artifact["name"] == "trace-events" and artifact["file"] == "trace/events.jsonl" and
               artifact["type"] == "jsonl"
           end)

    assert Enum.any?(manifest["artifacts"], fn artifact ->
             artifact["name"] == "trace-summary" and artifact["file"] == "trace/summary.json" and
               artifact["type"] == "json"
           end)

    assert File.exists?(Path.join(output_dir, "trace/events.jsonl"))

    summary = read_json(Path.join(output_dir, "trace/summary.json"))
    assert summary["run_id"] == Path.basename(output_dir)
    assert summary["status"] == "running"

    RunStore.complete_run(output_dir, "complete")

    completed = read_json(Path.join(output_dir, "trace/summary.json"))
    assert completed["status"] == "complete"
    assert is_binary(completed["completed_at"])
  end
end
