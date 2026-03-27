defmodule Thinktank.Review.Diff do
  @moduledoc """
  Parses unified diffs into a small summary used by the review workflow router.
  """

  @doc_extensions MapSet.new(~w(.md .mdx .rst .txt .adoc .asciidoc .org))
  @security_hints MapSet.new(~w(auth security permission permissions oauth jwt api route router))

  @type file_record :: %{
          path: String.t(),
          additions: non_neg_integer(),
          deletions: non_neg_integer(),
          extension: String.t(),
          is_doc: boolean(),
          is_test: boolean(),
          is_code: boolean()
        }

  @type summary :: %{
          files: [file_record()],
          total_additions: non_neg_integer(),
          total_deletions: non_neg_integer(),
          total_changed_lines: non_neg_integer(),
          total_files: non_neg_integer(),
          doc_files: non_neg_integer(),
          test_files: non_neg_integer(),
          code_files: non_neg_integer(),
          code_changed: boolean(),
          size_bucket: atom(),
          model_tier: atom(),
          security_hint: boolean()
        }

  @spec parse(String.t()) :: summary()
  def parse(nil), do: empty_summary()
  def parse(""), do: empty_summary()

  def parse(diff_text) when is_binary(diff_text) do
    {files, _current} =
      diff_text
      |> String.split("\n")
      |> Enum.reduce({%{}, nil}, &reduce_line/2)

    file_list =
      files
      |> Enum.sort_by(fn {path, _} -> path end)
      |> Enum.map(fn {_path, record} ->
        ext = Path.extname(record.path) |> String.downcase()
        {is_doc, is_test, is_code} = classify_file(record.path)
        %{record | extension: ext, is_doc: is_doc, is_test: is_test, is_code: is_code}
      end)

    total_additions = Enum.sum(Enum.map(file_list, & &1.additions))
    total_deletions = Enum.sum(Enum.map(file_list, & &1.deletions))

    security_hint =
      Enum.any?(file_list, fn file ->
        path = String.downcase(file.path)
        Enum.any?(@security_hints, &String.contains?(path, &1))
      end)

    base = %{
      files: file_list,
      total_additions: total_additions,
      total_deletions: total_deletions,
      total_changed_lines: total_additions + total_deletions,
      total_files: length(file_list),
      doc_files: Enum.count(file_list, & &1.is_doc),
      test_files: Enum.count(file_list, & &1.is_test),
      code_files: Enum.count(file_list, & &1.is_code),
      code_changed: Enum.any?(file_list, & &1.is_code),
      security_hint: security_hint
    }

    base
    |> Map.put(:size_bucket, classify_size(base))
    |> Map.put(:model_tier, classify_model_tier(base))
  end

  @spec classify_file(String.t()) :: {boolean(), boolean(), boolean()}
  def classify_file(path) do
    normalized = String.downcase(path) |> String.trim_leading("/")
    ext = Path.extname(normalized)
    name = Path.basename(normalized)

    is_doc =
      MapSet.member?(@doc_extensions, ext) or
        String.starts_with?(normalized, "docs/") or
        String.starts_with?(normalized, "doc/") or
        name in ~w(readme readme.md changelog.md license contributing.md)

    is_test =
      String.contains?(normalized, "/test/") or
        String.contains?(normalized, "/tests/") or
        String.starts_with?(normalized, "test/") or
        String.starts_with?(normalized, "tests/") or
        String.starts_with?(name, "test_") or
        String.ends_with?(name, "_test.py") or
        String.ends_with?(name, "_test.exs") or
        String.ends_with?(name, "_test.ex") or
        String.contains?(name, ".test.") or
        String.contains?(name, ".spec.")

    cond do
      is_doc -> {true, false, false}
      is_test -> {false, true, false}
      true -> {false, false, true}
    end
  end

  @spec classify_size(summary()) :: :small | :medium | :large | :xlarge
  def classify_size(%{total_changed_lines: lines}) do
    cond do
      lines <= 50 -> :small
      lines <= 200 -> :medium
      lines <= 500 -> :large
      true -> :xlarge
    end
  end

  @spec classify_model_tier(summary()) :: :flash | :standard | :pro
  def classify_model_tier(%{
        total_changed_lines: lines,
        code_files: code_files,
        test_files: test_files,
        doc_files: doc_files,
        security_hint: security_hint
      }) do
    cond do
      lines <= 50 and code_files == 0 and test_files + doc_files > 0 -> :flash
      lines >= 300 or security_hint -> :pro
      true -> :standard
    end
  end

  defp reduce_line(line, {files, current}) do
    cond do
      String.starts_with?(line, "diff --git ") ->
        case parse_diff_header(line) do
          {:ok, path} -> {Map.put_new(files, path, new_file_record(path)), path}
          :error -> {files, current}
        end

      String.starts_with?(line, "+++ ") and current != nil ->
        case extract_b_path(line) do
          {:ok, "/dev/null"} ->
            {files, current}

          {:ok, new_path} when new_path != current ->
            record = Map.get(files, current, new_file_record(new_path))
            {files |> Map.delete(current) |> Map.put(new_path, %{record | path: new_path}), new_path}

          _ ->
            {files, current}
        end

      String.starts_with?(line, "+") and not String.starts_with?(line, "+++ ") and current != nil ->
        {Map.update!(files, current, &%{&1 | additions: &1.additions + 1}), current}

      String.starts_with?(line, "-") and not String.starts_with?(line, "--- ") and current != nil ->
        {Map.update!(files, current, &%{&1 | deletions: &1.deletions + 1}), current}

      true ->
        {files, current}
    end
  end

  defp parse_diff_header("diff --git " <> rest) do
    case String.split(rest, " ") do
      [_a, "b/" <> path | _] when path != "" -> {:ok, path}
      _ -> :error
    end
  end

  defp parse_diff_header(_), do: :error

  defp extract_b_path("+++ b/" <> path), do: {:ok, path}
  defp extract_b_path("+++ " <> path), do: {:ok, path}
  defp extract_b_path(_), do: :error

  defp new_file_record(path) do
    %{
      path: path,
      additions: 0,
      deletions: 0,
      extension: "",
      is_doc: false,
      is_test: false,
      is_code: false
    }
  end

  defp empty_summary do
    %{
      files: [],
      total_additions: 0,
      total_deletions: 0,
      total_changed_lines: 0,
      total_files: 0,
      doc_files: 0,
      test_files: 0,
      code_files: 0,
      code_changed: false,
      security_hint: false,
      size_bucket: :small,
      model_tier: :flash
    }
  end
end
