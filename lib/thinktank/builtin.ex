defmodule Thinktank.Builtin do
  @moduledoc false

  alias Thinktank.Prompts.{Research, Review, Synthesis}

  @builtin_config_path Path.expand("../../priv/config/builtin.yml", __DIR__)
  @external_resource @builtin_config_path
  @builtin_config_yaml File.read!(@builtin_config_path)

  @spec raw_config() :: map()
  def raw_config do
    case YamlElixir.read_from_string(@builtin_config_yaml) do
      {:ok, %{} = config} ->
        inject_prompts(config)

      {:ok, other} ->
        raise "builtin config #{@builtin_config_path} must contain a YAML mapping, got: #{inspect(other)}"

      {:error, reason} ->
        raise "failed to read builtin config #{@builtin_config_path}: #{inspect(reason)}"
    end
  end

  defp inject_prompts(config) do
    config
    |> put_agent_prompts("systems", Research.systems(), Research.task())
    |> put_agent_prompts("verification", Research.verification(), Research.task())
    |> put_agent_prompts("ml", Research.ml(), Research.task())
    |> put_agent_prompts("dx", Research.dx(), Research.task())
    |> put_agent_prompts("trace", Review.trace(), Review.task())
    |> put_agent_prompts("guard", Review.guard(), Review.task())
    |> put_agent_prompts("atlas", Review.atlas(), Review.task())
    |> put_agent_prompts("proof", Review.proof(), Review.task())
    |> put_agent_prompts("vector", Review.vector(), Review.task())
    |> put_agent_prompts("pulse", Review.pulse(), Review.task())
    |> put_agent_prompts("scout", Review.scout(), Review.task())
    |> put_agent_prompts("forge", Review.forge(), Review.task())
    |> put_agent_prompts("orbit", Review.orbit(), Review.task())
    |> put_agent_prompts("sentry", Review.sentry(), Review.task())
    |> put_agent_prompts("marshal", Review.marshal(), Review.plan_task())
    |> put_agent_prompts("research-synth", Synthesis.research_system(), Synthesis.research_task())
    |> put_agent_prompts("review-synth", Synthesis.review_system(), Synthesis.review_task())
  end

  defp put_agent_prompts(config, agent_name, system_prompt, task_prompt) do
    config
    |> put_in(["agents", agent_name, "system_prompt"], system_prompt)
    |> put_in(["agents", agent_name, "task_prompt"], task_prompt)
  end
end
