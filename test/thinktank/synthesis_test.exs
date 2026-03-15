defmodule Thinktank.SynthesisTest do
  use ExUnit.Case, async: true

  alias Thinktank.Synthesis

  @test_opts [api_key: "test-key", plug: {Req.Test, Synthesis}]

  @perspectives [
    {"security auditor", "The code has SQL injection vulnerabilities in the user input handler."},
    {"performance engineer", "The N+1 query pattern in the dashboard will degrade at scale."},
    {"architecture reviewer",
     "The service layer is well-structured but coupling between modules is tight."},
    {"UX researcher", "The error messages are developer-facing, not user-friendly."}
  ]

  defp synthesis_response(text) do
    fn conn ->
      Req.Test.json(conn, %{
        "choices" => [%{"message" => %{"content" => text}}]
      })
    end
  end

  defp full_synthesis_text do
    """
    ## Agreement
    All perspectives agree that input validation needs improvement.

    ## Disagreement
    Security prioritizes immediate remediation while architecture suggests a phased approach.
    The security auditor's urgency is more appropriate given the severity.

    ## Confidence
    - SQL injection finding: high — concrete, verifiable vulnerability
    - N+1 query concern: medium — depends on actual traffic patterns
    - Coupling assessment: medium — subjective without dependency metrics
    - UX gap: high — error messages are clearly developer-oriented

    ## Recommendations
    1. Fix SQL injection immediately (security)
    2. Add query batching for dashboard (performance)
    3. Improve error messages for end users (UX)
    4. Plan module decoupling in next sprint (architecture)
    """
  end

  describe "synthesize/3" do
    test "returns {:ok, text} containing all required sections" do
      Req.Test.stub(Synthesis, synthesis_response(full_synthesis_text()))

      assert {:ok, text} =
               Synthesis.synthesize(@perspectives, "review this auth flow",
                 openrouter_opts: @test_opts
               )

      assert text =~ "## Agreement"
      assert text =~ "## Disagreement"
      assert text =~ "## Confidence"
      assert text =~ "## Recommendations"
    end

    test "sends system message with format constraints and user message with perspectives" do
      test_pid = self()

      Req.Test.stub(Synthesis, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:synthesis_request, Jason.decode!(body)})

        Req.Test.json(conn, %{
          "choices" => [%{"message" => %{"content" => full_synthesis_text()}}]
        })
      end)

      Synthesis.synthesize(@perspectives, "review this auth flow", openrouter_opts: @test_opts)

      assert_receive {:synthesis_request, body}
      [system, user] = body["messages"]

      assert system["role"] == "system"
      assert system["content"] =~ "Agreement"
      assert system["content"] =~ "Disagreement"
      assert system["content"] =~ "Confidence"
      assert system["content"] =~ "Recommendations"

      assert user["role"] == "user"
      assert user["content"] =~ "security auditor"
      assert user["content"] =~ "SQL injection"
      assert user["content"] =~ "review this auth flow"
    end

    test "retries up to 3 times on failure with exponential backoff" do
      test_pid = self()
      call_count = :counters.new(1, [:atomics])

      Req.Test.stub(Synthesis, fn conn ->
        :counters.add(call_count, 1, 1)
        attempt = :counters.get(call_count, 1)
        send(test_pid, {:attempt, attempt})

        if attempt < 3 do
          conn
          |> Plug.Conn.put_status(500)
          |> Req.Test.json(%{"error" => %{"message" => "server error"}})
        else
          Req.Test.json(conn, %{
            "choices" => [%{"message" => %{"content" => full_synthesis_text()}}]
          })
        end
      end)

      assert {:ok, _text} =
               Synthesis.synthesize(@perspectives, "review this",
                 openrouter_opts: @test_opts,
                 backoff_base: 1
               )

      assert_receive {:attempt, _}
      assert_receive {:attempt, _}
      assert_receive {:attempt, _}
    end

    test "returns error after 3 failed attempts" do
      Req.Test.stub(Synthesis, fn conn ->
        conn
        |> Plug.Conn.put_status(500)
        |> Req.Test.json(%{"error" => %{"message" => "server error"}})
      end)

      assert {:error, _} =
               Synthesis.synthesize(@perspectives, "review this",
                 openrouter_opts: @test_opts,
                 backoff_base: 1
               )
    end

    test "uses specified synthesis model" do
      test_pid = self()

      Req.Test.stub(Synthesis, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:model_used, Jason.decode!(body)["model"]})
        Req.Test.json(conn, %{"choices" => [%{"message" => %{"content" => "ok"}}]})
      end)

      Synthesis.synthesize(@perspectives, "review this",
        openrouter_opts: @test_opts,
        synthesis_model: "anthropic/claude-opus-4.6"
      )

      assert_receive {:model_used, "anthropic/claude-opus-4.6"}
    end

    test "defaults to most capable model when none specified" do
      test_pid = self()

      Req.Test.stub(Synthesis, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:model_used, Jason.decode!(body)["model"]})
        Req.Test.json(conn, %{"choices" => [%{"message" => %{"content" => "ok"}}]})
      end)

      Synthesis.synthesize(@perspectives, "review this", openrouter_opts: @test_opts)

      assert_receive {:model_used, model}
      assert model == Synthesis.default_model()
    end

    test "returns {:ok, text} with whatever the model produces" do
      Req.Test.stub(Synthesis, synthesis_response("Sparse output"))

      assert {:ok, "Sparse output"} =
               Synthesis.synthesize(@perspectives, "review this", openrouter_opts: @test_opts)
    end

    test "handles empty perspectives list — still calls the API" do
      test_pid = self()

      Req.Test.stub(Synthesis, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:called, Jason.decode!(body)})
        Req.Test.json(conn, %{"choices" => [%{"message" => %{"content" => "synthesized"}}]})
      end)

      assert {:ok, "synthesized"} =
               Synthesis.synthesize([], "empty question", openrouter_opts: @test_opts)

      assert_receive {:called, body}
      assert body["messages"] |> length() == 2
    end
  end

  describe "default_model/0" do
    test "returns a non-empty string" do
      model = Synthesis.default_model()
      assert is_binary(model)
      assert model != ""
    end
  end
end
