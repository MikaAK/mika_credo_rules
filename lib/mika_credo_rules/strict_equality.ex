defmodule MikaCredoRules.StrictEquality do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      ignored_functions: [
        :dynamic,
        :from,
        :where,
        :or_where,
        :having,
        :or_having,
        :select,
        :select_merge,
        :on,
        :join,
        :query,
        :subquery,
        :in
      ]
    ],
    explanations: [
      params: [
        ignored_functions: """
        A list of atoms naming calls whose arguments are exempt from this check.

        Defaults to the Ecto query DSL, where `==` and `!=` are the only equality
        operators the query compiler accepts.
        """
      ]
    ]

  @moduledoc """
  Comparisons must use `===`/`!==` instead of `==`/`!=`.

  `==` coerces across numeric types — `1 == 1.0` is true — so a refactor that
  changes a value from integer to float keeps every comparison silently passing.
  `===` only matches the same type and value, and fails loudly the moment types
  drift.

      # BAD
      if user.age == 18, do: ...
      if status != :active, do: ...

      # GOOD
      if user.age === 18, do: ...
      if status !== :active, do: ...

  Ecto queries are exempt because the query DSL only compiles `==` and `!=`:

      from(u in User, where: u.age == 18)   # allowed
      where(query, [u], u.age == 18)        # allowed
      dynamic([u], u.age == ^age)           # allowed

  Which calls are exempt is controlled by the `:ignored_functions` param. Bare and
  imported calls match by function name; qualified calls are only exempt on
  `Ecto.Query` itself or an alias of it (`alias Ecto.Query`, `alias Ecto.Query,
  as: Q`, `alias Ecto.{Query, ...}`), so `Enum.join/2` sharing a name with the
  `:join` entry never hides its arguments. Only the arguments of an exempt call
  are skipped — a loose comparison beside a query call on the same line is still
  reported.

  Any comparison with `Mix.env()` on either side is deliberately allowed, in any
  file — so the standard `start_permanent: Mix.env() == :prod` line in `mix.exs`
  passes. `Mix.env/0` returns an atom, which `==` cannot coerce, and calling
  `Mix.env/0` outside `mix.exs` is a different rule's job to catch.
  """
  @explanation [check: @moduledoc]

  @loose_operators [:==, :!=]
  @strict_replacements %{:== => :===, :!= => :!==}
  @ecto_query [:Ecto, :Query]
  @fully_qualified_ecto_query [Elixir, :Ecto, :Query]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    context = %{
      ignored_functions: Params.get(params, :ignored_functions, __MODULE__),
      ecto_query_modules: ecto_query_modules(source_file)
    }

    source_file
    |> Credo.Code.prewalk(&traverse(&1, &2, context))
    |> Enum.map(&issue_for(&1, issue_meta))
  end

  # Every module path in this file that refers to Ecto.Query, starting from the
  # two spellings that always do and folding each alias over that base.
  defp ecto_query_modules(source_file) do
    source_file
    |> Credo.Code.prewalk(&collect_aliases/2)
    |> Enum.reduce([@ecto_query, @fully_qualified_ecto_query], &apply_alias/2)
  end

  defp collect_aliases({:alias, _, [{:__aliases__, _, target}]} = ast, aliases) do
    {ast, [{[List.last(target)], target} | aliases]}
  end

  defp collect_aliases({:alias, _, [{:__aliases__, _, target}, opts]} = ast, aliases)
       when is_list(opts) do
    {ast, [{alias_name(target, opts), target} | aliases]}
  end

  # `alias Ecto.{Query, Changeset}` — the inner aliases are relative to the base.
  defp collect_aliases(
         {:alias, _, [{{:., _, [{:__aliases__, _, base}, :{}]}, _, inner_nodes}]} = ast,
         aliases
       ) do
    grouped_aliases =
      for {:__aliases__, _, inner} <- inner_nodes do
        {[List.last(inner)], base ++ inner}
      end

    {ast, grouped_aliases ++ aliases}
  end

  defp collect_aliases(ast, aliases), do: {ast, aliases}

  defp alias_name(target, opts) do
    case Keyword.get(opts, :as) do
      {:__aliases__, _, name} -> name
      _ -> [List.last(target)]
    end
  end

  # `alias Ecto.Query` / `alias Ecto.Query, as: Q` — Query/Q now mean Ecto.Query.
  defp apply_alias({name, target}, modules)
       when target === @ecto_query
       when target === @fully_qualified_ecto_query do
    [name | modules]
  end

  defp apply_alias(_alias, modules), do: modules

  defp traverse({operator, meta, [left, right]} = ast, loose_comparisons, _context)
       when operator in @loose_operators do
    if mix_env_call?(left) or mix_env_call?(right) do
      {ast, loose_comparisons}
    else
      {ast, [loose_comparison(operator, meta) | loose_comparisons]}
    end
  end

  # `&==/2` and other non-binary spellings of the operators.
  defp traverse({operator, meta, _} = ast, loose_comparisons, _context)
       when operator in @loose_operators do
    {ast, [loose_comparison(operator, meta) | loose_comparisons]}
  end

  # Qualified calls are only exempt on Ecto.Query or an alias of it, so an ignored
  # function name on another module (`Enum.join/2`) never hides its arguments.
  defp traverse(
         {{:., _, [{:__aliases__, _, module}, function]}, _, args} = ast,
         loose_comparisons,
         context
       )
       when is_atom(function) and is_list(args) do
    if module in context.ecto_query_modules do
      prune_ignored(ast, function, loose_comparisons, context)
    else
      {ast, loose_comparisons}
    end
  end

  defp traverse({function, _, args} = ast, loose_comparisons, context)
       when is_atom(function) and is_list(args) do
    prune_ignored(ast, function, loose_comparisons, context)
  end

  defp traverse(ast, loose_comparisons, _context), do: {ast, loose_comparisons}

  # Replacing an ignored call with a leaf stops the prewalk from descending into
  # its arguments, so only the call itself is exempt — never its whole line.
  defp prune_ignored(ast, function, loose_comparisons, context) do
    if function in context.ignored_functions do
      {nil, loose_comparisons}
    else
      {ast, loose_comparisons}
    end
  end

  defp loose_comparison(operator, meta) do
    %{operator: operator, line_no: meta[:line], column: meta[:column]}
  end

  defp mix_env_call?({{:., _, [{:__aliases__, _, module}, :env]}, _, []})
       when module === [:Mix]
       when module === [Elixir, :Mix],
       do: true

  defp mix_env_call?(_ast), do: false

  defp issue_for(loose_comparison, issue_meta) do
    strict_operator = Map.fetch!(@strict_replacements, loose_comparison.operator)

    format_issue(issue_meta,
      message:
        "#{loose_comparison.operator}/2 found — comparisons must be strict, use #{strict_operator}/2 instead",
      trigger: "#{loose_comparison.operator}",
      line_no: loose_comparison.line_no,
      column: loose_comparison.column
    )
  end
end
