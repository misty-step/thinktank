defmodule Thinktank.ProviderSpec do
  @moduledoc """
  Typed provider configuration for workflow execution.
  """

  @valid_adapters %{
    "openrouter" => :openrouter
  }

  @enforce_keys [:id, :adapter, :credential_env]
  defstruct [:id, :adapter, :credential_env, defaults: %{}]

  @type t :: %__MODULE__{
          id: String.t(),
          adapter: atom(),
          credential_env: String.t(),
          defaults: map()
        }

  @spec from_pair(String.t(), map()) :: {:ok, t()} | {:error, String.t()}
  def from_pair(id, %{} = raw) when is_binary(id) do
    with {:ok, adapter} <- parse_adapter(raw["adapter"]),
         {:ok, credential_env} <- parse_credential_env(raw["credential_env"]) do
      {:ok,
       %__MODULE__{
         id: id,
         adapter: adapter,
         credential_env: credential_env,
         defaults: Map.get(raw, "defaults", %{})
       }}
    end
  end

  def from_pair(id, _raw), do: {:error, "provider #{id} must be a map"}

  defp parse_adapter(adapter) when is_atom(adapter), do: parse_adapter(Atom.to_string(adapter))

  defp parse_adapter(adapter) when is_binary(adapter) and adapter != "" do
    case Map.fetch(@valid_adapters, adapter) do
      {:ok, parsed} ->
        {:ok, parsed}

      :error ->
        {:error, "provider adapter must be one of #{Enum.join(Map.keys(@valid_adapters), ", ")}"}
    end
  end

  defp parse_adapter(_), do: {:error, "provider adapter is required"}

  defp parse_credential_env(env) when is_binary(env) and env != "", do: {:ok, env}
  defp parse_credential_env(_), do: {:error, "provider credential_env is required"}
end
