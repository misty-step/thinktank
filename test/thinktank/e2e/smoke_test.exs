defmodule Thinktank.E2E.SmokeTest do
  @moduledoc """
  End-to-end smoke checks for the built `./thinktank` escript.

  Verifies the two highest-value flows — `research --json` over stdin and
  `review eval` against a saved contract — through the actual binary, with
  a fake `pi` shim on `PATH` so no live OpenRouter calls are made.
  """

  use ExUnit.Case, async: false

  @moduletag :e2e

  alias Thinktank.Test.FakePi
  alias Thinktank.Test.Workspace

  @repo_root Path.expand("../../..", __DIR__)
  @escript Path.join(@repo_root, "thinktank")

  setup_all do
    unless File.exists?(@escript) do
      flunk("""
      Built escript not found at #{@escript}.
      Run `mix escript.build` before invoking the e2e smoke suite.
      """)
    end

    :ok
  end

  describe "research --json over stdin" do
    test "exits 0 and emits a complete run payload without contacting the network" do
      FakePi.with_fake_pi("success", fn env ->
        workspace = Workspace.unique_tmp_dir("thinktank-e2e-research")

        {stdout, stderr, status} =
          run_escript(
            ["research", "--json", "--no-synthesis", "--agents", "systems"],
            cd: workspace,
            env: FakePi.subprocess_env(env),
            input: "inspect this repo\n"
          )

        assert status == 0,
               "expected exit 0, got #{status}. stdout:\n#{stdout}\nstderr:\n#{stderr}"

        refute stdout =~ "openrouter.ai",
               "stdout leaked openrouter.ai reference:\n#{stdout}"

        refute stdout =~ "https://api.",
               "stdout leaked HTTPS api reference:\n#{stdout}"

        refute stderr =~ "openrouter.ai",
               "stderr leaked openrouter.ai reference:\n#{stderr}"

        refute stderr =~ "https://api.",
               "stderr leaked HTTPS api reference:\n#{stderr}"

        payload = decode_json!(stdout)

        assert payload["bench"] == "research/default"
        assert payload["status"] == "complete"
        assert is_binary(payload["output_dir"])
        assert is_binary(payload["started_at"])
        assert is_binary(payload["completed_at"])
        assert is_list(payload["artifacts"])
        assert is_list(payload["agents"])

        output_dir = payload["output_dir"]
        contract_path = Path.join(output_dir, "contract.json")
        manifest_path = Path.join(output_dir, "manifest.json")

        refute stdout =~ "\"type\":\"progress\""
        assert stderr =~ "\"type\":\"progress\""
        assert stderr =~ "\"phase\":\"initializing\""
        assert stderr =~ "\"phase\":\"running_agents\""
        assert stderr =~ "\"output_dir\":\"#{output_dir}\""

        assert File.exists?(contract_path), "missing contract.json at #{contract_path}"
        assert File.exists?(manifest_path), "missing manifest.json at #{manifest_path}"

        contract = decode_json!(File.read!(contract_path))
        assert is_binary(contract["bench_id"])
        assert is_binary(contract["workspace_root"])
        assert is_map(contract["input"])
        assert is_binary(contract["artifact_dir"])
        assert is_map(contract["adapter_context"])

        manifest = decode_json!(File.read!(manifest_path))
        assert manifest["status"] == "complete"
      end)
    end
  end

  describe "review eval against a saved contract" do
    test "exits 0 with a complete cases payload and per-case manifest" do
      FakePi.with_fake_pi("success", fn env ->
        workspace = Workspace.unique_tmp_dir("thinktank-e2e-review-workspace")
        Workspace.init_git_repo!(workspace)

        fixture_root = Workspace.unique_tmp_dir("thinktank-e2e-review-fixtures")
        output_root = Path.join(Workspace.unique_tmp_dir("thinktank-e2e-review-output"), "runs")

        contract = %{
          "bench_id" => "review/default",
          "workspace_root" => workspace,
          "input" => %{"input_text" => "Review the current change"},
          "artifact_dir" => Path.join([fixture_root, "case-001", "source-run"]),
          "adapter_context" => %{}
        }

        contract_path = Path.join([fixture_root, "case-001", "contract.json"])
        File.mkdir_p!(Path.dirname(contract_path))
        File.write!(contract_path, Jason.encode!(contract))

        {stdout, stderr, status} =
          run_escript(
            ["review", "eval", fixture_root, "--json", "--output", output_root],
            cd: workspace,
            env: FakePi.subprocess_env(env)
          )

        assert status == 0,
               "expected exit 0, got #{status}. stdout:\n#{stdout}\nstderr:\n#{stderr}"

        refute stdout =~ "openrouter.ai",
               "stdout leaked openrouter.ai reference:\n#{stdout}"

        refute stdout =~ "https://api.",
               "stdout leaked HTTPS api reference:\n#{stdout}"

        refute stderr =~ "openrouter.ai",
               "stderr leaked openrouter.ai reference:\n#{stderr}"

        refute stderr =~ "https://api.",
               "stderr leaked HTTPS api reference:\n#{stderr}"

        payload = decode_json!(stdout)
        assert payload["status"] == "complete"
        assert is_list(payload["cases"])
        assert payload["cases"] != []

        case_manifest = Path.join([Path.expand(output_root), "case-001", "manifest.json"])
        assert File.exists?(case_manifest), "missing per-case manifest at #{case_manifest}"

        manifest = decode_json!(File.read!(case_manifest))
        assert manifest["status"] == "complete"
      end)
    end
  end

  # ─── helpers ──────────────────────────────────────────────────────────

  # Runs the built escript and returns {stdout, stderr, status}. Stderr is
  # captured to a sibling tmp file so JSON on stdout is never corrupted by
  # log lines. The stdin scratch file (if any) is written outside the
  # workspace-under-test so the assertions see a clean tree.
  defp run_escript(args, opts) do
    cd = Keyword.fetch!(opts, :cd)
    env = Keyword.fetch!(opts, :env)
    input = Keyword.get(opts, :input)

    scratch_dir = Workspace.unique_tmp_dir("thinktank-e2e-scratch")
    stderr_path = Path.join(scratch_dir, "stderr.log")

    redirected = "2> #{shell_escape(stderr_path)}"

    cmd =
      case input do
        nil ->
          "exec #{shell_escape(@escript)} #{shell_args(args)} #{redirected}"

        bin when is_binary(bin) ->
          stdin_path = Path.join(scratch_dir, "stdin.txt")
          File.write!(stdin_path, bin)

          "exec #{shell_escape(@escript)} #{shell_args(args)}" <>
            " < #{shell_escape(stdin_path)} #{redirected}"
      end

    {stdout, status} = System.cmd("/bin/sh", ["-c", cmd], cd: cd, env: env)
    stderr = File.read!(stderr_path)
    {stdout, stderr, status}
  end

  defp shell_args(args), do: Enum.map_join(args, " ", &shell_escape/1)

  defp shell_escape(value) do
    "'" <> String.replace(value, "'", "'\\''") <> "'"
  end

  defp decode_json!(text) do
    case Jason.decode(String.trim(text)) do
      {:ok, decoded} ->
        decoded

      {:error, error} ->
        flunk("expected JSON output, got error #{inspect(error)}\nraw:\n#{text}")
    end
  end
end
