defmodule Thinktank.ErrorTest do
  use ExUnit.Case, async: true

  alias Thinktank.Error

  describe "from_reason/1" do
    test "preserves an existing Thinktank.Error" do
      existing = %Error{
        code: :bootstrap_failed,
        message: "already normalized",
        details: %{phase: "init_run"}
      }

      assert Error.from_reason(existing) == existing
    end

    test "normalizes :missing_input_text" do
      error = Error.from_reason(:missing_input_text)

      assert %Error{code: :missing_input_text, message: "input text is required", details: %{}} =
               error
    end

    test "normalizes :no_successful_agents" do
      error = Error.from_reason(:no_successful_agents)

      assert %Error{
               code: :no_successful_agents,
               message: "no agents completed successfully",
               details: %{}
             } = error
    end

    test "normalizes a binary reason" do
      error = Error.from_reason("something broke")
      assert %Error{code: :run_error, message: "something broke", details: %{}} = error
    end

    test "normalizes a map with :category key" do
      error = Error.from_reason(%{category: :timeout, message: "timed out"})

      assert %Error{
               code: :timeout,
               message: "timed out",
               details: %{category: :timeout, message: "timed out"}
             } = error
    end

    test "normalizes a map with :category but no :message" do
      error = Error.from_reason(%{category: :crash})
      assert %Error{code: :crash, message: "agent error", details: %{category: :crash}} = error
    end

    test "normalizes unknown terms" do
      error = Error.from_reason({:unexpected, 42})
      assert %Error{code: :unknown, details: %{}} = error
      assert error.message == inspect({:unexpected, 42})
    end
  end

  describe "Jason.Encoder" do
    test "serializes to JSON" do
      error = Error.from_reason(:missing_input_text)
      assert {:ok, json} = Jason.encode(error)
      decoded = Jason.decode!(json)
      assert decoded["code"] == "missing_input_text"
      assert decoded["message"] == "input text is required"
      assert decoded["details"] == %{}
    end
  end
end
