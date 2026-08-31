defmodule MikaCredoRules.NoSingleLetterVariables do
  use Credo.Check,
    base_priority: :high,
    category: :readability,
    param_defaults: [allowed_names: [], banned_names: []],
    explanations: [
      params: [
        allowed_names: """
        A list of single-letter variable names that are allowed anyway. Entries may
        be given as atoms or strings — `[:i]` and `["i"]` are equivalent.

        Defaults to `[]`.
        """,
        banned_names: """
        A list of additional variable names to flag at binding sites, whatever
        their length. Entries may be given as atoms or strings — `[:cs]` and
        `["cs"]` are equivalent.

        Defaults to `[]`, e.g. project-specific abbreviations you have banned.
        A name listed in both `:banned_names` and `:allowed_names` is still
        flagged — `:banned_names` wins. A single-letter name listed in
        `:banned_names` is reported as a single-letter violation, not a banned
        name, since that check runs first.
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

  Names longer than a single letter that still carry no meaning — acronyms such
  as `cs` or `sf` rather than words — can be banned the same way through the
  `:banned_names` param, reported at the same binding sites and with the same
  underscore-prefix exemption as single-letter names.

  A name in both `:banned_names` and `:allowed_names` is still flagged —
  `:banned_names` wins. A single-letter name that is also in `:banned_names` is
  reported as a single-letter violation rather than a banned name, since the
  single-letter check runs first.

      # BAD — with banned_names: [:cs]
      def summarize(cs), do: cs.total

      # GOOD
      def summarize(changeset), do: changeset.total
  """
  @explanation [check: @moduledoc]

  @def_operations [:def, :defp, :defmacro, :defmacrop, :defguard, :defguardp]
  @typespec_attributes [:spec, :type, :typep, :opaque, :callback, :macrocallback]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    naming_rules = naming_rules(params)

    source_file
    |> Credo.Code.prewalk(&traverse(&1, &2, naming_rules))
    |> Enum.uniq()
    |> Enum.map(&issue_for(&1, issue_meta))
  end

  defp naming_rules(params) do
    %{allowed_names: allowed_names(params), banned_names: banned_names(params)}
  end

  defp allowed_names(params) do
    params
    |> Params.get(:allowed_names, __MODULE__)
    |> Enum.map(&to_string/1)
  end

  defp banned_names(params) do
    params
    |> Params.get(:banned_names, __MODULE__)
    |> Enum.map(&to_string/1)
  end

  defp traverse({:=, _, [pattern, _expression]} = ast, bindings, naming_rules) do
    {ast, collect(pattern, bindings, naming_rules)}
  end

  defp traverse({:<-, _, [pattern, _expression]} = ast, bindings, naming_rules) do
    {ast, collect(pattern, bindings, naming_rules)}
  end

  defp traverse({:->, _, [patterns, _body]} = ast, bindings, naming_rules) do
    {ast, collect(patterns, bindings, naming_rules)}
  end

  defp traverse({def_operation, _, [head | _body]} = ast, bindings, naming_rules)
       when def_operation in @def_operations do
    {ast, head |> function_parameters() |> collect(bindings, naming_rules)}
  end

  # Names in a type signature are type variables, not variables — the whole
  # subtree is dropped from the walk.
  defp traverse({:@, _, [{attribute, _, _}]}, bindings, _naming_rules)
       when attribute in @typespec_attributes do
    {nil, bindings}
  end

  # cond clause heads and the after head of a receive are expressions, not
  # patterns. Renaming their arrows keeps the heads out of the `:->` clause above
  # while the walk still descends into them, so a binding made inside a head is
  # caught through its `=`. receive do-heads remain patterns and stay untouched.
  defp traverse({:cond, meta, [sections]}, bindings, _naming_rules) when is_list(sections) do
    {{:cond, meta, [neutralize_arrows_under(sections, :do)]}, bindings}
  end

  defp traverse({:receive, meta, [sections]}, bindings, _naming_rules)
       when is_list(sections) do
    {{:receive, meta, [neutralize_arrows_under(sections, :after)]}, bindings}
  end

  defp traverse(ast, bindings, _naming_rules), do: {ast, bindings}

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
  defp collect({:^, _, _}, bindings, _naming_rules), do: bindings

  # Guards contain variable usages, not bindings — only the patterns before the
  # final guard expression are collected.
  defp collect({:when, _, args}, bindings, naming_rules) do
    args |> Enum.drop(-1) |> collect(bindings, naming_rules)
  end

  # In a binary pattern only the left of `::` binds; the right is a type spec whose
  # size expressions use existing variables.
  defp collect({:"::", _, [segment | _type]}, bindings, naming_rules) do
    collect(segment, bindings, naming_rules)
  end

  defp collect({name, meta, context}, bindings, naming_rules)
       when is_atom(name) and is_atom(context) do
    case flag_reason(name, naming_rules) do
      nil -> bindings
      reason -> [%{name: Atom.to_string(name), line_no: meta[:line], reason: reason} | bindings]
    end
  end

  defp collect({_operation, _, args}, bindings, naming_rules) when is_list(args) do
    collect(args, bindings, naming_rules)
  end

  defp collect({left, right}, bindings, naming_rules) do
    left |> collect(bindings, naming_rules) |> then(&collect(right, &1, naming_rules))
  end

  defp collect(patterns, bindings, naming_rules) when is_list(patterns) do
    Enum.reduce(patterns, bindings, &collect(&1, &2, naming_rules))
  end

  defp collect(_literal, bindings, _naming_rules), do: bindings

  defp flag_reason(name, naming_rules) do
    name_string = Atom.to_string(name)

    cond do
      String.starts_with?(name_string, "_") -> nil
      single_letter?(name_string, naming_rules.allowed_names) -> :single_letter
      name_string in naming_rules.banned_names -> :banned_name
      true -> nil
    end
  end

  defp single_letter?(name_string, allowed_names) do
    String.length(name_string) === 1 and name_string not in allowed_names
  end

  defp issue_for(bound_variable, issue_meta) do
    format_issue(issue_meta,
      message: message_for(bound_variable),
      trigger: bound_variable.name,
      line_no: bound_variable.line_no
    )
  end

  defp message_for(%{reason: :single_letter, name: name}) do
    "\"#{name}\" found — single-letter variables must be renamed to descriptive names"
  end

  defp message_for(%{reason: :banned_name, name: name}) do
    "\"#{name}\" found — banned variable name, must be renamed to a descriptive name"
  end
end
