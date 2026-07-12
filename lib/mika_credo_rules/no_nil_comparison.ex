defmodule MikaCredoRules.NoNilComparison do
  use Credo.Check,
    base_priority: :high,
    category: :readability,
    param_defaults: [
      operators: [:==, :!=, :===, :!==]
    ],
    explanations: [
      params: [
        operators: """
        A list of comparison operators that count as a nil comparison when either
        operand is the `nil` literal. Defaults to all four equality operators.
        """
      ]
    ]

  @moduledoc """
  Comparing against `nil` must use `is_nil/1`, not an equality operator.

  `value == nil` and `value != nil` obscure intent and invite `==`/`===`
  inconsistency. `is_nil/1` says exactly what is being asked, works in guards, and
  is the required spelling in Ecto queries.

      # BAD — equality operator against nil
      defmodule MyApp.Worker do
        def missing?(value), do: value == nil
        def present?(value), do: value != nil
        def fallback(value) when value === nil, do: :default
      end

      # GOOD — is_nil/1, in bodies and guards alike
      defmodule MyApp.Worker do
        def missing?(value), do: is_nil(value)
        def present?(value), do: not is_nil(value)
        def fallback(value) when is_nil(value), do: :default
      end

  `nil` on either side is caught:

      value == nil    # caught
      nil == value    # caught
      value !== nil   # caught

  Pattern matches on `nil` (`case value do nil -> ...`) and `nil` passed as an
  argument are not comparisons and are never flagged.
  """
  @explanation [check: @moduledoc]

  @equality_operators [:==, :===]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    operators = Params.get(params, :operators, __MODULE__)

    source_file
    |> Credo.Code.prewalk(&traverse(&1, &2, operators))
    |> Enum.map(&issue_for(&1, issue_meta))
  end

  defp traverse({operator, meta, [lhs, rhs]} = ast, comparisons, operators)
       when is_atom(operator) and (is_nil(lhs) or is_nil(rhs)) do
    if operator in operators do
      {ast, [nil_comparison(operator, lhs, rhs, meta) | comparisons]}
    else
      {ast, comparisons}
    end
  end

  defp traverse(ast, comparisons, _operators), do: {ast, comparisons}

  defp nil_comparison(operator, lhs, rhs, meta) do
    %{operator: operator, expression: compared_expression(lhs, rhs), line_no: meta[:line]}
  end

  defp compared_expression(nil, rhs), do: rhs
  defp compared_expression(lhs, nil), do: lhs

  defp issue_for(comparison, issue_meta) do
    trigger = "#{comparison.operator} nil"

    format_issue(issue_meta,
      message: "#{trigger} found — use #{replacement(comparison)} instead",
      trigger: trigger,
      line_no: comparison.line_no
    )
  end

  defp replacement(%{operator: operator, expression: expression})
       when operator in @equality_operators do
    "is_nil(#{Macro.to_string(expression)})"
  end

  defp replacement(%{expression: expression}) do
    "not is_nil(#{Macro.to_string(expression)})"
  end
end
