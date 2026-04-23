defmodule Thinktank.Integration.ReviewBenchCapabilityTest do
  @moduledoc """
  Probes the live OpenRouter catalog through `thinktank benches validate`'s
  capability validator and asserts the built-in benches stay tool-compatible.
  Catches the class of regression filed as backlog 019: silent tool-capability
  drift between the bench's declared tools and a configured model.

  Tagged `:integration` because it hits `openrouter.ai`. Gated on
  `OPENROUTER_API_KEY`: absent, the test emits a loud stderr notice and
  passes as a no-op (the `:integration` tag excludes it from the default
  `mix test` run, so the no-op path only triggers when a caller opts in
  without providing a key).
  """

  use ExUnit.Case, async: false

  @moduletag :integration

  alias Thinktank.{BenchValidation, Config}

  test "built-in benches validate against the live OpenRouter catalog in under five seconds" do
    api_key =
      System.get_env("OPENROUTER_API_KEY") || System.get_env("THINKTANK_OPENROUTER_API_KEY")

    if is_nil(api_key) or api_key == "" do
      IO.warn(
        "integration test skipped: OPENROUTER_API_KEY not set (nothing was probed)",
        []
      )

      :ok
    else
      {:ok, config} = Config.load()
      started_at = System.monotonic_time(:millisecond)
      report = BenchValidation.validate(config)
      duration_ms = System.monotonic_time(:millisecond) - started_at

      assert report.status == "ok"
      assert Map.get(report, :warnings, []) == []
      assert Map.get(report, :errors, []) == []
      assert duration_ms < 5_000
    end
  end
end
