defmodule Thinktank.Dispatch.Quick do
  @moduledoc """
  Parallel API dispatch for quick mode.

  Sends instruction + optional file contents to each perspective's model
  via concurrent OpenRouter calls. Best-effort: no retries, no OTP supervision.
  Errors are collected alongside successes.
  """

  alias Thinktank.OpenRouter

  @max_concurrency 8
  @timeout :timer.minutes(5)
  @max_file_bytes 100_000

  @type result :: {:ok, String.t(), String.t()} | {:error, String.t(), map()}

  @doc """
  Dispatch parallel API calls for each perspective.

  Returns a list of `{:ok, role, text}` or `{:error, role, error_map}` tuples
  in the same order as the input perspectives.

  Options:
    - `:paths` — file paths to read and inline in the prompt
    - `:openrouter_opts` — keyword opts forwarded to `OpenRouter.chat/4`
  """
  @spec dispatch([Thinktank.Perspective.t()], String.t(), keyword()) :: [result()]
  def dispatch(perspectives, instruction, opts \\ []) do
    file_contents = read_files(opts[:paths] || [])
    or_opts = opts[:openrouter_opts] || []
    prompt = build_prompt(instruction, file_contents)

    perspectives
    |> Task.async_stream(
      fn p ->
        case OpenRouter.chat(p.model, p.system_prompt, prompt, or_opts) do
          {:ok, text} -> {:ok, p.role, text}
          {:error, err} -> {:error, p.role, err}
        end
      end,
      max_concurrency: @max_concurrency,
      timeout: @timeout,
      on_timeout: :kill_task
    )
    |> Enum.zip(perspectives)
    |> Enum.map(fn
      {{:ok, result}, _p} -> result
      {{:exit, :timeout}, p} -> {:error, p.role, %{category: :timeout}}
    end)
  end

  defp read_files(paths) do
    Enum.flat_map(paths, fn path ->
      with true <- File.regular?(path),
           {:ok, %{size: size}} when size <= @max_file_bytes <- File.stat(path),
           {:ok, content} <- File.read(path) do
        [{path, content}]
      else
        _ -> []
      end
    end)
  end

  defp build_prompt(instruction, []), do: instruction

  defp build_prompt(instruction, files) do
    files_section =
      Enum.map_join(files, "\n\n", fn {path, content} ->
        "## #{Path.basename(path)}\n```\n#{content}\n```"
      end)

    "#{instruction}\n\n---\n\nContext files:\n\n#{files_section}"
  end
end
