defmodule Thinktank.RunStoreTest do
  use ExUnit.Case, async: true
  import Bitwise

  alias Thinktank.{RunContract, RunStore, WorkflowSpec}

  defp unique_tmp_dir(prefix) do
    dir = Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    dir
  end

  test "stores run artifacts inside a private output directory" do
    output_dir = Path.join(unique_tmp_dir("thinktank-run-store"), "run")

    contract = %RunContract{
      workflow_id: "research/default",
      workspace_root: File.cwd!(),
      input: %{},
      artifact_dir: output_dir,
      adapter_context: %{},
      mode: :quick
    }

    workflow = %WorkflowSpec{
      id: "research/default",
      description: "Demo",
      stages: []
    }

    RunStore.init_run(output_dir, contract, workflow)

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
      workflow_id: "research/default",
      workspace_root: File.cwd!(),
      input: %{input_text: "hello"},
      artifact_dir: output_dir,
      adapter_context: %{},
      mode: :quick
    }

    workflow = %WorkflowSpec{
      id: "research/default",
      description: "Demo",
      stages: []
    }

    RunStore.init_run(output_dir, contract, workflow)
    RunStore.record_agent_result(output_dir, "trace", "hello", %{status: :ok})
    RunStore.write_text_artifact(output_dir, "review", "review.md", "content")
    RunStore.complete_run(output_dir, "complete")

    envelope = RunStore.result_envelope(output_dir)
    assert envelope.output_dir == output_dir
    assert envelope.workflow == "research/default"
    assert envelope.status == "complete"
    assert Enum.any?(envelope.agents, &(&1["name"] == "trace"))
    assert Enum.any?(envelope.artifacts, &(&1["name"] == "review"))
  end

  test "disambiguates stage and agent filenames with stable hashes" do
    output_dir = Path.join(unique_tmp_dir("thinktank-run-store-hash"), "run")

    contract = %RunContract{
      workflow_id: "research/default",
      workspace_root: File.cwd!(),
      input: %{},
      artifact_dir: output_dir,
      adapter_context: %{},
      mode: :quick
    }

    workflow = %WorkflowSpec{
      id: "research/default",
      description: "Demo",
      stages: []
    }

    RunStore.init_run(output_dir, contract, workflow)
    RunStore.record_stage(output_dir, "A B", "complete", 1, %{})
    RunStore.record_stage(output_dir, "a-b", "complete", 1, %{})
    RunStore.record_agent_result(output_dir, "Trace Guard", "one", %{})
    RunStore.record_agent_result(output_dir, "Trace/Guard", "two", %{})

    stage_files = Path.join(output_dir, "stages") |> File.ls!() |> Enum.sort()
    agent_files = Path.join(output_dir, "agents") |> File.ls!() |> Enum.sort()

    assert length(stage_files) == 2
    assert length(agent_files) == 2
    assert Enum.uniq(stage_files) == stage_files
    assert Enum.uniq(agent_files) == agent_files
  end
end
