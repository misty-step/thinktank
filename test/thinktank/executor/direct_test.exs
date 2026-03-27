defmodule Thinktank.Executor.DirectTest do
  use ExUnit.Case, async: false

  alias Thinktank.{AgentSpec, Config, ProviderSpec, RunContract}
  alias Thinktank.Executor.Direct

  defp decode_request(conn) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    {conn, Jason.decode!(body)}
  end

  defp config(provider_defaults \\ %{}) do
    %Config{
      providers: %{
        "openrouter" => %ProviderSpec{
          id: "openrouter",
          adapter: :openrouter,
          credential_env: "THINKTANK_OPENROUTER_API_KEY",
          defaults: provider_defaults
        }
      },
      agents: %{},
      workflows: %{},
      sources: %{}
    }
  end

  test "retries retryable failures and uses structured review for cerberus" do
    test_pid = self()
    {:ok, attempts} = Agent.start_link(fn -> 0 end)

    Req.Test.stub(__MODULE__, fn conn ->
      {conn, payload} = decode_request(conn)
      send(test_pid, {:payload, payload})

      count = Agent.get_and_update(attempts, fn value -> {value, value + 1} end)

      if count == 0 do
        conn
        |> Plug.Conn.put_status(429)
        |> Req.Test.json(%{})
      else
        Req.Test.json(conn, %{
          "choices" => [
            %{
              "message" => %{
                "content" =>
                  Jason.encode!(%{
                    "reviewer" => "trace",
                    "perspective" => "correctness",
                    "verdict" => "PASS",
                    "confidence" => 0.9,
                    "summary" => "Looks good",
                    "findings" => [],
                    "stats" => %{
                      "files_reviewed" => 1,
                      "files_with_issues" => 0,
                      "critical" => 0,
                      "major" => 0,
                      "minor" => 0,
                      "info" => 0
                    }
                  })
              }
            }
          ],
          "usage" => %{"prompt_tokens" => 1, "completion_tokens" => 1, "total_tokens" => 2},
          "cost" => 0.0001
        })
      end
    end)

    agent = %AgentSpec{
      name: "trace",
      provider: "openrouter",
      model: "openai/gpt-5.4",
      system_prompt: "You are a reviewer.",
      prompt: "{{input_text}}",
      tool_profile: "review",
      retries: 1,
      timeout_ms: 5_000
    }

    contract = %RunContract{
      workflow_id: "review/cerberus",
      workspace_root: File.cwd!(),
      input: %{input_text: "Review this"},
      artifact_dir: Path.join(System.tmp_dir!(), "thinktank-direct-review"),
      adapter_context: %{},
      mode: :quick
    }

    [result] =
      Direct.run([agent], contract, %{}, config(),
        openrouter_opts: [api_key: "test-key", plug: {Req.Test, __MODULE__}]
      )

    assert result.status == :ok
    assert Agent.get(attempts, & &1) == 2
    assert result.output =~ "\"reviewer\": \"trace\""
    assert_receive {:payload, %{"response_format" => %{"type" => "json_schema"}}}
  end

  test "falls back to provider default credential env" do
    test_pid = self()
    System.delete_env("THINKTANK_OPENROUTER_API_KEY")
    System.put_env("OPENROUTER_API_KEY", "fallback-key")

    on_exit(fn ->
      System.delete_env("OPENROUTER_API_KEY")
      System.delete_env("THINKTANK_OPENROUTER_API_KEY")
    end)

    Req.Test.stub(__MODULE__, fn conn ->
      send(test_pid, {:auth, Plug.Conn.get_req_header(conn, "authorization")})

      Req.Test.json(conn, %{
        "choices" => [%{"message" => %{"content" => "plain response"}}],
        "usage" => %{"prompt_tokens" => 1, "completion_tokens" => 1, "total_tokens" => 2},
        "cost" => 0.0001
      })
    end)

    agent = %AgentSpec{
      name: "architect",
      provider: "openrouter",
      model: "openai/gpt-5.4",
      system_prompt: "You are helpful.",
      prompt: "{{input_text}}",
      timeout_ms: 5_000
    }

    contract = %RunContract{
      workflow_id: "research/default",
      workspace_root: File.cwd!(),
      input: %{input_text: "Research this"},
      artifact_dir: Path.join(System.tmp_dir!(), "thinktank-direct-research"),
      adapter_context: %{},
      mode: :quick
    }

    [result] =
      Direct.run(
        [agent],
        contract,
        %{},
        config(%{"fallback_env" => "OPENROUTER_API_KEY"}),
        openrouter_opts: [plug: {Req.Test, __MODULE__}]
      )

    assert result.status == :ok
    assert_receive {:auth, ["Bearer fallback-key"]}
  end
end
