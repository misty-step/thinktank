defmodule Thinktank.Integration.ReviewBenchCapabilityTest do
  @moduledoc """
  Probes the live OpenRouter catalog to assert every tool-using agent in the
  built-in `review/default` bench (reviewers, planner, synthesizer) is wired
  to a model whose endpoints advertise `tools` in `supported_parameters`.
  Catches the class of regression filed as backlog 019: silent tool-capability
  drift between the bench's declared `@agent_tools`/`@summary_tools` and a
  configured model.

  Tagged `:integration` because it hits `openrouter.ai`. Gated on
  `OPENROUTER_API_KEY`: absent, the test emits a loud stderr notice and
  passes as a no-op (the `:integration` tag excludes it from the default
  `mix test` run, so the no-op path only triggers when a caller opts in
  without providing a key).
  """

  use ExUnit.Case, async: false

  @moduletag :integration

  alias Thinktank.Builtin

  @endpoints_url "https://openrouter.ai/api/v1/models"

  test "every tool-using review/default agent uses a tool-capable OpenRouter model" do
    api_key =
      System.get_env("OPENROUTER_API_KEY") || System.get_env("THINKTANK_OPENROUTER_API_KEY")

    if is_nil(api_key) or api_key == "" do
      IO.warn(
        "integration test skipped: OPENROUTER_API_KEY not set (nothing was probed)",
        []
      )

      :ok
    else
      config = Builtin.raw_config()
      bench = get_in(config, ["benches", "review/default"])
      agents_map = Map.fetch!(config, "agents")

      agent_names =
        ([bench["planner"] | bench["agents"]] ++ [bench["synthesizer"]])
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()

      results =
        Enum.map(agent_names, fn name ->
          model = agents_map |> Map.fetch!(name) |> Map.fetch!("model")
          {name, model, tool_capable?(model, api_key)}
        end)

      failures =
        Enum.reject(results, fn
          {_name, _model, {:ok, true}} -> true
          _ -> false
        end)

      assert failures == [],
             "tool-capability check failed for:\n" <>
               Enum.map_join(failures, "\n", fn {name, model, result} ->
                 "  #{name} (#{model}): #{inspect(result)}"
               end)
    end
  end

  defp tool_capable?(model, api_key) do
    url = "#{@endpoints_url}/#{model}/endpoints"
    args = ["-sS", "-H", "Authorization: Bearer #{api_key}", url]

    case System.cmd("curl", args, stderr_to_stdout: true) do
      {body, 0} -> parse_endpoints(body)
      {body, code} -> {:error, {:curl_failed, code, body}}
    end
  end

  defp parse_endpoints(body) do
    with {:ok, decoded} <- Jason.decode(body),
         endpoints when is_list(endpoints) <- get_in(decoded, ["data", "endpoints"]) do
      {:ok, Enum.any?(endpoints, &tool_endpoint?/1)}
    else
      other -> {:error, {:unexpected_payload, other}}
    end
  end

  defp tool_endpoint?(endpoint) do
    "tools" in (endpoint["supported_parameters"] || [])
  end
end
