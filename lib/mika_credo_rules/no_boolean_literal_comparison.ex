defmodule MikaCredoRules.NoBooleanLiteralComparison do
  use Credo.Check,
    base_priority: :high,
    category: :readability,
    param_defaults: [
      operators: [:==, :===, :!=, :!==],
      ignored_functions: MikaCredoRules.AstHelpers.ecto_query_functions(),
      excluded_paths: []
    ],
    explanations: [
      params: [
        operators: """
        A list of comparison operators that count as a boolean literal comparison
        when either operand is the literal `true` or `false`. Defaults to all four
        equality operators.
        """,
        ignored_functions: """
        A list of atoms naming calls whose arguments are exempt from this check.

        Defaults to the Ecto query DSL, where `==`/`!=` against a boolean literal is
        the only spelling the query compiler accepts.
        """,
        excluded_paths: """
        A list of path fragments exempt from the check (segment-boundary matched).
        """
      ]
    ]

  alias MikaCredoRules.AstHelpers
  alias MikaCredoRules.SourceFilter

  @moduledoc """
  Comparing a value to `true`/`false` must use the value directly, not an
  equality operator.

  `user.admin === true` and `Enum.filter(users, &(&1.active === true))` are
  redundant — the comparison itself already evaluates to a boolean, so
  comparing it to a boolean literal adds nothing but characters, and invites
  `==`/`===` inconsistency along the way.

      # BAD — redundant comparison against a boolean literal
      def admin?(user), do: user.admin === true
      Enum.filter(users, &(&1.active === true))
      if user.archived != false, do: ...

      # GOOD — use the boolean directly
      def admin?(user), do: user.admin
      Enum.filter(users, & &1.active)

      # GOOD — negate with not (boolean field) or ! (truthy)
      Enum.reject(users, & &1.archived)
      unless user.admin, do: ...

  A boolean literal on either side is caught:

      user.admin == true    # caught
      true == user.admin    # caught
      status != false       # caught

  Ecto queries are exempt because the query DSL only compiles `==`/`!=`:

      from(u in User, where: u.active == true)   # allowed
      where(query, [u], u.active == true)        # allowed

  Which calls are exempt is controlled by the `:ignored_functions` param. Bare and
  imported calls match by function name; qualified calls are only exempt on
  `Ecto.Query` itself or an alias of it (`alias Ecto.Query`, `alias Ecto.Query,
  as: Q`, `alias Ecto.{Query, ...}`), so a project module that happens to share a
  name with an ignored function (`alias MyApp.Query`) never borrows the
  exemption. Only the arguments of an exempt call are skipped — a boolean
  literal comparison beside a query call on the same line is still reported.
  """
  @explanation [check: @moduledoc]

  @comparison_operators [:==, :===, :!=, :!==]
  @boolean_literals [true, false]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    if excluded_file?(source_file.filename, params) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      context = build_context(source_file, params)

      source_file
      |> Credo.Code.prewalk(&traverse(&1, &2, context))
      |> Enum.map(&issue_for(&1, issue_meta))
    end
  end

  defp excluded_file?(filename, params) do
    SourceFilter.matches_fragment?(filename, Params.get(params, :excluded_paths, __MODULE__))
  end

  defp build_context(source_file, params) do
    %{
      operators: Params.get(params, :operators, __MODULE__),
      ignored_functions: Params.get(params, :ignored_functions, __MODULE__),
      ecto_query_modules: AstHelpers.resolve_aliases(source_file, [Ecto.Query])
    }
  end

  defp traverse({operator, meta, [left, right]} = ast, comparisons, context)
       when operator in @comparison_operators do
    if operator in context.operators do
      {ast, collect_if_boolean_literal(comparisons, operator, left, right, meta)}
    else
      {ast, comparisons}
    end
  end

  # Qualified calls are only exempt on Ecto.Query or an alias of it, so an
  # ignored function name on another module never borrows the exemption.
  defp traverse(
         {{:., _, [{:__aliases__, _, _module}, function]}, _, args} = ast,
         comparisons,
         context
       )
       when is_atom(function) and is_list(args) do
    prune_if_ecto_query_call(ast, comparisons, context)
  end

  defp traverse({function, _, args} = ast, comparisons, context)
       when is_atom(function) and is_list(args) do
    prune_if_ecto_query_call(ast, comparisons, context)
  end

  defp traverse(ast, comparisons, _context), do: {ast, comparisons}

  defp collect_if_boolean_literal(comparisons, operator, left, right, meta) do
    cond do
      left in @boolean_literals -> [comparison(operator, left, meta) | comparisons]
      right in @boolean_literals -> [comparison(operator, right, meta) | comparisons]
      true -> comparisons
    end
  end

  # Replacing an ignored call with a leaf stops the prewalk from descending
  # into its arguments, so only the call itself is exempt — never its whole
  # line.
  defp prune_if_ecto_query_call(ast, comparisons, context) do
    if AstHelpers.ecto_query_call?(ast, context.ecto_query_modules, context.ignored_functions) do
      {nil, comparisons}
    else
      {ast, comparisons}
    end
  end

  defp comparison(operator, literal, meta) do
    %{operator: operator, literal: literal, line_no: meta[:line], column: meta[:column]}
  end

  defp issue_for(comparison, issue_meta) do
    trigger = to_string(comparison.operator)

    format_issue(issue_meta,
      message:
        "#{trigger} #{comparison.literal} found — use the value directly, or negate with not/! or Enum.reject, instead of comparing to a boolean literal",
      trigger: trigger,
      line_no: comparison.line_no,
      column: comparison.column
    )
  end
end
