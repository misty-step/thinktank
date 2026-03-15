defmodule Thinktank.OpenRouter do
  @moduledoc """
  Thin HTTP client for OpenRouter chat completions.

  Supports plain text and structured (JSON schema) responses.
  Callers own retry and rate-limit backoff.
  """

  @base_url "https://openrouter.ai/api/v1"

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
    case Keyword.get(opts, :api_key, System.get_env("OPENROUTER_API_KEY")) do
      nil -> {:error, %{category: :missing_api_key, message: "OPENROUTER_API_KEY not set"}}
      "" -> {:error, %{category: :missing_api_key, message: "OPENROUTER_API_KEY is empty"}}
      key -> {:ok, key}
    end
  end

  defp handle_response({:ok, %{status: 200, body: body}}, extractor), do: extractor.(body)

  defp handle_response({:ok, %{status: 401, body: body}}, _),
    do:
      {:error, %{category: :auth, message: get_in(body, ["error", "message"]) || "unauthorized"}}

  defp handle_response({:ok, %{status: 429} = resp}, _),
    do:
      {:error,
       %{
         category: :rate_limit,
         retry_after: Req.Response.get_header(resp, "retry-after") |> List.first()
       }}

  defp handle_response({:ok, %{status: status, body: body}}, _),
    do:
      {:error,
       %{category: :api_error, status: status, message: get_in(body, ["error", "message"])}}

  defp handle_response({:error, reason}, _),
    do: {:error, %{category: :transport, message: inspect(reason)}}

  defp extract_text(body) do
    {:ok, get_in(body, ["choices", Access.at(0), "message", "content"])}
  end

  defp extract_json(body) do
    raw = get_in(body, ["choices", Access.at(0), "message", "content"])

    case Jason.decode(raw) do
      {:ok, parsed} -> {:ok, parsed}
      {:error, _} -> {:error, %{category: :invalid_json, raw: raw}}
    end
  end
end
