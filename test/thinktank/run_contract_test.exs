defmodule Thinktank.RunContractTest do
  use ExUnit.Case, async: true

  alias Thinktank.RunContract

  test "to_map serializes the default adapter_context as an empty map" do
    contract = %RunContract{
      bench_id: "review/default",
      workspace_root: "/tmp/workspace",
      input: %{"input_text" => "Review this change"},
      artifact_dir: "/tmp/output"
    }

    assert RunContract.to_map(contract) == %{
             "bench_id" => "review/default",
             "workspace_root" => "/tmp/workspace",
             "input" => %{"input_text" => "Review this change"},
             "artifact_dir" => "/tmp/output",
             "adapter_context" => %{}
           }
  end

  test "from_map accepts atom keys and preserves adapter_context" do
    assert {:ok, contract} =
             RunContract.from_map(%{
               bench_id: "review/default",
               workspace_root: "/tmp/workspace",
               input: %{"input_text" => "Review this change"},
               artifact_dir: "/tmp/output",
               adapter_context: %{base: "master"}
             })

    assert contract.bench_id == "review/default"
    assert contract.adapter_context == %{base: "master"}
  end

  test "from_map defaults a missing adapter_context to an empty map" do
    assert {:ok, contract} =
             RunContract.from_map(%{
               "bench_id" => "review/default",
               "workspace_root" => "/tmp/workspace",
               "input" => %{"input_text" => "Review this change"},
               "artifact_dir" => "/tmp/output"
             })

    assert contract.adapter_context == %{}
  end

  test "from_map validates required and map fields" do
    assert {:error, "run contract must be a map"} = RunContract.from_map(nil)

    assert {:error, "missing bench_id"} =
             RunContract.from_map(%{
               "workspace_root" => "/tmp/workspace",
               "input" => %{},
               "artifact_dir" => "/tmp/output"
             })

    assert {:error, "input must be a map"} =
             RunContract.from_map(%{
               "bench_id" => "review/default",
               "workspace_root" => "/tmp/workspace",
               "input" => "review this",
               "artifact_dir" => "/tmp/output"
             })

    assert {:error, "adapter_context must be a map"} =
             RunContract.from_map(%{
               "bench_id" => "review/default",
               "workspace_root" => "/tmp/workspace",
               "input" => %{},
               "artifact_dir" => "/tmp/output",
               "adapter_context" => "bad"
             })
  end
end
