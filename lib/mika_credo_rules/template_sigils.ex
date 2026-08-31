defmodule MikaCredoRules.TemplateSigils do
  @moduledoc """
  Shared extraction of `~H`/`~F` template sigil bodies, for every check that
  inspects HEEx/Surface markup.

  A `~H`/`~F` body reaches Credo's AST as
  `{:sigil_H, meta, [{:<<>>, _, parts}, mods]}`. Both sigil letters are
  uppercase, and Elixir never interpolates or escapes an uppercase sigil
  (`~s` interpolates, `~S` does not — the same rule applies to `~r`/`~R`),
  so `parts` is a single raw binary for every genuine `~H`/`~F` call —
  confirmed by parsing real HEEx source and inspecting the AST. `parts` is
  still filtered to binaries defensively, so a repo pointing `sigils:` at a
  custom lowercase (interpolating) sigil still gets a usable body instead
  of a crash.

  ## Line numbers

  `meta[:line]` is the line of the sigil's OPENING delimiter, not the first
  line of its content. For a heredoc (`\"\"\"`/`'''`) the content always
  starts one physical line below the delimiter — heredoc syntax requires a
  newline right after the opening quotes, and that newline is consumed
  rather than kept in `parts` — while a single-quoted sigil
  (`~H"<div/>"`) has its content start on the same line as the delimiter.
  `collect/2` accounts for this and returns, per sigil, the physical source
  line of the first character of `body`, so every check can compute a
  match's real line as `line_no + newlines before the match` with no
  further correction — see `line_at/2`.

  ## Column numbers

  A heredoc body has its common leading whitespace stripped (based on the
  closing delimiter's own indentation) — `parts` never contains that
  whitespace, so a byte offset inside `body` is NOT the same as a column in
  the real file; the stripped amount has to be added back. `column_at/2`
  does this using the `indentation:` meta Elixir already attaches to a
  heredoc's `<<>>` node, plus (for a non-heredoc sigil, where nothing is
  stripped) the real column of the sigil's `~` marker, its letter, and its
  opening delimiter — confirmed against `Code.string_to_quoted(source,
  columns: true)` output, which is exactly what Credo itself parses with.
  """

  alias Credo.SourceFile

  @type t :: %{
          line_no: pos_integer(),
          body: String.t(),
          first_line_column: pos_integer(),
          indentation: non_neg_integer(),
          sigil_line: pos_integer(),
          sigil_column: pos_integer(),
          sigil_trigger: String.t()
        }

  @heredoc_delimiters ["\"\"\"", "'''"]

  @doc "Every `sigils`-named sigil body in `source_file`, in source order."
  @spec collect(SourceFile.t(), [atom()]) :: [t()]
  def collect(source_file, sigils) do
    source_file
    |> Credo.Code.prewalk(&traverse(&1, &2, sigils))
    |> Enum.reverse()
  end

  @doc "The physical source line of the byte at `offset` inside `sigil.body`."
  @spec line_at(t(), non_neg_integer()) :: pos_integer()
  def line_at(%{line_no: line_no, body: body}, offset) do
    line_no + newline_count(binary_part(body, 0, offset))
  end

  @doc "The 1-based column, in the real source file, of the byte at `offset` inside `sigil.body`."
  @spec column_at(t(), non_neg_integer()) :: pos_integer()
  def column_at(%{body: body} = sigil, offset) do
    body
    |> binary_part(0, offset)
    |> String.split("\n")
    |> column_for_lines(sigil)
  end

  @doc "Number of physical source lines `sigil.body` spans."
  @spec line_count(t()) :: pos_integer()
  def line_count(%{body: body}) do
    body
    |> String.replace_suffix("\n", "")
    |> String.split("\n")
    |> length()
  end

  defp column_for_lines([only_line], %{first_line_column: first_line_column}) do
    first_line_column + String.length(only_line)
  end

  defp column_for_lines(lines, %{indentation: indentation}) do
    indentation + 1 + String.length(List.last(lines))
  end

  defp traverse(
         {sigil_name, meta, [{:<<>>, bitstring_meta, parts}, _mods]} = ast,
         sigil_acc,
         sigils
       )
       when is_list(parts) do
    if sigil_name in sigils do
      {ast, [build_sigil(sigil_name, meta, bitstring_meta, parts) | sigil_acc]}
    else
      {ast, sigil_acc}
    end
  end

  defp traverse(ast, sigil_acc, _sigils), do: {ast, sigil_acc}

  # `indentation:` (the amount of leading whitespace Elixir stripped from
  # every line of a heredoc body) lives on the INNER `{:<<>>, bitstring_meta,
  # parts}` node, not on the outer sigil node — `bitstring_meta` is the only
  # place it is ever present.
  defp build_sigil(sigil_name, meta, bitstring_meta, parts) do
    body = join_binary_parts(parts)

    sigil_location = %{
      sigil_line: meta[:line],
      sigil_column: meta[:column],
      sigil_trigger: sigil_trigger(sigil_name)
    }

    if heredoc?(meta) do
      Map.merge(sigil_location, build_heredoc_sigil(bitstring_meta, body))
    else
      Map.merge(sigil_location, build_single_line_sigil(sigil_name, meta, body))
    end
  end

  defp build_heredoc_sigil(bitstring_meta, body) do
    indentation = Keyword.get(bitstring_meta, :indentation, 0)

    %{
      line_no: bitstring_meta[:line] + 1,
      body: body,
      first_line_column: indentation + 1,
      indentation: indentation
    }
  end

  defp build_single_line_sigil(sigil_name, meta, body) do
    %{
      line_no: meta[:line],
      body: body,
      first_line_column: single_line_start_column(sigil_name, meta),
      indentation: 0
    }
  end

  defp heredoc?(meta), do: meta[:delimiter] in @heredoc_delimiters

  # `meta[:column]` is the column of the sigil's `~` marker. Content starts
  # right after `~`, the sigil letter(s) (`H`, or e.g. `HOLO`), and the
  # opening delimiter character(s).
  defp single_line_start_column(sigil_name, meta) do
    meta[:column] + 1 + sigil_letter_length(sigil_name) + String.length(meta[:delimiter])
  end

  defp sigil_trigger(sigil_name), do: "~" <> sigil_letter(sigil_name)

  defp sigil_letter_length(sigil_name), do: String.length(sigil_letter(sigil_name))

  defp sigil_letter(sigil_name) do
    sigil_name
    |> Atom.to_string()
    |> String.trim_leading("sigil_")
  end

  defp join_binary_parts(parts) do
    parts
    |> Enum.filter(&is_binary/1)
    |> Enum.join()
  end

  defp newline_count(binary) do
    binary
    |> :binary.matches("\n")
    |> length()
  end
end
