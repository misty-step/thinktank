defmodule Thinktank.Template do
  @moduledoc """
  Small placeholder renderer used by workflow prompts.
  """

  @placeholder ~r/\{\{([^}]+)\}\}/

  @spec render(String.t(), map()) :: String.t()
  def render(template, vars) when is_binary(template) and is_map(vars) do
    vars = stringify_keys(vars)

    Regex.replace(@placeholder, template, fn _match, key ->
      vars
      |> Map.get(String.trim(key))
      |> stringify()
    end)
  end

  defp stringify(value) when is_binary(value), do: value
  defp stringify(value) when is_integer(value) or is_float(value), do: to_string(value)
  defp stringify(value) when is_boolean(value), do: to_string(value)
  defp stringify(value) when is_list(value), do: Enum.map_join(value, "\n", &stringify/1)
  defp stringify(%{} = value), do: Jason.encode!(value, pretty: true)
  defp stringify(nil), do: ""
  defp stringify(value), do: inspect(value)

  defp stringify_keys(map) do
    map
    |> Enum.map(fn {key, value} -> {to_string(key), value} end)
    |> Enum.into(%{})
  end
end
