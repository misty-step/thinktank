defmodule Thinktank.ArtifactLayoutTest do
  use ExUnit.Case, async: true

  alias Thinktank.{ArtifactLayout, BenchSpec, RunContract, RunStore}

  defp unique_tmp_dir(prefix) do
    dir = Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    dir
  end

  defp read_json(path), do: path |> File.read!() |> Jason.decode!()

  test "summary artifacts stay stable by bench kind" do
    assert ArtifactLayout.summary_artifacts(:review) == [
             {"summary", "summary.md"},
             {"review", "review.md"}
           ]

    assert ArtifactLayout.summary_artifacts(:research) == [
             {"summary", "summary.md"},
             {"synthesis", "synthesis.md"}
           ]
  end

  test "run store writes the canonical artifact layout contract" do
    output_dir = Path.join(unique_tmp_dir("thinktank-artifact-layout"), "run")

    contract = %RunContract{
      bench_id: "review/default",
      workspace_root: File.cwd!(),
      input: %{input_text: "review this branch"},
      artifact_dir: output_dir,
      adapter_context: %{}
    }

    bench = %BenchSpec{
      id: "review/default",
      kind: :review,
      description: "Review",
      agents: ["trace"]
    }

    RunStore.init_run(output_dir, contract, bench)
    RunStore.init_agent_scratchpad(output_dir, "trace", "trace-1", %{bench: bench.id})
    RunStore.append_agent_output(output_dir, "trace-1", "partial note\n")

    RunStore.record_agent_result(output_dir, "trace", "final note", %{
      instance_id: "trace-1",
      status: :ok
    })

    assert File.exists?(Path.join(output_dir, ArtifactLayout.manifest_file()))
    assert File.exists?(Path.join(output_dir, ArtifactLayout.contract_file()))
    assert File.exists?(Path.join(output_dir, ArtifactLayout.run_scratchpad_file()))
    assert File.exists?(Path.join(output_dir, ArtifactLayout.agent_scratchpad_file("trace-1")))
    assert File.exists?(Path.join(output_dir, ArtifactLayout.agent_stream_file("trace-1")))
    assert File.exists?(Path.join(output_dir, ArtifactLayout.agent_result_file("trace-1")))

    manifest = read_json(Path.join(output_dir, ArtifactLayout.manifest_file()))

    assert Enum.any?(manifest["artifacts"], fn artifact ->
             artifact["name"] == "contract" and artifact["file"] == ArtifactLayout.contract_file()
           end)

    assert Enum.any?(manifest["agents"], fn agent ->
             agent["file"] == ArtifactLayout.agent_result_file("trace-1") and
               get_in(agent, ["metadata", "scratchpad"]) ==
                 ArtifactLayout.agent_scratchpad_file("trace-1") and
               get_in(agent, ["metadata", "stream"]) ==
                 ArtifactLayout.agent_stream_file("trace-1")
           end)
  end
end
