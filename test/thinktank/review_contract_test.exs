defmodule Thinktank.ReviewContractTest do
  use ExUnit.Case, async: true

  alias Thinktank.{Engine, RunContract}
  alias Thinktank.Review.{Diff, Verdict}

  defp decode_request(conn) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    {conn, Jason.decode!(body)}
  end

  test "diff parser classifies docs and code changes" do
    diff = """
    diff --git a/README.md b/README.md
    --- a/README.md
    +++ b/README.md
    @@ -1 +1 @@
    -old
    +new
    diff --git a/lib/app.ex b/lib/app.ex
    --- a/lib/app.ex
    +++ b/lib/app.ex
    @@ -1 +1 @@
    -old
    +new
    """

    summary = Diff.parse(diff)

    assert summary.total_files == 2
    assert summary.doc_files == 1
    assert summary.code_files == 1
    assert summary.code_changed == true
  end

  test "verdict parser extracts fenced JSON blocks" do
    text = """
    Review summary

    ```json
    {
      "reviewer": "trace",
      "perspective": "correctness",
      "verdict": "WARN",
      "confidence": 0.84,
      "summary": "One issue",
      "findings": [
        {
          "severity": "major",
          "category": "logic",
          "title": "Bug",
          "description": "Broken behavior",
          "suggestion": "Fix it",
          "file": "lib/app.ex",
          "line": 8
        }
      ],
      "stats": {
        "files_reviewed": 1,
        "files_with_issues": 1,
        "critical": 0,
        "major": 1,
        "minor": 0,
        "info": 0
      }
    }
    ```
    """

    assert {:ok, verdict} = Verdict.parse(text)
    assert verdict.verdict == "WARN"
    assert hd(verdict.findings).file == "lib/app.ex"
  end

  test "run contracts round-trip and are persisted as adapter-facing artifacts" do
    contract = %RunContract{
      workflow_id: "review/cerberus",
      workspace_root: "/tmp/workspace",
      input: %{"base" => "main", "head" => "HEAD"},
      artifact_dir: "/tmp/output",
      adapter_context: %{"repo" => "acme/project", "pr" => 42},
      mode: :deep
    }

    assert {:ok, decoded} = contract |> RunContract.to_map() |> RunContract.from_map()
    assert decoded == contract

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
            ]
          })

        String.contains?(
          get_in(payload, ["messages", Access.at(0), "content"]),
          "research synthesizer"
        ) ->
          Req.Test.json(conn, %{
            "choices" => [
              %{
                "message" => %{
                  "content" =>
                    "## Agreement\n- Round trip\n\n## Disagreement\n- None\n\n## Confidence\n- High\n\n## Recommendations\n- Proceed"
                }
              }
            ]
          })

        true ->
          Req.Test.json(conn, %{
            "choices" => [%{"message" => %{"content" => "analysis"}}]
          })
      end
    end)

    assert {:ok, result} =
             Engine.run(
               "research/default",
               %{input_text: "Persist the contract", perspectives: 1},
               cwd: File.cwd!(),
               mode: :quick,
               adapter_context: %{source: "test-adapter", pr: 42},
               openrouter_opts: [api_key: "test-key", plug: {Req.Test, __MODULE__}]
             )

    contract_path = Path.join(result.output_dir, "contract.json")

    assert File.exists?(contract_path)

    assert {:ok, persisted} =
             contract_path |> File.read!() |> Jason.decode!() |> RunContract.from_map()

    assert persisted.workflow_id == "research/default"
    assert persisted.adapter_context == %{"pr" => 42, "source" => "test-adapter"}
    assert Enum.any?(result.envelope.artifacts, &(&1["name"] == "contract"))
  end
end
