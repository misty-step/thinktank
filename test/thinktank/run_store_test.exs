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
end
