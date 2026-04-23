defmodule Thinktank.AgentSpecTest do
  use ExUnit.Case, async: true

  alias Thinktank.AgentSpec

  test "parses agent specs with task_prompt and tools" do
    assert {:ok, spec} =
             AgentSpec.from_pair("trace", %{
               "provider" => "openrouter",
               "model" => "openai/gpt-5.4",
               "system_prompt" => "You are trace.",
               "thinking_level" => "high",
               "task_prompt" => "Review {{input_text}}",
               "tools" => "bash,read,grep",
               "timeout_ms" => "9000"
             })

    assert spec.name == "trace"
    assert spec.task_prompt == "Review {{input_text}}"
    assert spec.tools == ["bash", "read", "grep"]
    assert spec.timeout_ms == 9000
  end

  test "accepts legacy prompt as task_prompt alias" do
    assert {:ok, spec} =
             AgentSpec.from_pair("trace", %{
               "provider" => "openrouter",
               "model" => "openai/gpt-5.4",
               "system_prompt" => "You are trace.",
               "thinking_level" => "high",
               "prompt" => "Legacy {{input_text}}"
             })

    assert spec.task_prompt == "Legacy {{input_text}}"
  end

  test "rejects invalid models" do
    assert {:error, "agent model must not contain whitespace"} =
             AgentSpec.from_pair("trace", %{
               "provider" => "openrouter",
               "model" => "bad model",
               "thinking_level" => "high",
               "system_prompt" => "You are trace."
             })
  end

  test "uses configured defaults for blank optional strings and rejects blank required strings" do
    assert {:ok, spec} =
             AgentSpec.from_pair(
               "trace",
               %{
                 "provider" => "openrouter",
                 "model" => "openai/gpt-5.4",
                 "system_prompt" => "You are trace.",
                 "task_prompt" => "   ",
                 "thinking_level" => " "
               },
               %{"thinking_level" => "high"}
             )

    assert spec.task_prompt == "{{input_text}}"
    assert spec.thinking_level == "high"

    assert {:error, "agent system_prompt is required"} =
             AgentSpec.from_pair("trace", %{
               "provider" => "openrouter",
               "model" => "openai/gpt-5.4",
               "thinking_level" => "high",
               "system_prompt" => "   "
             })
  end

  test "parses retries, legacy timeout alias, metadata, and list tools" do
    assert {:ok, spec} =
             AgentSpec.from_pair("trace", %{
               "provider" => "openrouter",
               "model" => "openai/gpt-5.4",
               "system_prompt" => "You are trace.",
               "thinking_level" => "high",
               "retries" => "2",
               "timeout" => 7000,
               "tools" => ["bash", 42, "read"],
               "metadata" => %{"role" => "correctness"}
             })

    assert spec.retries == 2
    assert spec.timeout_ms == 7000
    assert spec.tools == ["bash", "read"]
    assert spec.metadata == %{"role" => "correctness"}
  end

  test "rejects non-map specs and invalid numeric fields" do
    assert {:error, "agent trace must be a map"} = AgentSpec.from_pair("trace", nil)

    assert {:error, "agent retries must be a non-negative integer"} =
             AgentSpec.from_pair("trace", %{
               "provider" => "openrouter",
               "model" => "openai/gpt-5.4",
               "system_prompt" => "You are trace.",
               "thinking_level" => "high",
               "retries" => "-1"
             })

    assert {:error, "agent timeout_ms must be a non-negative integer"} =
             AgentSpec.from_pair("trace", %{
               "provider" => "openrouter",
               "model" => "openai/gpt-5.4",
               "system_prompt" => "You are trace.",
               "thinking_level" => "high",
               "timeout_ms" => "nope"
             })
  end

  test "rejects missing required strings" do
    assert {:error, "agent provider is required"} =
             AgentSpec.from_pair("trace", %{
               "provider" => " ",
               "model" => "openai/gpt-5.4",
               "thinking_level" => "high",
               "system_prompt" => "You are trace."
             })

    assert {:error, "agent model is required"} =
             AgentSpec.from_pair("trace", %{
               "provider" => "openrouter",
               "thinking_level" => "high",
               "system_prompt" => "You are trace."
             })
  end

  test "requires thinking_level when config defaults do not provide one" do
    assert {:error, "agent thinking_level is required"} =
             AgentSpec.from_pair("trace", %{
               "provider" => "openrouter",
               "model" => "openai/gpt-5.4",
               "system_prompt" => "You are trace."
             })
  end

  test "falls back to nil tools and empty metadata for unsupported values" do
    assert {:ok, spec} =
             AgentSpec.from_pair("trace", %{
               "provider" => "openrouter",
               "model" => "openai/gpt-5.4",
               "system_prompt" => "You are trace.",
               "thinking_level" => "high",
               "retries" => 1,
               "tools" => %{"bash" => true}
             })

    assert spec.retries == 1
    assert spec.tools == nil
    assert spec.metadata == %{}
  end
end
