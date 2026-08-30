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
  """

  alias Credo.SourceFile

  @type t :: %{line_no: pos_integer(), body: String.t()}

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

  @doc "The 1-based column of the byte at `offset` inside `sigil.body`."
  @spec column_at(t(), non_neg_integer()) :: pos_integer()
  def column_at(%{body: body}, offset) do
    body
    |> binary_part(0, offset)
    |> String.split("\n")
    |> List.last()
    |> String.length()
    |> Kernel.+(1)
  end

  @doc "Number of physical source lines `sigil.body` spans."
  @spec line_count(t()) :: pos_integer()
  def line_count(%{body: body}) do
    body
    |> String.trim_trailing("\n")
    |> String.split("\n")
    |> length()
  end

  defp traverse({sigil_name, meta, [{:<<>>, _, parts}, _mods]} = ast, sigil_acc, sigils)
       when is_list(parts) do
    if sigil_name in sigils do
      {ast, [build_sigil(meta, parts) | sigil_acc]}
    else
      {ast, sigil_acc}
    end
  end

  defp traverse(ast, sigil_acc, _sigils), do: {ast, sigil_acc}

  defp build_sigil(meta, parts) do
    %{line_no: content_line(meta), body: join_binary_parts(parts)}
  end

  defp content_line(meta) do
    if meta[:delimiter] in @heredoc_delimiters, do: meta[:line] + 1, else: meta[:line]
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
