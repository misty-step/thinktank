defmodule Thinktank.RunStoreTest do
  use ExUnit.Case, async: true
  import Bitwise

  alias Thinktank.{BenchSpec, RunContract, RunStore}

  defp unique_tmp_dir(prefix) do
    dir = Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    dir
  end

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
end
