defmodule MikaCredoRules.NoVacuousAssert do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [test_files: ["_test.exs"]],
    explanations: [
      params: [
        test_files: """
        A list of file path suffixes treated as test files. The check only runs on
        source files whose path ends with one of these.

        Defaults to `["_test.exs"]`.
        """
      ]
    ]

  alias MikaCredoRules.SourceFilter

  @moduledoc """
  Assertions must exercise real behaviour, never a hardcoded literal.

  `assert true`, `assert :ok`, `refute false` always pass or fail regardless of
  what the test does — they are placeholders that survived past the point a real
  assertion should have replaced them. `assert x === x` is the same trap wearing
  an operator: it compares a value to itself, so it can never fail.

      # BAD
      assert true
      assert :ok
      refute false
      refute nil
      assert Orders.status(order) === Orders.status(order)

      # GOOD
      assert Orders.status(order) === :shipped

  A bare variable or a function call is never flagged — `assert some_call()` and
  `assert x` are legitimate assertions on a value computed elsewhere.

  The check only runs on test files, identified by filename via the `:test_files`
  param.
  """
  @explanation [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    if test_file?(source_file.filename, test_files(params)) do
      issue_meta = IssueMeta.for(source_file, params)

      source_file
      |> Credo.Code.prewalk(&traverse/2)
      |> Enum.map(&issue_for(&1, issue_meta))
    else
      []
    end
  end

  defp test_files(params), do: Params.get(params, :test_files, __MODULE__)

  defp test_file?(filename, test_files), do: SourceFilter.matches_suffix?(filename, test_files)

  defp traverse({:assert, meta, [{op, _, [left, right]} | _]} = ast, vacuous_asserts)
       when op in [:===, :==] do
    if identical_ast?(left, right) do
      trigger = "assert #{Macro.to_string(left)} #{op} #{Macro.to_string(right)}"
      {ast, [vacuous(trigger, meta) | vacuous_asserts]}
    else
      {ast, vacuous_asserts}
    end
  end

  defp traverse({:assert, meta, [literal | _]} = ast, vacuous_asserts) do
    if truthy_literal?(literal) do
      {ast, [vacuous("assert #{Macro.to_string(literal)}", meta) | vacuous_asserts]}
    else
      {ast, vacuous_asserts}
    end
  end

  defp traverse({:refute, meta, [literal | _]} = ast, vacuous_asserts)
       when literal in [false, nil] do
    {ast, [vacuous("refute #{Macro.to_string(literal)}", meta) | vacuous_asserts]}
  end

  defp traverse(ast, vacuous_asserts), do: {ast, vacuous_asserts}

  defp truthy_literal?(false), do: false
  defp truthy_literal?(nil), do: false
  defp truthy_literal?(literal), do: Macro.quoted_literal?(literal)

  defp identical_ast?(left, right), do: strip_meta(left) === strip_meta(right)

  defp strip_meta({form, _meta, args}), do: {strip_meta(form), [], strip_meta(args)}
  defp strip_meta({left, right}), do: {strip_meta(left), strip_meta(right)}
  defp strip_meta(list) when is_list(list), do: Enum.map(list, &strip_meta/1)
  defp strip_meta(other), do: other

  defp vacuous(trigger, meta), do: %{trigger: trigger, line_no: meta[:line]}

  defp issue_for(vacuous_assert, issue_meta) do
    format_issue(issue_meta,
      message: "#{vacuous_assert.trigger} found — assert a behaviour, not a literal",
      trigger: vacuous_assert.trigger,
      line_no: vacuous_assert.line_no
    )
  end
end
