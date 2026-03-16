defmodule Thinktank.OpenRouterTest do
  use ExUnit.Case, async: true

  alias Thinktank.OpenRouter

  @test_opts [api_key: "test-key", plug: {Req.Test, OpenRouter}]

  defp success_plug(conn) do
    Req.Test.json(conn, %{
      "choices" => [%{"message" => %{"content" => "Hello from the model"}}],
      "usage" => %{"prompt_tokens" => 10, "completion_tokens" => 20, "total_tokens" => 30},
      "cost" => 0.00015
    })
  end

  defp structured_plug(conn) do
    Req.Test.json(conn, %{
      "choices" => [
        %{"message" => %{"content" => Jason.encode!(%{"name" => "Alice", "age" => 30})}}
      ],
      "usage" => %{"prompt_tokens" => 10, "completion_tokens" => 20, "total_tokens" => 30},
      "cost" => 0.00015
    })
  end

  defp auth_error_plug(conn) do
    conn
    |> Plug.Conn.put_status(401)
    |> Req.Test.json(%{"error" => %{"message" => "Invalid API key"}})
  end

  defp rate_limit_plug(conn) do
    conn
    |> Plug.Conn.put_status(429)
    |> Plug.Conn.put_resp_header("retry-after", "5")
    |> Req.Test.json(%{"error" => %{"message" => "Rate limited"}})
  end

  defp capture_request_plug(test_pid) do
    fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:request, conn, body})

      Req.Test.json(conn, %{
        "choices" => [%{"message" => %{"content" => "ok"}}],
        "usage" => %{"prompt_tokens" => 1, "completion_tokens" => 1, "total_tokens" => 2},
        "cost" => 0.0001
      })
    end
  end

  describe "chat/4" do
    test "returns {:ok, text, usage} on success" do
      Req.Test.stub(OpenRouter, &success_plug/1)

      assert {:ok, "Hello from the model", _usage} =
               OpenRouter.chat("test-model", "system prompt", "user prompt", @test_opts)
    end

    test "returns {:error, %{category: :auth}} on 401" do
      Req.Test.stub(OpenRouter, &auth_error_plug/1)

      assert {:error, %{category: :auth, message: message}} =
               OpenRouter.chat("test-model", "system", "user", @test_opts)

      assert message =~ "Invalid API key"
    end

    test "returns {:error, %{category: :rate_limit}} on 429" do
      Req.Test.stub(OpenRouter, &rate_limit_plug/1)

      assert {:error, %{category: :rate_limit, retry_after: "5"}} =
               OpenRouter.chat("test-model", "system", "user", @test_opts)
    end

    test "returns {:error, %{category: :api_error}} on 500" do
      Req.Test.stub(OpenRouter, fn conn ->
        conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{"error" => %{"message" => "boom"}})
      end)

      assert {:error, %{category: :api_error, status: 500}} =
               OpenRouter.chat("test-model", "system", "user", @test_opts)
    end

    test "returns {:error, %{category: :missing_api_key}} when no key provided" do
      assert {:error, %{category: :missing_api_key}} =
               OpenRouter.chat("test-model", "system", "user", api_key: nil)
    end
  end

  describe "chat_structured/5" do
    test "returns {:ok, parsed_map, usage} on success" do
      Req.Test.stub(OpenRouter, &structured_plug/1)

      schema = %{
        "type" => "object",
        "properties" => %{"name" => %{"type" => "string"}, "age" => %{"type" => "integer"}}
      }

      assert {:ok, %{"name" => "Alice", "age" => 30}, _usage} =
               OpenRouter.chat_structured("test-model", "system", "user", schema, @test_opts)
    end

    test "returns {:error, :invalid_json} when response is not valid JSON" do
      Req.Test.stub(OpenRouter, fn conn ->
        Req.Test.json(conn, %{"choices" => [%{"message" => %{"content" => "not json"}}]})
      end)

      assert {:error, %{category: :invalid_json}} =
               OpenRouter.chat_structured("test-model", "system", "user", %{}, @test_opts)
    end

    test "returns {:error, :invalid_json} when content is nil" do
      Req.Test.stub(OpenRouter, fn conn ->
        Req.Test.json(conn, %{"choices" => [%{"message" => %{"content" => nil}}]})
      end)

      assert {:error, %{category: :invalid_json, raw: nil}} =
               OpenRouter.chat_structured("test-model", "system", "user", %{}, @test_opts)
    end

    test "returns {:error, :invalid_json} when choices is empty" do
      Req.Test.stub(OpenRouter, fn conn ->
        Req.Test.json(conn, %{"choices" => []})
      end)

      assert {:error, %{category: :invalid_json, raw: nil}} =
               OpenRouter.chat_structured("test-model", "system", "user", %{}, @test_opts)
    end
  end

  describe "error body handling" do
    test "handles plain text error body on 500" do
      Req.Test.stub(OpenRouter, fn conn ->
        conn
        |> Plug.Conn.put_status(502)
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.send_resp(502, "Bad Gateway")
      end)

      assert {:error, %{category: :api_error, status: 502, message: "Bad Gateway"}} =
               OpenRouter.chat("test-model", "system", "user", @test_opts)
    end
  end

  describe "usage extraction" do
    test "returns usage data from response" do
      Req.Test.stub(OpenRouter, &success_plug/1)

      assert {:ok, _, usage} =
               OpenRouter.chat("test-model", "system", "user", @test_opts)

      assert usage.prompt_tokens == 10
      assert usage.completion_tokens == 20
      assert usage.total_tokens == 30
      assert usage.cost == 0.00015
    end

    test "returns zero usage when usage field is missing" do
      Req.Test.stub(OpenRouter, fn conn ->
        Req.Test.json(conn, %{
          "choices" => [%{"message" => %{"content" => "no usage here"}}]
        })
      end)

      assert {:ok, "no usage here", usage} =
               OpenRouter.chat("test-model", "system", "user", @test_opts)

      assert usage == %{prompt_tokens: 0, completion_tokens: 0, total_tokens: 0, cost: 0.0}
    end
  end

  describe "headers" do
    test "includes HTTP-Referer and X-Title" do
      Req.Test.stub(OpenRouter, capture_request_plug(self()))

      OpenRouter.chat("test-model", "system", "user", @test_opts)

      assert_receive {:request, conn, _body}
      headers = Map.new(conn.req_headers)
      assert Map.has_key?(headers, "http-referer")
      assert Map.has_key?(headers, "x-title")
    end

    test "includes authorization bearer token" do
      Req.Test.stub(OpenRouter, capture_request_plug(self()))

      opts = Keyword.put(@test_opts, :api_key, "sk-test-123")
      OpenRouter.chat("test-model", "system", "user", opts)

      assert_receive {:request, conn, _body}
      headers = Map.new(conn.req_headers)
      assert headers["authorization"] == "Bearer sk-test-123"
    end
  end
end
