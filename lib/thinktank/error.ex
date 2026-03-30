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
    no_successful_agents: "no agents completed successfully"
  }

  @spec from_reason(term()) :: t()
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
end
