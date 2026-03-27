defmodule Thinktank.Review.Verdict do
  @moduledoc """
  Parser and validator for reviewer JSON verdicts.
  """

  @required_root_keys ~w(reviewer perspective verdict confidence summary findings stats)
  @required_finding_keys ~w(severity category title description suggestion file line)
  @required_stats_keys ~w(files_reviewed files_with_issues critical major minor info)
  @valid_verdicts MapSet.new(~w(PASS WARN FAIL SKIP))
  @valid_severities MapSet.new(~w(critical major minor info))

  @type finding :: %{
          severity: String.t(),
          category: String.t(),
          title: String.t(),
          description: String.t(),
          suggestion: String.t(),
          file: String.t(),
          line: non_neg_integer()
        }

  @type t :: %{
          reviewer: String.t(),
          perspective: String.t(),
          verdict: String.t(),
          confidence: float(),
          summary: String.t(),
          findings: [finding()],
          stats: map()
        }

  @spec parse(String.t()) :: {:ok, t()} | {:error, term()}
  def parse(text) when is_binary(text) do
    with {:ok, json_text} <- extract_json(text),
         {:ok, map} <- Jason.decode(json_text),
         {:ok, verdict} <- validate(map) do
      {:ok, verdict}
    end
  end

  @spec validate(map()) :: {:ok, t()} | {:error, term()}
  def validate(map) when is_map(map) do
    with :ok <- check_required_keys(map),
         :ok <- check_verdict(map["verdict"]),
         {:ok, confidence} <- normalize_confidence(map["confidence"]),
         {:ok, findings} <- validate_findings(map["findings"]),
         :ok <- validate_stats(map["stats"]) do
      {:ok,
       %{
         reviewer: map["reviewer"],
         perspective: map["perspective"],
         verdict: map["verdict"],
         confidence: confidence,
         summary: map["summary"],
         findings: findings,
         stats: map["stats"]
       }}
    end
  end

  def validate(_), do: {:error, :verdict_must_be_object}

  defp extract_json(text) do
    case Regex.scan(~r/```json\s*\n(.*?)```/s, text) do
      [] ->
        trimmed = String.trim(text)
        if String.starts_with?(trimmed, "{"), do: {:ok, trimmed}, else: {:error, :no_json_block}

      matches ->
        [_, json] = List.last(matches)
        {:ok, String.trim(json)}
    end
  end

  defp check_required_keys(map) do
    missing = Enum.filter(@required_root_keys, &(not Map.has_key?(map, &1)))
    if missing == [], do: :ok, else: {:error, {:missing_keys, missing}}
  end

  defp check_verdict(verdict) when is_binary(verdict) do
    if MapSet.member?(@valid_verdicts, verdict), do: :ok, else: {:error, {:invalid_verdict, verdict}}
  end

  defp check_verdict(_), do: {:error, :invalid_verdict}

  defp normalize_confidence(value) when is_integer(value) and value >= 0 and value <= 100 do
    normalized = if value > 1, do: value / 100.0, else: value * 1.0
    {:ok, normalized}
  end

  defp normalize_confidence(value) when is_float(value) and value >= 0.0 and value <= 100.0 do
    normalized = if value > 1.0, do: value / 100.0, else: value
    {:ok, normalized}
  end

  defp normalize_confidence(_), do: {:error, :invalid_confidence}

  defp validate_findings(findings) when is_list(findings) do
    findings
    |> Enum.reduce_while({:ok, []}, fn finding, {:ok, acc} ->
      case validate_finding(finding) do
        {:ok, valid} -> {:cont, {:ok, [valid | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      error -> error
    end
  end

  defp validate_findings(_), do: {:error, :findings_must_be_list}

  defp validate_finding(%{} = finding) do
    missing = Enum.filter(@required_finding_keys, &(not Map.has_key?(finding, &1)))

    cond do
      missing != [] ->
        {:error, {:missing_finding_keys, missing}}

      not MapSet.member?(@valid_severities, finding["severity"]) ->
        {:error, {:invalid_severity, finding["severity"]}}

      not is_integer(finding["line"]) or finding["line"] < 0 ->
        {:error, {:invalid_line, finding["line"]}}

      true ->
        {:ok,
         %{
           severity: finding["severity"],
           category: finding["category"],
           title: finding["title"],
           description: finding["description"],
           suggestion: finding["suggestion"],
           file: finding["file"],
           line: finding["line"]
         }}
    end
  end

  defp validate_finding(_), do: {:error, :invalid_finding}

  defp validate_stats(%{} = stats) do
    missing = Enum.filter(@required_stats_keys, &(not Map.has_key?(stats, &1)))

    cond do
      missing != [] ->
        {:error, {:missing_stats_keys, missing}}

      Enum.any?(@required_stats_keys, fn key -> not is_integer(stats[key]) end) ->
        {:error, :stats_values_must_be_integers}

      true ->
        :ok
    end
  end

  defp validate_stats(_), do: {:error, :stats_must_be_object}
end
