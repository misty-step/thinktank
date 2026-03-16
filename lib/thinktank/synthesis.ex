defmodule Thinktank.Synthesis do
  @moduledoc """
  Structured synthesis of role-labeled perspective outputs.

  Combines N perspective analyses into coherent insight with explicit
  agreement/disagreement analysis, confidence assessment, and actionable
  recommendations. Uses system/user message separation: system constrains
  format, user carries the perspective outputs.

  Retries up to 3 times with exponential backoff on failure.
  """

  alias Thinktank.{Models, OpenRouter}

  @max_attempts 3
  @default_backoff_base 1000

  @system_prompt """
  You are a research synthesizer. You receive analysis from multiple expert perspectives \
  on the same question. Your job is to produce a structured synthesis that extracts maximum \
  insight from their combined analysis.

  Output format (use these exact headings):

  ## Agreement
  Points where perspectives converge. Cite which perspectives agree and on what.

  ## Disagreement
  Points where perspectives diverge. Assess which position is more likely correct and why.

  ## Confidence
  Your confidence level in each key finding (high/medium/low) with reasoning.

  ## Recommendations
  Actionable next steps, grounded in the evidence from perspectives. Prioritize by impact.\
  """

  @doc """
  Synthesize perspective outputs into structured insight.

  Takes a list of `{role, text}` tuples and the original instruction.

  Options:
    - `:synthesis_model` — explicit model override
    - `:tier` — model tier (default `:standard`), used when no `:synthesis_model` given
    - `:openrouter_opts` — keyword opts forwarded to `OpenRouter.chat/4`
    - `:backoff_base` — base backoff in ms (default 1000, set low in tests)
  """
  @spec synthesize([{String.t(), String.t()}], String.t(), keyword()) ::
          {:ok, String.t(), OpenRouter.usage()} | {:error, map()}
  def synthesize(perspectives, instruction, opts \\ []) do
    tier = Keyword.get(opts, :tier, :standard)
    model = opts[:synthesis_model] || Models.synthesis_model(tier)
    or_opts = opts[:openrouter_opts] || []
    backoff_base = opts[:backoff_base] || @default_backoff_base
    user_prompt = build_user_prompt(perspectives, instruction)

    retry(model, user_prompt, or_opts, backoff_base, 1)
  end

  defp retry(_model, _prompt, _or_opts, _backoff_base, attempt) when attempt > @max_attempts do
    {:error, %{category: :synthesis_failed, message: "all #{@max_attempts} attempts failed"}}
  end

  defp retry(model, prompt, or_opts, backoff_base, attempt) do
    case OpenRouter.chat(model, @system_prompt, prompt, or_opts) do
      {:ok, text, usage} ->
        {:ok, text, usage}

      {:error, _} = err ->
        if attempt < @max_attempts do
          backoff = backoff_base * Integer.pow(2, attempt - 1)
          Process.sleep(backoff)
          retry(model, prompt, or_opts, backoff_base, attempt + 1)
        else
          err
        end
    end
  end

  defp build_user_prompt(perspectives, instruction) do
    perspectives_text =
      Enum.map_join(perspectives, "\n\n", fn {role, text} ->
        "### #{role}\n#{text}"
      end)

    """
    Original research question: #{instruction}

    ---

    The following expert perspectives were gathered. Synthesize them into a unified analysis.

    #{perspectives_text}
    """
  end
end
