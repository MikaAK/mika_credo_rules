{:ok, _} = Application.ensure_all_started(:credo)

defmodule MikaCredoRules.DocExamples do
  @moduledoc """
  Pulls `# BAD` / `# GOOD` code examples out of a check's live `@moduledoc`
  and its README section, so example-gate tests read the actual shipped
  docs instead of a hand-copied duplicate that can silently desync from
  them.
  """

  @doc "Fetches the raw `@moduledoc` text for a compiled module."
  def moduledoc(check_module) do
    {:docs_v1, _, _, _, %{"en" => text}, _, _} = Code.fetch_docs(check_module)
    text
  end

  @doc "Fetches the raw text of a README `### `Name`` section, up to the next `###`."
  def readme_section(name) do
    "README.md"
    |> File.read!()
    |> String.split("### `#{name}`")
    |> Enum.at(1)
    |> String.split("\n### ")
    |> List.first()
  end

  @doc "Extracts fenced ```elixir blocks from README markdown text."
  def fenced_blocks(text) do
    ~r/```elixir\n(.*?)```/s
    |> Regex.scan(text)
    |> Enum.map(fn [_, body] -> body end)
  end

  @doc "Extracts 4-space-indented code blocks from `@moduledoc` heredoc text."
  def indented_blocks(text) do
    text
    |> String.split("\n")
    |> Enum.chunk_by(&(String.trim(&1) === "" or String.starts_with?(&1, "    ")))
    |> Enum.filter(fn lines ->
      Enum.any?(lines, &String.starts_with?(&1, "    ")) and
        Enum.any?(lines, &(String.trim(&1) !== ""))
    end)
    |> Enum.map(fn lines ->
      lines |> Enum.map_join("\n", &String.replace_prefix(&1, "    ", "")) |> String.trim()
    end)
  end

  @doc """
  Splits blocks of text on `# BAD` / `# GOOD` markers and numbers the
  results, returning `{index, "BAD" | "GOOD", code}` tuples in doc order.
  """
  def bad_good_examples(blocks) do
    blocks
    |> Enum.flat_map(&split_examples/1)
    |> Enum.with_index(1)
    |> Enum.map(fn {{kind, code}, index} -> {index, kind, code} end)
  end

  defp split_examples(block) do
    block
    |> String.split(~r/^[ \t]*# (BAD|GOOD)[^\n]*\n/m, include_captures: true, trim: true)
    |> Enum.chunk_every(2)
    |> Enum.flat_map(fn
      [marker, body] -> [{marker_kind(marker), String.trim(body)}]
      _ -> []
    end)
  end

  defp marker_kind(marker) do
    Regex.run(~r/# (BAD|GOOD)/, marker) |> Enum.at(1)
  end
end

ExUnit.start()
