defmodule MikaCredoRules.NoTruthyAndOr do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      nilable_functions: [
        {Access, :get, 2},
        {Map, :get, 2},
        {Keyword, :get, 2},
        {List, :first, 1},
        {Map, :get, 3},
        {Keyword, :get, 3}
      ],
      excluded_paths: ["test/support/"]
    ],
    explanations: [
      params: [
        nilable_functions: """
        A list of `{module, function, arity}` tuples naming shapes that can
        evaluate to `nil`. Defaults to `Access.get/2` (bracket syntax `x[:k]`
        included), `Map.get/2`, `Keyword.get/2`, `List.first/1`, and
        `Map.get/3`/`Keyword.get/3` whose default argument is the literal `nil`.
        """,
        excluded_paths: """
        A list of path fragments exempt from the check (segment-boundary matched).
        Defaults to `["test/support/"]` — see the moduledoc for why.
        """
      ]
    ]

  alias MikaCredoRules.AstHelpers
  alias MikaCredoRules.SourceFilter

  @moduledoc """
  `and`/`or`/`not` must not be used on a provably-nilable operand.

  `and` and `or` require a strictly boolean operand and raise `BadBooleanError`
  the moment either side is `nil`; `not` requires the same and raises
  `ArgumentError` instead. `opts[:key]`, `Map.get/2`, `Keyword.get/2`, and
  `List.first/1` all evaluate to `nil` when the value is absent, so combining
  them with `and`/`or`/`not` is a crash waiting on a missing key.

      # BAD — crashes with BadBooleanError when opts[:key]/config is nil
      if opts[:llm_merge] or opts[:ai_review], do: ...
      if Map.get(config, :enabled) and ready?(), do: ...

      # BAD — crashes with ArgumentError when the operand is nil
      if not Keyword.get(opts, :skip), do: ...

      # GOOD — &&/||/! handle nil/falsy operands
      if opts[:llm_merge] || opts[:ai_review], do: ...
      if Map.get(config, :enabled) && ready?(), do: ...
      if !Keyword.get(opts, :skip), do: ...

  `Map.get/3` and `Keyword.get/3` are only flagged when the default argument
  is the literal `nil` — passing `nil` as the default is the same as passing no
  default at all, so the result is still nilable. A non-nil default (`Map.get(
  config, :enabled, false)`) means the result can never be `nil`, and is not
  flagged.

  Plain variables, ordinary function calls, and comparisons are never flagged —
  only the specific shapes in `:nilable_functions` are provably nilable enough
  to warrant a warning. A boolean literal on either side, `Enum.all?/2`
  results, and other guaranteed-boolean expressions are all left alone.

  One issue is emitted per `and`/`or`/`not` node, not per nilable operand —
  `opts[:a] and opts[:b]` (both operands nilable) reports once, while
  `a and b and c` (two `and` nodes) reports twice.

  `test/support/` is excluded by default: Phoenix/Ecto generator boilerplate
  (`data_case.ex`, `conn_case.ex`, `feature_case.ex`) commonly writes `shared:
  not tags[:async]` / `not context[:async]`, and ExUnit merges `async: async ||
  false` into every test's tags before this runs, so the operand is always a
  genuine boolean and this specific shape can never raise in practice —
  contract-correct, but not a real risk at that path.
  """
  @explanation [check: @moduledoc]

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
    nilable_functions = Params.get(params, :nilable_functions, __MODULE__)
    unique_modules = nilable_functions |> Enum.map(&elem(&1, 0)) |> Enum.uniq()

    resolved_modules =
      Map.new(unique_modules, &{&1, AstHelpers.resolve_aliases(source_file, [&1])})

    %{nilable_functions: nilable_functions, resolved_modules: resolved_modules}
  end

  defp traverse({operator, meta, [left, right]} = ast, issues, context)
       when operator in [:and, :or] do
    {ast, collect_if_nilable_operand([left, right], operator, meta, issues, context)}
  end

  defp traverse({:not, meta, [operand]} = ast, issues, context) do
    {ast, collect_if_nilable_operand([operand], :not, meta, issues, context)}
  end

  defp traverse(ast, issues, _context), do: {ast, issues}

  defp collect_if_nilable_operand(operands, operator, meta, issues, context) do
    if Enum.any?(operands, &nilable_operand?(&1, context)) do
      [nilable_use(operator, meta) | issues]
    else
      issues
    end
  end

  defp nilable_operand?({{:., _, [Access, :get]}, _, [_subject, _key]}, context) do
    {Access, :get, 2} in context.nilable_functions
  end

  defp nilable_operand?(
         {{:., _, [{:__aliases__, _, module}, function]}, _, args},
         context
       )
       when is_atom(function) and is_list(args) do
    Enum.any?(context.nilable_functions, &nilable_call?(&1, module, function, args, context))
  end

  defp nilable_operand?(_ast, _context), do: false

  defp nilable_call?({config_module, function, 2}, module, function, args, context)
       when length(args) === 2 do
    module in resolved_modules(context, config_module)
  end

  defp nilable_call?({config_module, function, 1}, module, function, args, context)
       when length(args) === 1 do
    module in resolved_modules(context, config_module)
  end

  defp nilable_call?({config_module, function, 3}, module, function, args, context)
       when length(args) === 3 do
    module in resolved_modules(context, config_module) and nil_default?(Enum.at(args, 2))
  end

  defp nilable_call?(_config, _module, _function, _args, _context), do: false

  defp nil_default?(nil), do: true
  defp nil_default?(_other), do: false

  defp resolved_modules(context, module), do: Map.fetch!(context.resolved_modules, module)

  defp nilable_use(operator, meta) do
    %{trigger: to_string(operator), line_no: meta[:line], column: meta[:column]}
  end

  defp issue_for(nilable_use, issue_meta) do
    format_issue(issue_meta,
      message:
        "#{nilable_use.trigger} found on a possibly-nil operand — use #{replacement(nilable_use.trigger)} instead",
      trigger: nilable_use.trigger,
      line_no: nilable_use.line_no,
      column: nilable_use.column
    )
  end

  defp replacement("and"), do: "&&"
  defp replacement("or"), do: "||"
  defp replacement("not"), do: "!"
end
