defmodule MikaCredoRules.NoBinaryPatternForStringPrefix do
  use Credo.Check,
    base_priority: :normal,
    category: :readability,
    param_defaults: [excluded_paths: []],
    explanations: [
      params: [
        excluded_paths: """
        A list of path fragments exempt from the check, matched at a path-segment
        boundary.

        Defaults to `[]`.
        """
      ]
    ]

  @moduledoc """
  Match a string prefix with concatenation, not a binary pattern.

  `<<"GET ", rest::binary>>` and `"GET " <> rest` match the same values, but
  the binary-pattern spelling reads like real byte-level parsing (sizes, bit
  widths, encodings) when nothing here needs any of that — it's matching a
  literal string prefix. `<>` says exactly that, with no bit-syntax noise.

      # BAD
      <<"my", rest::binary>> = "my string"

      def parse(<<"GET ", path::binary>>), do: path

      # GOOD
      "my" <> rest = "my string"

      def parse("GET " <> path), do: path

  Only a `<<>>` pattern whose first segment is a plain string literal, and
  whose every other segment is a bare variable or a `::binary`/`::bytes`-typed
  variable, is flagged — genuine binary parsing is left alone:

      # GOOD — real byte-level parsing, not a string prefix match
      <<size::32, rest::binary>> = data
      <<"GET", _::8, path::binary>> = data

  A `<<>>` used as a constructor rather than a pattern is never flagged —
  only pattern positions are inspected: the left-hand side of `=`,
  function-clause heads, and `case`/`fn`/`with`/`for` pattern heads.

      # GOOD — a <<>> constructor, not a pattern
      x = <<"GET ", rest::binary>>
      IO.inspect(<<"GET ", rest::binary>>)
  """
  @explanation [check: @moduledoc]

  alias MikaCredoRules.SourceFilter

  @def_kinds [:def, :defp, :defmacro, :defmacrop]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    if excluded_file?(source_file.filename, params) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)

      source_file
      |> Credo.Code.prewalk(&traverse/2)
      |> Enum.map(&issue_for(&1, issue_meta))
    end
  end

  defp excluded_file?(filename, params) do
    SourceFilter.matches_fragment?(filename, Params.get(params, :excluded_paths, __MODULE__))
  end

  defp traverse({:=, _, [lhs, _rhs]} = ast, matches) do
    {ast, collect_binary_patterns(lhs, matches)}
  end

  defp traverse({def_kind, _, [head | _body]} = ast, matches) when def_kind in @def_kinds do
    {ast, head |> function_parameters() |> collect_binary_patterns(matches)}
  end

  # `case`/`fn`/`receive`-do clause heads are patterns; `cond` heads and the
  # `after` head of a `receive` are expressions, not patterns — their arrows
  # are neutralized (renamed) before the generic `:->` clause below can treat
  # them as one, mirroring MikaCredoRules.NoSingleLetterVariables.
  defp traverse({:cond, meta, [sections]}, matches) when is_list(sections) do
    {{:cond, meta, [neutralize_arrows_under(sections, :do)]}, matches}
  end

  defp traverse({:receive, meta, [sections]}, matches) when is_list(sections) do
    {{:receive, meta, [neutralize_arrows_under(sections, :after)]}, matches}
  end

  defp traverse({:->, _, [patterns, _body]} = ast, matches) do
    {ast, collect_binary_patterns(patterns, matches)}
  end

  defp traverse({with_or_for, _, clauses} = ast, matches)
       when with_or_for in [:with, :for] and is_list(clauses) do
    {ast, collect_generator_patterns(clauses, matches)}
  end

  defp traverse(ast, matches), do: {ast, matches}

  defp neutralize_arrows_under(sections, key) do
    Enum.map(sections, fn
      {^key, arrows} when is_list(arrows) -> {key, Enum.map(arrows, &neutralize_arrow/1)}
      section -> section
    end)
  end

  defp neutralize_arrow({:->, meta, clause}), do: {:expression_clause, meta, clause}
  defp neutralize_arrow(clause), do: clause

  defp function_parameters({:when, _, [head | _guards]}), do: function_parameters(head)
  defp function_parameters({_name, _, parameters}) when is_list(parameters), do: parameters
  defp function_parameters(_head), do: []

  defp collect_generator_patterns(clauses, matches) do
    Enum.reduce(clauses, matches, fn
      {:<-, _, [pattern, _source]}, acc -> collect_binary_patterns(pattern, acc)
      _clause, acc -> acc
    end)
  end

  defp collect_binary_patterns(pattern, matches) do
    {_ast, collected} = Macro.prewalk(pattern, matches, &collect_binary_pattern/2)
    collected
  end

  defp collect_binary_pattern({:<<>>, meta, segments} = node, matches) when is_list(segments) do
    if string_prefix_pattern?(segments) do
      {node, [%{line_no: meta[:line], column: meta[:column]} | matches]}
    else
      {node, matches}
    end
  end

  defp collect_binary_pattern(node, matches), do: {node, matches}

  defp string_prefix_pattern?([first | [_ | _] = rest]) do
    is_binary(first) and Enum.all?(rest, &safe_segment?/1)
  end

  defp string_prefix_pattern?(_segments), do: false

  defp safe_segment?({name, _meta, context}) when is_atom(name) and is_atom(context), do: true

  defp safe_segment?({:"::", _meta, [{name, _meta2, context}, type]})
       when is_atom(name) and is_atom(context) do
    binary_type?(type)
  end

  defp safe_segment?(_segment), do: false

  defp binary_type?({name, _meta, _context}) when name in [:binary, :bytes], do: true
  defp binary_type?(_type), do: false

  defp issue_for(match, issue_meta) do
    format_issue(issue_meta,
      message: "<<>> string-prefix pattern found — match with concatenation instead",
      trigger: "<<",
      line_no: match.line_no,
      column: match.column
    )
  end
end
