defmodule Thinktank.RouterTest do
  use ExUnit.Case, async: true

  alias Thinktank.{Router, Perspective}

  @available_models [
    "anthropic/claude-sonnet-4-6",
    "openai/gpt-5.4",
    "moonshotai/kimi-k2.5"
  ]

  @test_opts [api_key: "test-key", plug: {Req.Test, Router}]

  defp router_success_plug(conn) do
    perspectives = %{
      "perspectives" => [
        %{
          "role" => "security auditor",
          "model" => "anthropic/claude-sonnet-4-6",
          "system_prompt" => "You are a security auditor focused on vulnerabilities.",
          "priority" => 1
        },
        %{
          "role" => "performance engineer",
          "model" => "openai/gpt-5.4",
          "system_prompt" => "You are a performance engineer focused on bottlenecks.",
          "priority" => 2
        },
        %{
          "role" => "API designer",
          "model" => "moonshotai/kimi-k2.5",
          "system_prompt" => "You are an API designer focused on ergonomics.",
          "priority" => 3
        }
      ]
    }

    Req.Test.json(conn, %{
      "choices" => [%{"message" => %{"content" => Jason.encode!(perspectives)}}]
    })
  end

  defp invalid_model_plug(conn) do
    perspectives = %{
      "perspectives" => [
        %{
          "role" => "analyst",
          "model" => "nonexistent/model-xyz",
          "system_prompt" => "You analyze.",
          "priority" => 1
        },
        %{
          "role" => "reviewer",
          "model" => "anthropic/claude-sonnet-4-6",
          "system_prompt" => "You review.",
          "priority" => 2
        }
      ]
    }

    Req.Test.json(conn, %{
      "choices" => [%{"message" => %{"content" => Jason.encode!(perspectives)}}]
    })
  end

  defp error_plug(conn) do
    conn
    |> Plug.Conn.put_status(500)
    |> Req.Test.json(%{"error" => %{"message" => "internal error"}})
  end

  describe "generate_perspectives/3" do
    test "returns list of Perspective structs on success" do
      Req.Test.stub(Router, &router_success_plug/1)

      assert {:ok, perspectives} =
               Router.generate_perspectives(
                 "Review this codebase",
                 ["lib/app.ex"],
                 available_models: @available_models,
                 openrouter_opts: @test_opts
               )

      assert length(perspectives) >= 1
      assert Enum.all?(perspectives, &match?(%Perspective{}, &1))

      first = hd(perspectives)
      assert is_binary(first.role)
      assert is_binary(first.model)
      assert is_binary(first.system_prompt)
      assert is_integer(first.priority)
    end

    test "every perspective uses a model from available_models" do
      Req.Test.stub(Router, &router_success_plug/1)

      {:ok, perspectives} =
        Router.generate_perspectives(
          "Review this codebase",
          ["lib/app.ex"],
          available_models: @available_models,
          openrouter_opts: @test_opts
        )

      for p <- perspectives do
        assert p.model in @available_models,
               "model #{p.model} not in available_models"
      end
    end

    test "filters out perspectives with models not in available_models" do
      Req.Test.stub(Router, &invalid_model_plug/1)

      {:ok, perspectives} =
        Router.generate_perspectives(
          "Review this codebase",
          ["lib/app.ex"],
          available_models: @available_models,
          openrouter_opts: @test_opts
        )

      assert length(perspectives) == 1
      assert hd(perspectives).model == "anthropic/claude-sonnet-4-6"
    end

    test "falls back to default council on API error" do
      Req.Test.stub(Router, &error_plug/1)

      {:ok, perspectives} =
        Router.generate_perspectives(
          "Review this codebase",
          ["lib/app.ex"],
          available_models: @available_models,
          openrouter_opts: @test_opts
        )

      assert length(perspectives) == length(@available_models)

      models = Enum.map(perspectives, & &1.model)
      assert Enum.sort(models) == Enum.sort(@available_models)
    end

    test "falls back to default council when all models filtered out" do
      # All returned perspectives use invalid models
      Req.Test.stub(Router, fn conn ->
        perspectives = %{
          "perspectives" => [
            %{
              "role" => "ghost",
              "model" => "fake/model",
              "system_prompt" => "boo",
              "priority" => 1
            }
          ]
        }

        Req.Test.json(conn, %{
          "choices" => [%{"message" => %{"content" => Jason.encode!(perspectives)}}]
        })
      end)

      {:ok, perspectives} =
        Router.generate_perspectives(
          "Review this codebase",
          ["lib/app.ex"],
          available_models: @available_models,
          openrouter_opts: @test_opts
        )

      assert length(perspectives) == length(@available_models)
    end

    test "handles empty file_paths" do
      Req.Test.stub(Router, &router_success_plug/1)

      assert {:ok, _perspectives} =
               Router.generate_perspectives(
                 "General question",
                 [],
                 available_models: @available_models,
                 openrouter_opts: @test_opts
               )
    end
  end

  describe "manual_perspectives/2" do
    test "bypasses router with --roles, uses default models" do
      roles = ["security auditor", "performance engineer"]

      perspectives = Router.manual_perspectives(roles, @available_models)

      assert length(perspectives) == 2
      assert Enum.all?(perspectives, &match?(%Perspective{}, &1))

      for p <- perspectives do
        assert p.model in @available_models
        assert String.contains?(p.system_prompt, p.role)
      end
    end

    test "round-robins models across roles" do
      roles = ["role-a", "role-b", "role-c", "role-d"]
      models = ["model-1", "model-2", "model-3"]

      perspectives = Router.manual_perspectives(roles, models)

      assigned = Enum.map(perspectives, & &1.model)
      assert assigned == ["model-1", "model-2", "model-3", "model-1"]
    end
  end
end
