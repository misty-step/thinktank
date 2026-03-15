defmodule Thinktank.Router do
  @moduledoc """
  LLM-powered perspective router.

  Takes an instruction + file path metadata and generates 3-5 diverse
  expert perspectives via a single structured OpenRouter call. Each
  perspective carries a role, model selection, and custom system prompt.

  Falls back to a default council (one perspective per available model)
  if the router call fails or returns no valid perspectives.
  """

  alias Thinktank.{OpenRouter, Perspective}

  @router_model "google/gemini-3-flash-preview"

  @perspective_schema %{
    "type" => "object",
    "properties" => %{
      "perspectives" => %{
        "type" => "array",
        "minItems" => 3,
        "maxItems" => 5,
        "items" => %{
          "type" => "object",
          "properties" => %{
            "role" => %{
              "type" => "string",
              "description" => "Expert role name (e.g. 'security auditor')"
            },
            "model" => %{
              "type" => "string",
              "description" => "Model ID from the available_models list"
            },
            "system_prompt" => %{
              "type" => "string",
              "description" => "System prompt tailored to this expert's perspective"
            },
            "priority" => %{
              "type" => "integer",
              "description" => "Dispatch priority (1 = highest)"
            }
          },
          "required" => ["role", "model", "system_prompt", "priority"]
        }
      }
    },
    "required" => ["perspectives"]
  }

  @doc """
  Generate diverse perspectives for a research question.

  Options:
    - `:available_models` — list of model IDs the router may assign (required, non-empty)
    - `:perspectives` — target count (default 4)
    - `:openrouter_opts` — keyword opts forwarded to `OpenRouter.chat_structured/5`
  """
  @spec generate_perspectives(String.t(), [String.t()], keyword()) ::
          {:ok, [Perspective.t()]} | {:error, :no_models}
  def generate_perspectives(_instruction, _file_paths, opts \\ [])

  def generate_perspectives(_instruction, _file_paths, opts)
      when not is_list(opts) or opts == [] do
    {:error, :no_models}
  end

  def generate_perspectives(instruction, file_paths, opts) do
    available = Keyword.get(opts, :available_models, [])

    if available == [] do
      {:error, :no_models}
    else
      do_generate(instruction, file_paths, available, opts)
    end
  end

  defp do_generate(instruction, file_paths, available, opts) do
    count = Keyword.get(opts, :perspectives, 4)
    or_opts = Keyword.get(opts, :openrouter_opts, [])

    system = system_prompt()
    user = user_prompt(instruction, file_paths, available, count)

    case OpenRouter.chat_structured(@router_model, system, user, @perspective_schema, or_opts) do
      {:ok, %{"perspectives" => raw}} when is_list(raw) ->
        perspectives =
          raw
          |> Enum.map(&Perspective.from_map/1)
          |> Enum.reject(&is_nil/1)
          |> Enum.filter(&(&1.model in available))

        if perspectives == [] do
          {:ok, default_perspectives(available)}
        else
          {:ok, perspectives}
        end

      {:ok, _} ->
        {:ok, default_perspectives(available)}

      {:error, _} ->
        {:ok, default_perspectives(available)}
    end
  end

  @doc """
  Build perspectives from manually specified roles, bypassing the router.

  Models are round-robined across roles. Returns `[]` if no models available.
  """
  @spec manual_perspectives([String.t()], [String.t()]) :: [Perspective.t()]
  def manual_perspectives(_roles, []), do: []

  def manual_perspectives(roles, available_models) do
    count = length(available_models)

    roles
    |> Enum.with_index()
    |> Enum.map(fn {role, i} ->
      model = Enum.at(available_models, rem(i, count))

      %Perspective{
        role: role,
        model: model,
        system_prompt: "You are a #{role}. Provide analysis from this expert perspective.",
        priority: i + 1
      }
    end)
  end

  @doc false
  def default_perspectives(available_models) do
    available_models
    |> Enum.with_index()
    |> Enum.map(fn {model, i} ->
      %Perspective{
        role: "analyst-#{i + 1}",
        model: model,
        system_prompt: "You are a research analyst. Provide thorough, insightful analysis.",
        priority: i + 1
      }
    end)
  end

  defp system_prompt do
    """
    You are a research perspective router. Given a research question and context about the \
    files being analyzed, generate diverse expert perspectives that will produce complementary \
    analysis. Each perspective should have a distinct domain focus and reasoning approach. \
    Avoid overlapping concerns — maximize coverage of different analytical lenses.\
    """
  end

  defp user_prompt(instruction, file_paths, available_models, count) do
    files_summary =
      case file_paths do
        [] -> "No specific files provided."
        paths -> "Files: #{Enum.join(paths, ", ")}"
      end

    models_list = Enum.join(available_models, ", ")

    """
    Research question: #{instruction}

    #{files_summary}

    Available models (you MUST use only these): #{models_list}

    Generate exactly #{count} diverse expert perspectives. Each perspective must:
    - Have a unique analytical domain (e.g., security, performance, architecture, UX, data modeling)
    - Use a model from the available list above
    - Include a tailored system prompt that directs the model's analysis
    - Distribute models across perspectives (avoid assigning all to one model)
    """
  end
end
