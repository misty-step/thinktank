defmodule Thinktank.EngineTest do
  use ExUnit.Case, async: false

  alias Thinktank.Engine

  defp unique_tmp_dir(prefix) do
    dir = Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    dir
  end

  defp decode_request(conn) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    {conn, Jason.decode!(body)}
  end

  describe "run/3 research workflow" do
    test "supports prompt-only runs with routing, fanout, and synthesis" do
      test_pid = self()

      Req.Test.stub(__MODULE__, fn conn ->
        {conn, payload} = decode_request(conn)

        cond do
          Map.has_key?(payload, "response_format") ->
            Req.Test.json(conn, %{
              "choices" => [
                %{
                  "message" => %{
                    "content" =>
                      Jason.encode!(%{
                        "perspectives" => [
                          %{
                            "role" => "security analyst",
                            "model" => "x-ai/grok-4.1-fast",
                            "system_prompt" => "You are a security analyst.",
                            "priority" => 1
                          },
                          %{
                            "role" => "performance analyst",
                            "model" => "google/gemini-3-flash-preview",
                            "system_prompt" => "You are a performance analyst.",
                            "priority" => 2
                          }
                        ]
                      })
                  }
                }
              ],
              "usage" => %{"prompt_tokens" => 1, "completion_tokens" => 1, "total_tokens" => 2},
              "cost" => 0.0001
            })

          String.contains?(get_in(payload, ["messages", Access.at(0), "content"]), "research synthesizer") ->
            Req.Test.json(conn, %{
              "choices" => [%{"message" => %{"content" => "## Agreement\n- Shared view\n\n## Disagreement\n- None\n\n## Confidence\n- High\n\n## Recommendations\n- Act"}}],
              "usage" => %{"prompt_tokens" => 2, "completion_tokens" => 2, "total_tokens" => 4},
              "cost" => 0.0002
            })

          true ->
            send(test_pid, {:agent_prompt, get_in(payload, ["messages", Access.at(1), "content"])})

            Req.Test.json(conn, %{
              "choices" => [%{"message" => %{"content" => "Reviewer analysis"}}],
              "usage" => %{"prompt_tokens" => 2, "completion_tokens" => 2, "total_tokens" => 4},
              "cost" => 0.0002
            })
        end
      end)

      assert {:ok, result} =
               Engine.run(
                 "research/default",
                 %{input_text: "Compare approaches", perspectives: 2},
                 cwd: File.cwd!(),
                 mode: :quick,
                 openrouter_opts: [api_key: "test-key", plug: {Req.Test, __MODULE__}]
               )

      assert File.exists?(Path.join(result.output_dir, "synthesis.md"))
      assert Enum.any?(result.envelope.artifacts, &(&1["name"] == "synthesis"))
      assert result.context.workflow_exit_code == 0
      assert_receive {:agent_prompt, prompt}
      assert prompt =~ "Compare approaches"
    end

    test "includes path-backed context in agent prompts" do
      test_pid = self()
      tmp = unique_tmp_dir("thinktank-research")
      context_path = Path.join(tmp, "sample.txt")
      File.write!(context_path, "important local context")

      Req.Test.stub(__MODULE__, fn conn ->
        {conn, payload} = decode_request(conn)

        cond do
          Map.has_key?(payload, "response_format") ->
            Req.Test.json(conn, %{
              "choices" => [
                %{
                  "message" => %{
                    "content" =>
                      Jason.encode!(%{
                        "perspectives" => [
                          %{
                            "role" => "architect",
                            "model" => "x-ai/grok-4.1-fast",
                            "system_prompt" => "You are an architect.",
                            "priority" => 1
                          }
                        ]
                      })
                  }
                }
              ],
              "usage" => %{"prompt_tokens" => 1, "completion_tokens" => 1, "total_tokens" => 2},
              "cost" => 0.0001
            })

          String.contains?(get_in(payload, ["messages", Access.at(0), "content"]), "research synthesizer") ->
            Req.Test.json(conn, %{
              "choices" => [%{"message" => %{"content" => "## Agreement\n- Context used\n\n## Disagreement\n- None\n\n## Confidence\n- High\n\n## Recommendations\n- Proceed"}}]
            })

          true ->
            send(test_pid, {:agent_prompt, get_in(payload, ["messages", Access.at(1), "content"])})

            Req.Test.json(conn, %{
              "choices" => [%{"message" => %{"content" => "Context-aware analysis"}}]
            })
        end
      end)

      assert {:ok, _result} =
               Engine.run(
                 "research/default",
                 %{input_text: "Use context", paths: [context_path], perspectives: 1},
                 cwd: File.cwd!(),
                 mode: :quick,
                 openrouter_opts: [api_key: "test-key", plug: {Req.Test, __MODULE__}]
               )

      assert_receive {:agent_prompt, prompt}
      assert prompt =~ "important local context"
      assert prompt =~ "sample.txt"
    end

    test "retries aggregate stages and skips stages with unmet when conditions" do
      tmp = unique_tmp_dir("thinktank-custom")
      repo_cfg = Path.join([tmp, ".thinktank", "config.yml"])
      File.mkdir_p!(Path.dirname(repo_cfg))

      File.write!(
        repo_cfg,
        """
        agents:
          static-analyst:
            provider: openrouter
            model: x-ai/grok-4.1-fast
            system_prompt: You are a static analyst.
            prompt: "Consider: {{input_text}}"
        workflows:
          test/custom:
            description: Custom workflow
            default_mode: quick
            input_schema:
              required:
                - input_text
            stages:
              - type: prepare
                kind: research_input
              - type: route
                kind: static_agents
                agents:
                  - static-analyst
              - type: fanout
                kind: agents
              - name: aggregate
                type: aggregate
                kind: research_synthesis
                retry: 1
                when: agent_results
              - type: emit
                kind: artifacts
              - name: skipped_emit
                type: emit
                kind: artifacts
                when: nonexistent.path
        """
      )

      {:ok, counter} = Agent.start_link(fn -> 0 end)

      Req.Test.stub(__MODULE__, fn conn ->
        {conn, payload} = decode_request(conn)

        if String.contains?(get_in(payload, ["messages", Access.at(0), "content"]), "research synthesizer") do
          attempts = Agent.get_and_update(counter, fn count -> {count, count + 1} end)

          if attempts == 0 do
            conn
            |> Plug.Conn.put_status(500)
            |> Req.Test.json(%{"error" => %{"message" => "retry me"}})
          else
            Req.Test.json(conn, %{
              "choices" => [%{"message" => %{"content" => "## Agreement\n- Retried\n\n## Disagreement\n- None\n\n## Confidence\n- Medium\n\n## Recommendations\n- Done"}}]
            })
          end
        else
          Req.Test.json(conn, %{
            "choices" => [%{"message" => %{"content" => "Static review"}}]
          })
        end
      end)

      assert {:ok, result} =
               Engine.run(
                 "test/custom",
                 %{input_text: "Retry aggregate"},
                 cwd: tmp,
                 mode: :quick,
                 openrouter_opts: [api_key: "test-key", plug: {Req.Test, __MODULE__}]
               )

      manifest = Path.join(result.output_dir, "manifest.json") |> File.read!() |> Jason.decode!()
      skipped_stage = Enum.find(manifest["stages"], &(&1["name"] == "skipped_emit"))

      assert Agent.get(counter, & &1) == 2
      assert skipped_stage["status"] == "skipped"
      assert File.exists?(Path.join(result.output_dir, "synthesis.md"))
    end
  end
end
