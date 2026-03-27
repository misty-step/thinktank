defmodule Thinktank.AgentSpecTest do
  use ExUnit.Case, async: true

  alias Thinktank.AgentSpec

  test "parses agent specs with task_prompt and tools" do
    assert {:ok, spec} =
             AgentSpec.from_pair("trace", %{
               "provider" => "openrouter",
               "model" => "openai/gpt-5.4",
               "system_prompt" => "You are trace.",
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
               "prompt" => "Legacy {{input_text}}"
             })

    assert spec.task_prompt == "Legacy {{input_text}}"
  end

  test "rejects invalid models" do
    assert {:error, "agent model must not contain whitespace"} =
             AgentSpec.from_pair("trace", %{
               "provider" => "openrouter",
               "model" => "bad model",
               "system_prompt" => "You are trace."
             })
  end
end
