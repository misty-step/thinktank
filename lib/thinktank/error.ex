defmodule Thinktank.Error do
  @moduledoc """
  Structured error type for programmatic consumption.
  """

  @derive Jason.Encoder
  defstruct [:code, :message, :details]

  @type t :: %__MODULE__{
          code: atom(),
          message: binary(),
          details: map()
        }

  @known_reasons %{
    missing_input_text: "input text is required",
    no_successful_agents: "no agents completed successfully",
    no_git_repository: "workspace is not a git repository — review requires git"
  }

  @contract_reasons %{
    degraded_run: "one or more agents failed",
    review_eval_degraded: "one or more review eval cases degraded",
    review_eval_failed: "one or more review eval cases failed"
  }

  @spec from_reason(term()) :: t()
  def from_reason(%__MODULE__{} = error), do: error

  def from_reason(reason) when is_atom(reason) do
    %__MODULE__{
      code: reason,
      message: Map.get(@known_reasons, reason, Atom.to_string(reason)),
      details: %{}
    }
  end

  def from_reason(reason) when is_binary(reason) do
    %__MODULE__{code: :run_error, message: reason, details: %{}}
  end

  def from_reason(%{category: cat} = map) do
    %__MODULE__{
      code: cat,
      message: map[:message] || "agent error",
      details: map
    }
  end

  def from_reason(other) do
    %__MODULE__{code: :unknown, message: inspect(other), details: %{}}
  end

  @spec from_contract(atom(), map()) :: t()
  def from_contract(code, details \\ %{}) when is_atom(code) and is_map(details) do
    from_reason(
      Map.merge(
        %{category: code, message: Map.get(@contract_reasons, code, Atom.to_string(code))},
        details
      )
    )
  end
end
