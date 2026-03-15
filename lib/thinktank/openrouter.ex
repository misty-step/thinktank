defmodule Thinktank.OpenRouter do
  @moduledoc """
  Thin HTTP client for OpenRouter chat completions.

  Supports plain text and structured (JSON schema) responses.
  Callers own retry and rate-limit backoff.
  """

  @base_url "https://openrouter.ai/api/v1"

  @spec chat(String.t(), String.t(), String.t(), keyword()) ::
          {:ok, String.t() | nil} | {:error, map()}
  def chat(model, system_prompt, user_prompt, opts \\ []) do
    with {:ok, key} <- require_key(opts) do
      build_req(key, opts)
      |> Req.post(
        url: "/chat/completions",
        json: %{model: model, messages: messages(system_prompt, user_prompt)}
      )
      |> handle_response(&extract_text/1)
    end
  end

  @spec chat_structured(String.t(), String.t(), String.t(), map(), keyword()) ::
          {:ok, map()} | {:error, map()}
  def chat_structured(model, system_prompt, user_prompt, json_schema, opts \\ []) do
    with {:ok, key} <- require_key(opts) do
      body = %{
        model: model,
        messages: messages(system_prompt, user_prompt),
        response_format: %{
          type: "json_schema",
          json_schema: %{name: "response", schema: json_schema}
        }
      }

      build_req(key, opts)
      |> Req.post(url: "/chat/completions", json: body)
      |> handle_response(&extract_json/1)
    end
  end

  defp build_req(key, opts) do
    base = [
      base_url: Keyword.get(opts, :base_url, @base_url),
      headers: [
        {"authorization", "Bearer #{key}"},
        {"http-referer", "https://github.com/misty-step/thinktank"},
        {"x-title", "thinktank"}
      ]
    ]

    extra = if plug = Keyword.get(opts, :plug), do: [plug: plug], else: []
    Req.new(base ++ extra)
  end

  defp messages(system_prompt, user_prompt) do
    [
      %{role: "system", content: system_prompt},
      %{role: "user", content: user_prompt}
    ]
  end

  defp require_key(opts) do
    key =
      Keyword.get_lazy(opts, :api_key, fn ->
        non_empty_env("THINKTANK_OPENROUTER_API_KEY") || non_empty_env("OPENROUTER_API_KEY")
      end)

    case key do
      nil ->
        {:error,
         %{
           category: :missing_api_key,
           message: "Set THINKTANK_OPENROUTER_API_KEY or OPENROUTER_API_KEY"
         }}

      "" ->
        {:error, %{category: :missing_api_key, message: "API key is empty"}}

      key ->
        {:ok, key}
    end
  end

  defp handle_response({:ok, %{status: 200, body: body}}, extractor), do: extractor.(body)

  defp handle_response({:ok, %{status: 401, body: body}}, _),
    do: {:error, %{category: :auth, message: error_message(body) || "unauthorized"}}

  defp handle_response({:ok, %{status: 429} = resp}, _),
    do:
      {:error,
       %{
         category: :rate_limit,
         retry_after: Req.Response.get_header(resp, "retry-after") |> List.first()
       }}

  defp handle_response({:ok, %{status: status, body: body}}, _),
    do: {:error, %{category: :api_error, status: status, message: error_message(body)}}

  defp handle_response({:error, reason}, _),
    do: {:error, %{category: :transport, message: inspect(reason)}}

  defp extract_text(body) do
    {:ok, get_in(body, ["choices", Access.at(0), "message", "content"])}
  end

  defp extract_json(body) do
    case get_in(body, ["choices", Access.at(0), "message", "content"]) do
      nil -> {:error, %{category: :invalid_json, raw: nil}}
      raw when is_binary(raw) -> Jason.decode(raw) |> wrap_json(raw)
      other -> {:error, %{category: :invalid_json, raw: other}}
    end
  end

  defp wrap_json({:ok, parsed}, _raw), do: {:ok, parsed}
  defp wrap_json({:error, _}, raw), do: {:error, %{category: :invalid_json, raw: raw}}

  defp non_empty_env(name) do
    case System.get_env(name) do
      nil -> nil
      "" -> nil
      val -> val
    end
  end

  defp error_message(%{"error" => %{"message" => msg}}) when is_binary(msg), do: msg
  defp error_message(body) when is_binary(body), do: body
  defp error_message(_), do: nil
end
