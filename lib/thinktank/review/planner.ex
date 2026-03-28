defmodule Thinktank.Review.Planner do
  @moduledoc false

  alias Thinktank.{AgentSpec, Config, RunContract}
  alias Thinktank.Executor.Agentic
  alias Thinktank.Review.Context

  @type plan :: map()
  @type outcome :: %{plan: plan(), planner_result: Agentic.result() | nil}

  @spec manual([AgentSpec.t()]) :: outcome()
  def manual(agents) do
    %{plan: default_plan(agents, "manual"), planner_result: nil}
  end

  @spec create(
          AgentSpec.t() | nil,
          [AgentSpec.t()],
          RunContract.t(),
          map(),
          Config.t(),
          keyword()
        ) ::
          outcome()
  def create(nil, agents, _contract, _review_context, _config, _opts) do
    %{plan: default_plan(agents, "fallback"), planner_result: nil}
  end

  def create(planner, agents, contract, review_context, config, opts) do
    context = %{
      "paths_hint" => render_paths_hint(contract.input),
      "review_context" => Context.render(review_context),
      "review_roster" => render_roster(agents)
    }

    [planner_result] =
      Agentic.run([planner], contract, context, config,
        concurrency: 1,
        agent_config_dir: opts[:agent_config_dir],
        runner: opts[:runner]
      )

    plan =
      case planner_result.status do
        :ok ->
          case parse_plan(planner_result.output, agents) do
            {:ok, parsed} ->
              parsed

            {:error, reason} ->
              default_plan(agents, "fallback", [
                "planner output could not be parsed: #{reason}"
              ])
          end

        :error ->
          default_plan(agents, "fallback", [
            "planner failed: #{format_error(planner_result.error)}"
          ])
      end

    %{plan: plan, planner_result: planner_result}
  end

  @spec apply_plan(plan(), [AgentSpec.t()]) :: [AgentSpec.t()]
  def apply_plan(plan, agents) do
    indexed_agents =
      agents
      |> Enum.map(&{&1.name, &1})
      |> Map.new()

    selected =
      plan
      |> Map.get("selected_agents", [])
      |> Enum.map(&planned_agent(&1, indexed_agents))
      |> Enum.reject(&is_nil/1)

    if selected == [] do
      Enum.map(agents, &attach_brief(&1, default_brief(&1)))
    else
      selected
    end
  end

  @spec render(plan()) :: String.t()
  def render(plan) do
    reviewers =
      case Map.get(plan, "selected_agents", []) do
        [] ->
          "- none"

        selected ->
          Enum.map_join(selected, "\n", fn agent ->
            name = agent["name"] || "unknown"
            brief = agent["brief"] || ""
            "- #{name}: #{brief}"
          end)
      end

    warnings =
      case Map.get(plan, "warnings", []) do
        [] -> "- none"
        items -> Enum.map_join(items, "\n", &"- #{&1}")
      end

    """
    Review plan:
    - Source: #{Map.get(plan, "source", "unknown")}
    - Summary: #{Map.get(plan, "summary", "No planner summary provided.")}
    - Synth brief: #{Map.get(plan, "synthesis_brief", "Use reviewer evidence and suppress overlap.")}

    Selected reviewers:
    #{reviewers}

    Warnings:
    #{warnings}
    """
    |> String.trim()
  end

  defp parse_plan(raw_output, agents) when is_binary(raw_output) do
    allowed = MapSet.new(Enum.map(agents, & &1.name))

    with {:ok, decoded} <- decode_plan(raw_output),
         {:ok, selected} <- parse_selected_agents(decoded["selected_agents"], allowed),
         false <- selected == [] do
      {:ok,
       %{
         "version" => 1,
         "source" => "planner",
         "summary" =>
           trimmed_string(decoded["summary"]) ||
             "Planner selected the reviewer team for this change.",
         "selected_agents" => selected,
         "synthesis_brief" =>
           trimmed_string(decoded["synthesis_brief"]) ||
             "Prioritize grounded findings and collapse duplicates.",
         "warnings" => parse_warnings(decoded["warnings"])
       }}
    else
      true ->
        {:error, "planner selected no reviewers"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp decode_plan(raw_output) do
    raw_output
    |> candidate_json_strings()
    |> Enum.reduce_while({:error, "planner did not return valid JSON"}, fn candidate, _acc ->
      case Jason.decode(candidate) do
        {:ok, %{} = decoded} -> {:halt, {:ok, decoded}}
        _ -> {:cont, {:error, "planner did not return valid JSON"}}
      end
    end)
  end

  defp candidate_json_strings(raw_output) do
    trimmed = String.trim(raw_output)
    fenced = Regex.run(~r/```(?:json)?\s*(\{.*\})\s*```/s, raw_output, capture: :all_but_first)

    brace_candidate =
      case {first_index(raw_output, "{"), last_index(raw_output, "}")} do
        {nil, _} ->
          nil

        {_, nil} ->
          nil

        {start_index, end_index} when end_index >= start_index ->
          String.slice(raw_output, start_index..end_index)

        _ ->
          nil
      end

    [fenced && List.first(fenced), brace_candidate, trimmed]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp parse_selected_agents(selected_agents, allowed) when is_list(selected_agents) do
    parsed =
      selected_agents
      |> Enum.reduce([], fn entry, acc ->
        case parse_selected_agent(entry, allowed) do
          nil -> acc
          parsed_entry -> [parsed_entry | acc]
        end
      end)
      |> Enum.reverse()

    {:ok, parsed}
  end

  defp parse_selected_agents(_, _allowed), do: {:error, "selected_agents must be a list"}

  defp parse_selected_agent(%{} = entry, allowed) do
    with name when not is_nil(name) <- trimmed_string(entry["name"]),
         true <- MapSet.member?(allowed, name) do
      %{
        "name" => name,
        "brief" => trimmed_string(entry["brief"]) || default_brief(name)
      }
    else
      _ -> nil
    end
  end

  defp parse_selected_agent(_, _allowed), do: nil

  defp parse_warnings(warnings) when is_list(warnings) do
    warnings
    |> Enum.map(&trimmed_string/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_warnings(_), do: []

  defp default_plan(agents, source, warnings \\ []) do
    %{
      "version" => 1,
      "source" => source,
      "summary" => "Use the bench defaults for this review run.",
      "selected_agents" =>
        Enum.map(agents, fn agent ->
          %{
            "name" => agent.name,
            "brief" => default_brief(agent)
          }
        end),
      "synthesis_brief" => "Prioritize grounded findings and collapse duplicates.",
      "warnings" => warnings
    }
  end

  defp render_roster(agents) do
    Enum.map_join(agents, "\n", fn agent ->
      role = get_in(agent.metadata, ["review_role"]) || "reviewer"
      summary = first_sentence(agent.system_prompt)
      "- #{agent.name} (#{role}, #{agent.model}): #{summary}"
    end)
  end

  defp attach_brief(agent, brief) do
    %{agent | metadata: Map.put(agent.metadata, "review_brief", brief)}
  end

  defp planned_agent(agent_plan, indexed_agents) do
    case {trimmed_string(agent_plan["name"]), trimmed_string(agent_plan["brief"])} do
      {nil, _brief} ->
        nil

      {name, brief} ->
        case Map.get(indexed_agents, name) do
          nil -> nil
          agent -> attach_brief(agent, brief || default_brief(agent))
        end
    end
  end

  defp default_brief(%AgentSpec{} = agent) do
    role = get_in(agent.metadata, ["review_role"]) || "review"
    "Focus on the highest-signal #{role} risks in the change and report only grounded issues."
  end

  defp default_brief(name) when is_binary(name) do
    "Focus on the highest-signal risks relevant to #{name} and report only grounded issues."
  end

  defp first_sentence(text) when is_binary(text) do
    text
    |> String.split(~r/(?<=[.!?])\s+/, parts: 2)
    |> List.first()
    |> to_string()
    |> String.trim()
  end

  defp first_sentence(_), do: ""

  defp format_error(nil), do: "unknown error"
  defp format_error(error) when is_map(error), do: inspect(error)
  defp format_error(error), do: to_string(error)

  defp render_paths_hint(input) when is_map(input) do
    case Map.get(input, "paths", []) do
      [] -> "- none specified"
      paths -> Enum.map_join(paths, "\n", &"- #{&1}")
    end
  end

  defp trimmed_string(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp trimmed_string(_), do: nil

  defp first_index(haystack, needle) when is_binary(haystack) and is_binary(needle) do
    case :binary.match(haystack, needle) do
      {index, _length} -> index
      :nomatch -> nil
    end
  end

  defp last_index(haystack, needle) when is_binary(haystack) and is_binary(needle) do
    case :binary.matches(haystack, needle) do
      [] -> nil
      matches -> matches |> List.last() |> elem(0)
    end
  end
end
