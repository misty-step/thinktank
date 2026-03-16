defmodule Thinktank.Dispatch.QuickTest do
  use ExUnit.Case, async: true

  alias Thinktank.Dispatch.Quick
  alias Thinktank.{OpenRouter, Perspective}

  @moduletag :tmp_dir

  @or_opts [api_key: "test-key", plug: {Req.Test, OpenRouter}]

  defp perspective(role, model \\ "test-model") do
    %Perspective{
      role: role,
      model: model,
      system_prompt: "You are a #{role}."
    }
  end

  defp echo_model_plug(conn) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    %{"model" => model} = Jason.decode!(body)

    Req.Test.json(conn, %{
      "choices" => [%{"message" => %{"content" => "Response from #{model}"}}],
      "usage" => %{"prompt_tokens" => 10, "completion_tokens" => 20, "total_tokens" => 30},
      "cost" => 0.001
    })
  end

  defp echo_prompt_plug(conn) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    %{"messages" => [_, %{"content" => user_prompt}]} = Jason.decode!(body)

    Req.Test.json(conn, %{
      "choices" => [%{"message" => %{"content" => user_prompt}}],
      "usage" => %{"prompt_tokens" => 10, "completion_tokens" => 20, "total_tokens" => 30},
      "cost" => 0.001
    })
  end

  describe "dispatch/3 — parallel API calls" do
    test "dispatches to all perspectives and returns 4 results" do
      perspectives = [
        perspective("analyst-1", "model-a"),
        perspective("analyst-2", "model-b"),
        perspective("analyst-3", "model-c"),
        perspective("analyst-4", "model-d")
      ]

      Req.Test.stub(OpenRouter, &echo_model_plug/1)

      results = Quick.dispatch(perspectives, "test instruction", openrouter_opts: @or_opts)

      assert length(results) == 4
      assert Enum.any?(results, &match?({:ok, "analyst-1", "Response from model-a", _}, &1))
      assert Enum.any?(results, &match?({:ok, "analyst-2", "Response from model-b", _}, &1))
      assert Enum.any?(results, &match?({:ok, "analyst-3", "Response from model-c", _}, &1))
      assert Enum.any?(results, &match?({:ok, "analyst-4", "Response from model-d", _}, &1))
    end

    test "sends only instruction when no paths provided" do
      Req.Test.stub(OpenRouter, &echo_prompt_plug/1)

      [result] =
        Quick.dispatch(
          [perspective("analyst")],
          "what do you think?",
          openrouter_opts: @or_opts
        )

      assert {:ok, "analyst", "what do you think?", _usage} = result
    end

    test "inlines file contents in prompt when paths provided", %{tmp_dir: tmp} do
      test_file = Path.join(tmp, "main.ex")
      File.write!(test_file, "defmodule Main, do: :ok")

      Req.Test.stub(OpenRouter, &echo_prompt_plug/1)

      [result] =
        Quick.dispatch(
          [perspective("analyst")],
          "review this",
          paths: [test_file],
          openrouter_opts: @or_opts
        )

      assert {:ok, "analyst", content, _usage} = result
      assert content =~ "review this"
      assert content =~ "defmodule Main"
    end

    test "collects errors alongside successes" do
      perspectives = [
        perspective("good-1", "good-model"),
        perspective("bad-1", "bad-model"),
        perspective("good-2", "other-model")
      ]

      Req.Test.stub(OpenRouter, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"model" => model} = Jason.decode!(body)

        if model == "bad-model" do
          conn
          |> Plug.Conn.put_status(500)
          |> Req.Test.json(%{"error" => %{"message" => "boom"}})
        else
          Req.Test.json(conn, %{
            "choices" => [%{"message" => %{"content" => "ok"}}],
            "usage" => %{"prompt_tokens" => 10, "completion_tokens" => 20, "total_tokens" => 30},
            "cost" => 0.001
          })
        end
      end)

      results = Quick.dispatch(perspectives, "test", openrouter_opts: @or_opts)

      assert length(results) == 3
      oks = Enum.filter(results, &match?({:ok, _, _, _}, &1))
      errors = Enum.filter(results, &match?({:error, _, _}, &1))
      assert length(oks) == 2
      assert length(errors) == 1

      [{:error, role, err}] = errors
      assert role == "bad-1"
      assert err.category == :api_error
    end

    test "uses each perspective's system prompt" do
      perspectives = [
        %Perspective{
          role: "security",
          model: "test-model",
          system_prompt: "You are a security expert."
        },
        %Perspective{
          role: "perf",
          model: "test-model",
          system_prompt: "You are a performance analyst."
        }
      ]

      test_pid = self()

      Req.Test.stub(OpenRouter, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"messages" => [%{"content" => sys}, _]} = Jason.decode!(body)
        send(test_pid, {:system_prompt, sys})

        Req.Test.json(conn, %{
          "choices" => [%{"message" => %{"content" => "ok"}}],
          "usage" => %{"prompt_tokens" => 10, "completion_tokens" => 20, "total_tokens" => 30},
          "cost" => 0.001
        })
      end)

      Quick.dispatch(perspectives, "test", openrouter_opts: @or_opts)

      prompts = flush_tagged(:system_prompt)
      assert "You are a security expert." in prompts
      assert "You are a performance analyst." in prompts
    end
  end

  describe "dispatch/3 — file handling" do
    test "skips files larger than 100KB", %{tmp_dir: tmp} do
      small = Path.join(tmp, "small.ex")
      big = Path.join(tmp, "big.ex")
      File.write!(small, "small content")
      File.write!(big, String.duplicate("x", 100_001))

      Req.Test.stub(OpenRouter, &echo_prompt_plug/1)

      [result] =
        Quick.dispatch(
          [perspective("analyst")],
          "review",
          paths: [small, big],
          openrouter_opts: @or_opts
        )

      assert {:ok, _, content, _usage} = result
      assert content =~ "small content"
      refute content =~ String.duplicate("x", 100)
    end

    test "handles nonexistent files gracefully", %{tmp_dir: tmp} do
      missing = Path.join(tmp, "nope.ex")

      Req.Test.stub(OpenRouter, &echo_prompt_plug/1)

      [result] =
        Quick.dispatch(
          [perspective("analyst")],
          "review",
          paths: [missing],
          openrouter_opts: @or_opts
        )

      assert {:ok, _, "review", _usage} = result
    end
  end

  defp flush_tagged(tag) do
    flush_tagged(tag, [])
  end

  defp flush_tagged(tag, acc) do
    receive do
      {^tag, value} -> flush_tagged(tag, [value | acc])
    after
      200 -> Enum.reverse(acc)
    end
  end
end
