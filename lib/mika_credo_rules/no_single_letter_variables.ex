defmodule MikaCredoRules.NoSingleLetterVariables do
  use Credo.Check,
    base_priority: :high,
    category: :readability,
    param_defaults: [allowed_names: []],
    explanations: [
      params: [
        allowed_names: """
        A list of single-letter variable names that are allowed anyway. Entries may
        be given as atoms or strings — `[:i]` and `["i"]` are equivalent.

        Defaults to `[]`.
        """
      ]
    ]

  @moduledoc """
  Variables must not be named with a single letter.

  Single-letter names carry no meaning, so every reader has to reconstruct what the
  value is from the surrounding code. Name the value after what it holds.

      # BAD — the letters say nothing about the values
      def double(x), do: x * 2
      Enum.map(users, fn u -> u.name end)

      # GOOD — the names say what each value is
      def double(number), do: number * 2
      Enum.map(users, fn user -> user.name end)

  Only binding sites are reported — function heads, `fn` clauses, `case`/`receive`
  and `rescue` clauses, `=` matches, and `for`/`with` generators. A later use of an
  already-flagged variable is not reported again, and neither is a pin (`^x`), since
  the pinned variable was reported where it was bound.

  `cond` clause heads and the `after` head of a `receive` are expressions rather
  than patterns, so they are not searched for bindings — using an already-bound
  variable there is not reported again, while a binding made inside a head, as in
  `(result = f()) > 1 -> result`, is still caught through its `=`.

  Type signatures (`@spec`, `@type`, `@typep`, `@opaque`, `@callback`, and
  `@macrocallback`) are ignored entirely — `a` and `b` in
  `@spec transform(t, (a -> b)) :: [b]` are type variables, not variables.

  The wildcard `_` and underscore-prefixed names such as `_x` mark intentionally
  unused values and are always allowed.

  Names that must stay single-letter (for example in mathematical code) can be
  exempted through the `:allowed_names` param.
  """
  @explanation [check: @moduledoc]

  @def_operations [:def, :defp, :defmacro, :defmacrop, :defguard, :defguardp]
  @typespec_attributes [:spec, :type, :typep, :opaque, :callback, :macrocallback]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    allowed_names = allowed_names(params)

    source_file
    |> Credo.Code.prewalk(&traverse(&1, &2, allowed_names))
    |> Enum.uniq()
    |> Enum.map(&issue_for(&1, issue_meta))
  end

  defp allowed_names(params) do
    params
    |> Params.get(:allowed_names, __MODULE__)
    |> Enum.map(&to_string/1)
  end

  defp traverse({:=, _, [pattern, _expression]} = ast, bindings, allowed_names) do
    {ast, collect(pattern, bindings, allowed_names)}
  end

  defp traverse({:<-, _, [pattern, _expression]} = ast, bindings, allowed_names) do
    {ast, collect(pattern, bindings, allowed_names)}
  end

  defp traverse({:->, _, [patterns, _body]} = ast, bindings, allowed_names) do
    {ast, collect(patterns, bindings, allowed_names)}
  end

  defp traverse({def_operation, _, [head | _body]} = ast, bindings, allowed_names)
       when def_operation in @def_operations do
    {ast, head |> function_parameters() |> collect(bindings, allowed_names)}
  end

  # Names in a type signature are type variables, not variables — the whole
  # subtree is dropped from the walk.
  defp traverse({:@, _, [{attribute, _, _}]}, bindings, _allowed_names)
       when attribute in @typespec_attributes do
    {nil, bindings}
  end

  # cond clause heads and the after head of a receive are expressions, not
  # patterns. Renaming their arrows keeps the heads out of the `:->` clause above
  # while the walk still descends into them, so a binding made inside a head is
  # caught through its `=`. receive do-heads remain patterns and stay untouched.
  defp traverse({:cond, meta, [sections]}, bindings, _allowed_names) when is_list(sections) do
    {{:cond, meta, [neutralize_arrows_under(sections, :do)]}, bindings}
  end

  defp traverse({:receive, meta, [sections]}, bindings, _allowed_names)
       when is_list(sections) do
    {{:receive, meta, [neutralize_arrows_under(sections, :after)]}, bindings}
  end

  defp traverse(ast, bindings, _allowed_names), do: {ast, bindings}

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

  # A pin refers to an existing binding, which was reported where it was bound.
  defp collect({:^, _, _}, bindings, _allowed_names), do: bindings

  # Guards contain variable usages, not bindings — only the patterns before the
  # final guard expression are collected.
  defp collect({:when, _, args}, bindings, allowed_names) do
    args |> Enum.drop(-1) |> collect(bindings, allowed_names)
  end

  # In a binary pattern only the left of `::` binds; the right is a type spec whose
  # size expressions use existing variables.
  defp collect({:"::", _, [segment | _type]}, bindings, allowed_names) do
    collect(segment, bindings, allowed_names)
  end

  defp collect({name, meta, context}, bindings, allowed_names)
       when is_atom(name) and is_atom(context) do
    if flagged_name?(name, allowed_names) do
      [%{name: Atom.to_string(name), line_no: meta[:line]} | bindings]
    else
      bindings
    end
  end

  defp collect({_operation, _, args}, bindings, allowed_names) when is_list(args) do
    collect(args, bindings, allowed_names)
  end

  defp collect({left, right}, bindings, allowed_names) do
    left |> collect(bindings, allowed_names) |> then(&collect(right, &1, allowed_names))
  end

  defp collect(patterns, bindings, allowed_names) when is_list(patterns) do
    Enum.reduce(patterns, bindings, &collect(&1, &2, allowed_names))
  end

  defp collect(_literal, bindings, _allowed_names), do: bindings

  defp flagged_name?(name, allowed_names) do
    name_string = Atom.to_string(name)

    name_string !== "_" and String.length(name_string) === 1 and
      name_string not in allowed_names
  end

  defp issue_for(bound_variable, issue_meta) do
    format_issue(issue_meta,
      message:
        "\"#{bound_variable.name}\" found — single-letter variables must be renamed to descriptive names",
      trigger: bound_variable.name,
      line_no: bound_variable.line_no
    )
  end
end
