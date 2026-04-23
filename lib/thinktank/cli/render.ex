defmodule Thinktank.CLI.Render do
  @moduledoc false

  alias Thinktank.{AgentSpec, Error}

  @spec usage_text(String.t()) :: String.t()
  def usage_text(version) do
    """
    thinktank #{version}

    Usage:
      thinktank run <bench> --input "..." [options]
      thinktank research "..." [options]
      thinktank review [options]
      thinktank review eval <contract-or-dir> [--bench <bench>]
      thinktank runs list|show <path-or-id>|wait <path-or-id> [--timeout-ms N]
      thinktank benches list|show|validate

    Task text can come from --input, positional text, or piped stdin.

    Options:
      --input TEXT          Task text
      --paths PATH          Point the bench at paths in the workspace (repeatable)
      --agents LIST         Comma-separated agent override for the selected bench
      --json                Output JSON
      --full                Include full agent specs in benches show
      --output, -o DIR      Output directory
      --dry-run             Resolve the bench without launching agents
      --no-synthesis        Skip the synthesizer agent
      --trust-repo-config   Trust .thinktank/config.yml in the current repository
      --base REF            Review base ref
      --head REF            Review head ref
      --repo REPO           Review repo owner/name
      --pr N                Review pull request number
      --timeout-ms N        Bound runs wait polling in milliseconds

    Examples:
      thinktank research "analyze this codebase" --paths ./lib
      thinktank review --base origin/main --head HEAD
      thinktank review eval ./tmp/review-run --bench review/default
      thinktank run review/default --input "Review this branch" --agents trace,guard
      thinktank benches show research/default
    """
  end

  @spec dry_run_output(map(), map()) :: String.t()
  def dry_run_output(command, resolved) do
    payload = %{
      action: command.action,
      bench: resolved.bench.id,
      description: resolved.bench.description,
      agents: Enum.map(resolved.agents, & &1.name),
      planner: resolved.planner && resolved.planner.name,
      synthesizer: resolved.synthesizer && resolved.synthesizer.name,
      input: command.input,
      output: resolved.output_dir,
      json: command.json
    }

    if command.json do
      Jason.encode!(payload)
    else
      """
      Bench: #{payload.bench}
      Description: #{payload.description}
      Agents: #{Enum.join(payload.agents, ", ")}
      Planner: #{payload.planner || "none"}
      Synthesizer: #{payload.synthesizer || "none"}
      Input: #{payload.input.input_text}
      Output: #{payload.output}
      """
      |> String.trim()
    end
  end

  @spec benches_list_json([map()]) :: String.t()
  def benches_list_json(benches) do
    benches
    |> Enum.map(fn bench ->
      %{
        id: bench.id,
        description: bench.description,
        kind: Atom.to_string(bench.kind),
        agent_count: length(bench.agents)
      }
    end)
    |> Jason.encode!()
  end

  @spec benches_list_text([map()]) :: String.t()
  def benches_list_text(benches) do
    Enum.map_join(benches, "\n", fn bench ->
      "#{bench.id}\t#{bench.description}"
    end)
  end

  @spec benches_validate_json([map()]) :: String.t()
  def benches_validate_json(benches) do
    %{status: "ok", bench_count: length(benches)}
    |> Jason.encode!()
  end

  @spec benches_validate_text([map()]) :: String.t()
  def benches_validate_text(benches), do: "Validated #{length(benches)} benches"

  @spec benches_show_json(map()) :: String.t()
  def benches_show_json(payload), do: Jason.encode!(payload, pretty: true)

  @spec benches_show_text(map()) :: String.t()
  def benches_show_text(payload) do
    """
    Bench: #{payload.id}
    Description: #{payload.description}
    Kind: #{payload.kind}
    Planner: #{payload.planner || "none"}
    Synthesizer: #{payload.synthesizer || "none"}
    Concurrency: #{payload.concurrency || "none"}
    Default Task: #{payload.default_task || "none"}

    Agents:
    #{render_bench_show_agent_lines(payload.agents)}
    """
  end

  @spec runs_list_json([map()]) :: String.t()
  def runs_list_json(runs), do: Jason.encode!(%{runs: runs})

  @spec runs_list_text([map()]) :: String.t()
  def runs_list_text([]), do: "No runs found"

  def runs_list_text(runs) do
    rows =
      Enum.map_join(runs, "\n", fn run ->
        [
          run.id,
          run.status,
          run.bench || "unknown",
          run.started_at || "unknown",
          run.output_dir
        ]
        |> Enum.join("\t")
      end)

    "ID\tSTATUS\tBENCH\tSTARTED\tOUTPUT\n" <> rows
  end

  @spec run_json(map()) :: String.t()
  def run_json(run), do: Jason.encode!(%{run: run})

  @spec run_text(map()) :: String.t()
  def run_text(run) do
    """
    Run: #{run.id}
    Bench: #{run.bench || "unknown"}
    Kind: #{run.kind || "unknown"}
    Status: #{run.status}
    Started: #{run.started_at || "unknown"}
    Completed: #{run.completed_at || "pending"}
    Output: #{run.output_dir}
    Workspace: #{run.workspace_root || "unknown"}
    Manifest: #{run.manifest_file || "none"}
    Trace Summary: #{run.trace_summary_file || "none"}
    Trace Events: #{run.trace_events_file || "none"}
    """
    |> String.trim()
  end

  @spec resolve_agents_payload(map(), map(), boolean()) ::
          {:ok, [map() | String.t()]} | {:error, String.t()}
  def resolve_agents_payload(bench, _config, false), do: {:ok, bench.agents}

  def resolve_agents_payload(bench, config, true) do
    Enum.reduce_while(bench.agents, {:ok, []}, fn name, {:ok, acc} ->
      case Map.get(config.agents, name) do
        nil ->
          {:halt, {:error, "unknown agent: #{name}"}}

        %AgentSpec{} = agent ->
          spec = %{
            name: agent.name,
            model: agent.model,
            provider: agent.provider,
            tools: agent.tools,
            system_prompt: agent.system_prompt,
            thinking_level: agent.thinking_level,
            timeout_ms: agent.timeout_ms
          }

          {:cont, {:ok, [spec | acc]}}
      end
    end)
    |> case do
      {:ok, specs} -> {:ok, Enum.reverse(specs)}
      error -> error
    end
  end

  @spec error_payload(Error.t(), String.t() | nil) :: map()
  def error_payload(%Error{} = error, output_dir), do: %{error: error, output_dir: output_dir}

  @spec error_lines(Error.t(), String.t() | nil) :: [String.t()]
  def error_lines(%Error{} = error, output_dir) do
    ["Error: #{error.message}"] ++
      if(is_binary(output_dir), do: ["Artifacts: #{output_dir}"], else: [])
  end

  @spec eval_text(map()) :: String.t()
  def eval_text(payload) do
    """
    Review eval: #{payload.target}
    Status: #{payload.status}
    Output: #{payload.output_dir}

    Cases:
    #{render_eval_case_lines(payload.cases)}
    """
  end

  @spec contract_payload(map()) :: map()
  def contract_payload(payload), do: Map.put(payload, :error, contract_error(payload))

  @spec render_run_payload(map()) :: String.t()
  def render_run_payload(payload) do
    """
    Bench: #{payload.bench}
    Status: #{payload.status}
    Output: #{payload.output_dir}
    Cost: #{render_usd_cost(payload[:usd_cost_total], payload[:pricing_gaps] || [])}

    Agents:
    #{render_agent_lines(payload.agents)}

    Artifacts:
    #{render_artifact_lines(payload.artifacts)}
    """
  end

  defp render_bench_show_agent_lines(agents) do
    Enum.map_join(agents, "\n", fn
      name when is_binary(name) ->
        "- #{name}"

      %{} = agent ->
        tools =
          case agent.tools do
            nil -> "none"
            [] -> "none"
            values -> Enum.join(values, ", ")
          end

        system_prompt =
          agent.system_prompt
          |> String.trim_trailing()
          |> indent_lines("      ")

        """
        - #{agent.name}
          model=#{agent.model}
          provider=#{agent.provider}
          thinking_level=#{agent.thinking_level}
          timeout_ms=#{agent.timeout_ms}
          tools=#{tools}
          system_prompt:
        #{system_prompt}
        """
        |> String.trim_trailing()
    end)
  end

  defp indent_lines(text, prefix) do
    text
    |> String.split("\n")
    |> Enum.map_join("\n", &(prefix <> &1))
  end

  defp render_agent_lines(agents) do
    Enum.map_join(agents, "\n", fn agent ->
      status = get_in(agent, ["metadata", "status"]) || "unknown"
      "- #{agent["name"]}: #{status}"
    end)
  end

  defp render_artifact_lines(artifacts) do
    Enum.map_join(artifacts, "\n", fn artifact ->
      "- #{artifact["name"]}: #{artifact["file"]}"
    end)
  end

  defp render_eval_case_lines(cases) do
    Enum.map_join(cases, "\n", fn case_result ->
      "- #{case_result.case_id}: #{case_result.status} (#{case_result.bench})"
    end)
  end

  defp render_usd_cost(total, []), do: "$" <> format_usd(total)

  defp render_usd_cost(_total, pricing_gaps) do
    "unavailable (pricing gap: #{Enum.join(pricing_gaps, ", ")})"
  end

  defp format_usd(total) when is_number(total), do: :erlang.float_to_binary(total, decimals: 6)
  defp format_usd(_total), do: "0.000000"

  defp contract_error(%{status: "complete"}), do: nil

  defp contract_error(%{status: "degraded"}) do
    Error.from_contract(:degraded_run, %{status: "degraded"})
  end

  defp contract_error(%{status: "partial"}) do
    Error.from_contract(:partial_run, %{status: "partial"})
  end

  defp contract_error(_payload), do: nil
end
