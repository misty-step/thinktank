defmodule Thinktank.Integration.AgentContractTest do
  @moduledoc """
  Integration tests verifying the agent discovery contract:
  list benches (JSON) -> pick one -> show it (JSON, full) -> verify schema.
  Also tests structured error envelope output.
  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Thinktank.CLI

  @exit_codes CLI.exit_codes()

  describe "agent discovery path" do
    test "list benches, pick one, show full spec — all JSON" do
      # Step 1: list benches as JSON
      {:ok, list_cmd} = CLI.parse_args(["benches", "list", "--json"])

      list_output =
        capture_io(fn ->
          assert CLI.execute({:ok, list_cmd}) == @exit_codes.success
        end)

      {:ok, benches} = Jason.decode(String.trim(list_output))
      assert is_list(benches)
      assert length(benches) >= 1

      # Every bench entry has the required schema
      Enum.each(benches, fn bench ->
        assert is_binary(bench["id"])
        assert is_binary(bench["description"])
        assert is_binary(bench["kind"])
        assert is_integer(bench["agent_count"])
        assert bench["agent_count"] > 0
      end)

      # Step 2: pick one bench
      picked = List.first(benches)
      bench_id = picked["id"]

      # Step 3: show it with --full --json
      {:ok, show_cmd} = CLI.parse_args(["benches", "show", bench_id, "--full", "--json"])

      show_output =
        capture_io(fn ->
          assert CLI.execute({:ok, show_cmd}) == @exit_codes.success
        end)

      {:ok, detail} = Jason.decode(String.trim(show_output))
      assert detail["id"] == bench_id
      assert is_binary(detail["description"])
      assert is_binary(detail["kind"])
      assert is_list(detail["agents"])

      # Full agent specs have the required fields
      Enum.each(detail["agents"], fn agent ->
        assert is_binary(agent["name"]), "agent missing name"
        assert is_binary(agent["model"]), "agent #{agent["name"]} missing model"
        assert is_binary(agent["system_prompt"]), "agent #{agent["name"]} missing system_prompt"
        assert is_binary(agent["thinking_level"]), "agent #{agent["name"]} missing thinking_level"
        assert is_integer(agent["timeout_ms"]), "agent #{agent["name"]} missing timeout_ms"
        assert is_nil(agent["tools"]) or is_list(agent["tools"])
      end)

      # Agent count from list matches resolved agent count from show
      assert picked["agent_count"] == length(detail["agents"])
    end
  end

  describe "error envelope" do
    test "structured JSON error on dry-run with invalid input" do
      command = %{
        action: :run,
        bench_id: "research/default",
        cwd: File.cwd!(),
        json: true,
        output: nil,
        dry_run: true,
        trust_repo_config: nil,
        input: %{input_text: 42, paths: [], agents: [], no_synthesis: false}
      }

      stderr =
        capture_io(:stderr, fn ->
          assert CLI.execute({:ok, command}) == @exit_codes.input_error
        end)

      {:ok, decoded} = Jason.decode(String.trim(stderr))
      assert is_map(decoded["error"])
      assert decoded["error"]["code"] == "missing_input_text"
      assert is_binary(decoded["error"]["message"])
      assert is_map(decoded["error"]["details"])
    end

    test "text error on dry-run with invalid input without --json" do
      command = %{
        action: :run,
        bench_id: "research/default",
        cwd: File.cwd!(),
        json: false,
        output: nil,
        dry_run: true,
        trust_repo_config: nil,
        input: %{input_text: 42, paths: [], agents: [], no_synthesis: false}
      }

      stderr =
        capture_io(:stderr, fn ->
          assert CLI.execute({:ok, command}) == @exit_codes.input_error
        end)

      assert stderr =~ "Error: input text is required"
    end
  end
end
