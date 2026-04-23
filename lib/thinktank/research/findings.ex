defmodule Thinktank.Research.Findings do
  @moduledoc """
  Structured research findings contract.
  """

  @schema_version 1
  @confidence_levels ~w(high medium low unknown)

  @spec schema_prompt() :: String.t()
  def schema_prompt do
    """
    {
      "thesis": "one-sentence synthesis of the strongest conclusion",
      "findings": [
        {
          "claim": "specific finding or recommendation",
          "evidence": ["file, command, source, or agent-output reference"],
          "confidence": "high|medium|low"
        }
      ],
      "evidence": [
        {
          "source": "file, command, source, or agent name",
          "summary": "what this evidence supports"
        }
      ],
      "open_questions": ["question that remains unresolved"],
      "confidence": "high|medium|low"
    }
    """
    |> String.trim()
  end

  @spec from_synthesis_output(String.t()) :: map()
  def from_synthesis_output(output) when is_binary(output) do
    case Jason.decode(output) do
      {:ok, %{} = payload} ->
        from_payload(payload, output)

      {:ok, _other} ->
        invalid("invalid_shape", "research findings synthesis must return a JSON object", output)

      {:error, error} ->
        invalid(
          "invalid_json",
          "research findings synthesis returned invalid JSON: #{Exception.message(error)}",
          output
        )
    end
  end

  @spec complete?(map()) :: boolean()
  def complete?(%{"status" => "complete"}), do: true
  def complete?(_findings), do: false

  @spec error(map()) :: map() | nil
  def error(%{"error" => error}), do: error
  def error(_findings), do: nil

  @spec synthesis_failed(map() | nil) :: map()
  def synthesis_failed(error) do
    unavailable("synthesis_failed", "research synthesis failed before findings were available", %{
      "error" => normalize(error)
    })
  end

  @spec partial(map()) :: map()
  def partial(details \\ %{}) do
    base("partial", %{
      "category" => "partial_run",
      "message" => "research findings are unavailable because the run completed as partial",
      "details" => normalize(details)
    })
  end

  @spec to_markdown(map()) :: String.t()
  def to_markdown(%{"status" => "complete"} = findings) do
    """
    # Research Synthesis

    #{findings["thesis"]}

    ## Findings

    #{render_findings(findings["findings"])}

    ## Evidence

    #{render_evidence(findings["evidence"])}

    ## Open Questions

    #{render_open_questions(findings["open_questions"])}

    Confidence: #{findings["confidence"]}
    """
    |> String.trim()
  end

  defp from_payload(payload, raw_output) do
    with {:ok, thesis} <- required_string(payload, "thesis"),
         {:ok, findings} <- required_list(payload, "findings", &finding/1),
         {:ok, evidence} <- required_list(payload, "evidence", &evidence/1),
         {:ok, open_questions} <- required_list(payload, "open_questions", &open_question/1),
         {:ok, confidence} <- required_confidence(payload, "confidence") do
      %{
        "schema_version" => @schema_version,
        "status" => "complete",
        "thesis" => thesis,
        "findings" => findings,
        "evidence" => evidence,
        "open_questions" => open_questions,
        "confidence" => confidence,
        "error" => nil
      }
    else
      {:error, category, message} -> invalid(category, message, raw_output)
    end
  end

  defp required_string(payload, key) do
    case payload[key] do
      value when is_binary(value) ->
        value = String.trim(value)
        if value == "", do: missing_or_invalid(key), else: {:ok, value}

      _ ->
        missing_or_invalid(key)
    end
  end

  defp required_list(payload, key, normalize_entry) do
    case payload[key] do
      values when is_list(values) ->
        normalize_list(values, normalize_entry, missing_or_invalid(key))

      _ ->
        missing_or_invalid(key)
    end
  end

  defp missing_or_invalid(key) do
    {:error, "invalid_shape", "research findings field #{inspect(key)} is missing or invalid"}
  end

  defp finding(%{} = finding) do
    with {:ok, claim} <- string_field(finding, "claim"),
         {:ok, evidence} <- string_list_field(finding, "evidence"),
         {:ok, confidence} <- required_finding_confidence(finding, "confidence") do
      {:ok, %{"claim" => claim, "evidence" => evidence, "confidence" => confidence}}
    end
  end

  defp finding(_value), do: :error

  defp evidence(%{} = evidence) do
    with {:ok, source} <- string_field(evidence, "source"),
         {:ok, summary} <- string_field(evidence, "summary") do
      {:ok, %{"source" => source, "summary" => summary}}
    end
  end

  defp evidence(_value), do: :error

  defp open_question(value) when is_binary(value), do: present_string(value)
  defp open_question(_value), do: :error

  defp string_field(payload, key) do
    case payload[key] do
      value when is_binary(value) -> present_string(value)
      _ -> :error
    end
  end

  defp string_list_field(payload, key) do
    case payload[key] do
      values when is_list(values) -> normalize_list(values, &present_binary_string/1, :error)
      _ -> :error
    end
  end

  defp normalize_list(values, normalize_entry, invalid_result) do
    values
    |> Enum.reduce_while({:ok, []}, fn
      value, {:ok, acc} ->
        case normalize_entry.(value) do
          {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
          :error -> {:halt, invalid_result}
        end

      _value, _acc ->
        {:halt, invalid_result}
    end)
    |> case do
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      error -> error
    end
  end

  defp present_binary_string(value) when is_binary(value), do: present_string(value)
  defp present_binary_string(_value), do: :error

  defp present_string(value) do
    value = String.trim(value)
    if value == "", do: :error, else: {:ok, value}
  end

  defp required_confidence(payload, key) do
    case normalize_confidence(payload[key]) do
      "unknown" -> missing_or_invalid(key)
      confidence -> {:ok, confidence}
    end
  end

  defp required_finding_confidence(payload, key) do
    case normalize_confidence(payload[key]) do
      confidence when confidence in ~w(high medium low) -> {:ok, confidence}
      _ -> :error
    end
  end

  defp normalize_confidence(value) when is_binary(value) do
    value = value |> String.downcase() |> String.trim()
    if value in @confidence_levels, do: value, else: "unknown"
  end

  defp normalize_confidence(_value), do: "unknown"

  defp invalid(category, message, raw_output) do
    base("invalid", %{
      "category" => category,
      "message" => message,
      "raw_output_sha256" => sha256(raw_output)
    })
  end

  defp unavailable(category, message, details) do
    base("unavailable", %{
      "category" => category,
      "message" => message,
      "details" => normalize(details)
    })
  end

  defp base(status, error) do
    %{
      "schema_version" => @schema_version,
      "status" => status,
      "thesis" => nil,
      "findings" => [],
      "evidence" => [],
      "open_questions" => [],
      "confidence" => "unknown",
      "error" => error
    }
  end

  defp render_findings([]), do: "_No findings were returned._"

  defp render_findings(findings) do
    Enum.map_join(findings, "\n", fn finding ->
      evidence =
        case finding["evidence"] do
          [] -> ""
          refs -> " Evidence: #{Enum.join(refs, "; ")}."
        end

      "- #{finding["claim"]} (confidence: #{finding["confidence"]}).#{evidence}"
    end)
  end

  defp render_evidence([]), do: "_No evidence was returned._"

  defp render_evidence(evidence) do
    Enum.map_join(evidence, "\n", fn item ->
      "- #{item["source"]}: #{item["summary"]}"
    end)
  end

  defp render_open_questions([]), do: "_No open questions._"

  defp render_open_questions(questions) do
    Enum.map_join(questions, "\n", &"- #{&1}")
  end

  defp normalize(value) when is_map(value),
    do: Map.new(value, fn {key, val} -> {to_string(key), normalize(val)} end)

  defp normalize(value) when is_list(value), do: Enum.map(value, &normalize/1)
  defp normalize(value) when is_binary(value) or is_number(value) or is_boolean(value), do: value
  defp normalize(nil), do: nil
  defp normalize(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize(value), do: inspect(value)

  defp sha256(value) do
    :crypto.hash(:sha256, value)
    |> Base.encode16(case: :lower)
  end
end
