defmodule Thinktank.Review.Coverage do
  @moduledoc false

  alias Thinktank.BenchSpec

  @spec evaluate(BenchSpec.t(), [map()], [map()], String.t(), map() | nil) :: map() | nil
  def evaluate(%BenchSpec{kind: :review} = bench, planned_agents, results, run_status, policy) do
    planned_reviewers = Enum.map(planned_agents, &reviewer_entry/1)
    requested_domains = domains(planned_reviewers)
    completed_domains = result_domains(results, :ok)
    failed_domains = result_domains(results, :error)
    missing_domains = requested_domains -- completed_domains

    %{
      "version" => 1,
      "bench" => bench.id,
      "status" => coverage_status(run_status, requested_domains, missing_domains, failed_domains),
      "requested_domains" => requested_domains,
      "planned_reviewers" => planned_reviewers,
      "completed_domains" => completed_domains,
      "failed_domains" => failed_domains,
      "missing_domains" => missing_domains,
      "degraded_domains" => failed_domains,
      "degrade_policy" => degrade_policy_ref(policy)
    }
  end

  def evaluate(_bench, _planned_agents, _results, _run_status, _policy), do: nil

  @spec render_summary(map()) :: String.t()
  def render_summary(%{
        "status" => status,
        "requested_domains" => requested_domains,
        "completed_domains" => completed_domains,
        "missing_domains" => missing_domains,
        "degraded_domains" => degraded_domains
      }) do
    """
    ## Review Coverage

    - Status: #{status}
    - Requested: #{render_domains(requested_domains)}
    - Completed: #{render_domains(completed_domains)}
    - Missing: #{render_domains(missing_domains)}
    - Degraded: #{render_domains(degraded_domains)}
    """
    |> String.trim()
  end

  @spec summary_required?(map()) :: boolean()
  def summary_required?(%{"status" => status}), do: status in ["degraded", "failed", "partial"]

  defp reviewer_entry(agent) do
    %{
      "agent" => agent.name,
      "domain" => review_domain(agent)
    }
  end

  defp result_domains(results, status) do
    results
    |> Enum.filter(&result_has_status?(&1, status))
    |> Enum.map(&review_domain(&1.agent))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp domains(entries) do
    entries
    |> Enum.map(& &1["domain"])
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp review_domain(%{metadata: %{} = metadata}) do
    case Map.get(metadata, "review_role") do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  defp review_domain(_agent), do: nil

  defp result_has_status?(%{status: :ok, output: output}, :ok), do: String.trim(output) != ""
  defp result_has_status?(%{status: status}, status), do: true
  defp result_has_status?(_result, _status), do: false

  defp coverage_status(_run_status, [], _missing_domains, _failed_domains), do: "not_applicable"

  defp coverage_status("failed", _requested_domains, _missing_domains, _failed_domains),
    do: "failed"

  defp coverage_status("partial", _requested_domains, _missing_domains, _failed_domains),
    do: "partial"

  defp coverage_status(_run_status, _requested_domains, missing_domains, _failed_domains)
       when missing_domains != [],
       do: "degraded"

  defp coverage_status(_run_status, _requested_domains, _missing_domains, failed_domains)
       when failed_domains != [],
       do: "degraded"

  defp coverage_status(_run_status, _requested_domains, _missing_domains, _failed_domains),
    do: "complete"

  defp degrade_policy_ref(nil), do: nil

  defp degrade_policy_ref(%{"outcome" => outcome, "missing_domains" => missing_domains}) do
    %{
      "outcome" => outcome,
      "missing_domains" => missing_domains,
      "artifact" => "review/degrade_policy.json"
    }
  end

  defp render_domains([]), do: "none"
  defp render_domains(domains), do: Enum.join(domains, ", ")
end
