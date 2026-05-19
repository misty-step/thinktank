defmodule Thinktank.Review.DegradePolicy do
  @moduledoc false

  alias Thinktank.BenchSpec

  @spec evaluate(BenchSpec.t(), [map()], [map()], boolean()) :: map() | nil
  def evaluate(
        %BenchSpec{kind: :review} = bench,
        planned_agents,
        results,
        can_escalate_to_synthesizer?
      ) do
    invoked_domains = invoked_review_domains(planned_agents)
    failed_domains = failed_review_domains(results)
    missing_domains = Enum.filter(invoked_domains, &Map.has_key?(failed_domains, &1))

    outcome =
      cond do
        missing_domains == [] ->
          "none"

        can_escalate_to_synthesizer? and successful_output?(results) ->
          "escalate_to_synthesizer"

        true ->
          "fail_run"
      end

    %{
      "version" => 1,
      "bench" => bench.id,
      "invoked_domains" => invoked_domains,
      "missing_domains" => missing_domains,
      "outcome" => outcome,
      "gaps" =>
        Enum.map(missing_domains, fn domain ->
          %{
            "domain" => domain,
            "failed_agents" => Map.fetch!(failed_domains, domain),
            "message" => "Invoked #{domain} review coverage was unavailable."
          }
        end)
    }
  end

  def evaluate(_bench, _planned_agents, _results, _can_escalate_to_synthesizer?), do: nil

  @spec render_for_synthesis(map()) :: String.t()
  def render_for_synthesis(%{"gaps" => gaps, "outcome" => outcome}) do
    gap_lines =
      Enum.map_join(gaps, "\n", fn %{"domain" => domain, "failed_agents" => agents} ->
        "- #{domain}: #{Enum.join(agents, ", ")} failed"
      end)

    """
    Review degrade policy:
    Outcome: #{outcome}
    Missing invoked reviewer domains:
    #{gap_lines}

    Name these missing perspectives in the top-level review summary so the
    review does not read as complete coverage.
    """
    |> String.trim()
  end

  defp invoked_review_domains(planned_agents) do
    planned_agents
    |> Enum.map(&review_domain/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp failed_review_domains(results) do
    results
    |> Enum.filter(&(&1.status == :error))
    |> Enum.reduce(%{}, fn result, acc ->
      case review_domain(result.agent) do
        nil ->
          acc

        domain ->
          Map.update(acc, domain, [result.agent.name], &[result.agent.name | &1])
      end
    end)
    |> Map.new(fn {domain, agents} -> {domain, Enum.sort(agents)} end)
  end

  defp review_domain(%{metadata: %{} = metadata}) do
    case Map.get(metadata, "review_role") do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  defp review_domain(_agent), do: nil

  defp successful_output?(results) do
    Enum.any?(results, &(&1.status == :ok and String.trim(&1.output) != ""))
  end
end
