defmodule MikaCredoRules.EnsureLoadedBeforeExported do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      functions: [:function_exported?, :macro_exported?, {Code, :loaded?}],
      guard_functions: [
        {Code, :ensure_loaded?},
        {Code, :ensure_loaded},
        {Code, :ensure_compiled},
        {Code, :ensure_compiled!}
      ],
      excluded_paths: []
    ],
    explanations: [
      params: [
        functions: """
        A list of bare atoms (matched local/imported or `Kernel.`-qualified) and/or
        `{module, function}` tuples (matched qualified on that module, alias-resolved)
        naming the module-capability checks that must be guarded. Defaults to
        `[:function_exported?, :macro_exported?, {Code, :loaded?}]`.
        """,
        guard_functions: """
        A list of `{module, function}` tuples that count as a load guard when called
        anywhere in the same `def`/`defp` clause body. Defaults to `Code.ensure_loaded?/1`,
        `Code.ensure_loaded/1`, `Code.ensure_compiled/1`, and `Code.ensure_compiled!/1`.
        """,
        excluded_paths: """
        A list of path fragments exempt from the check (segment-boundary matched).
        """
      ]
    ]

  alias MikaCredoRules.AstHelpers
  alias MikaCredoRules.SourceFilter

  @moduledoc """
  `function_exported?/3`, `macro_exported?/3`, and `Code.loaded?/1` must be
  guarded by `Code.ensure_loaded?/1` in the same clause body.

  `function_exported?/3` returns `false` for a module that has not yet been
  loaded into the current process's code table — not an error, just silently
  wrong. This flakes intermittently: the same call returns `true` once the
  module happens to have loaded by then, and `false` otherwise, so a suite
  passes deterministically under some ExUnit seeds and fails under others.

      # BAD — ~45% flake; returns false on first access before the code table loads
      if function_exported?(graph_module, :compile, 1) do
        graph_module.compile(opts)
      else
        graph_module.compile()
      end

      # GOOD — ensure loaded first
      if Code.ensure_loaded?(graph_module) and function_exported?(graph_module, :compile, 1) do
        graph_module.compile(opts)
      else
        graph_module.compile()
      end

  Any call to `Code.ensure_loaded?/1`, `Code.ensure_loaded/1`,
  `Code.ensure_compiled/1`, or `Code.ensure_compiled!/1` anywhere in the same
  clause body satisfies the guard — order does not matter, and the guard does
  not need to wrap the call directly. Dot-call spellings of `Code` resolved
  through `alias`/`as:` are caught, via `:guard_functions`.

  Both local/imported (`function_exported?(...)`) and `Kernel.`-qualified
  (`Kernel.function_exported?(...)`) spellings of the checked functions are
  caught, and each is only flagged at its real arity — a same-named call with
  a different arity is left alone. Each guard scope (a `def`/`defp`/`defmacro`
  clause body, or an ExUnit `test`/`setup`/`setup_all` block) is checked
  independently — a guard in one scope does not satisfy an unguarded sibling.

  ## Limitations

  `Code.ensure_loaded?/1` reached through a bare-atom qualifier
  (`:"Elixir.Code".ensure_loaded?(mod)`) or through `import Code` followed by
  a bare `ensure_loaded?(mod)` call is not recognized as a guard — both are
  false positives on correctly-guarded code. `apply(Kernel, :function_exported?,
  [...])` evades the check entirely (no dot-call or bare-identifier AST node to
  match).
  """
  @explanation [check: @moduledoc]

  @kernel_paths AstHelpers.module_paths(Kernel)
  @scope_kinds [:def, :defp, :defmacro, :test, :setup, :setup_all]
  @real_arities %{function_exported?: 3, macro_exported?: 3, loaded?: 1}

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
    functions = Params.get(params, :functions, __MODULE__)
    guard_functions = Params.get(params, :guard_functions, __MODULE__)
    {bare_functions, qualified_functions} = Enum.split_with(functions, &is_atom/1)

    %{
      bare_functions: bare_functions,
      qualified_pairs: resolve_module_function_pairs(source_file, qualified_functions),
      guard_pairs: resolve_module_function_pairs(source_file, guard_functions)
    }
  end

  defp resolve_module_function_pairs(source_file, module_function_pairs) do
    unique_modules = module_function_pairs |> Enum.map(&elem(&1, 0)) |> Enum.uniq()

    resolved_modules =
      Map.new(unique_modules, &{&1, AstHelpers.resolve_aliases(source_file, [&1])})

    for {module, function} <- module_function_pairs,
        module_path <- Map.fetch!(resolved_modules, module) do
      {module_path, function}
    end
  end

  # `quote do ... end` defines code at the macro's call site, not in this
  # file — don't descend into quoted code.
  defp traverse({:quote, _, args}, unguarded_calls, _context) when is_list(args) do
    {nil, unguarded_calls}
  end

  # Each guard scope (def/defp/defmacro clause body, or an ExUnit
  # test/setup/setup_all block) is independent: pruning here and walking it
  # ourselves keeps the outer prewalk from visiting it (and mixing scopes) a
  # second time. `test`/`setup`/`setup_all` have variable arity (an optional
  # name and/or context pattern ahead of the block), so scope membership is
  # decided by shape — the last argument being a `do:` keyword block — rather
  # than by fixed arity.
  defp traverse({kind, _, args} = ast, unguarded_calls, context)
       when kind in @scope_kinds and is_list(args) do
    if do_block?(args) do
      {nil, collect_unguarded_calls(ast, context) ++ unguarded_calls}
    else
      {ast, unguarded_calls}
    end
  end

  defp traverse(ast, unguarded_calls, _context), do: {ast, unguarded_calls}

  defp do_block?(args) do
    match?([{:do, _} | _], List.last(args))
  end

  defp collect_unguarded_calls(clause_ast, context) do
    if guarded?(clause_ast, context) do
      []
    else
      matcher = &collect_exported_call/3

      clause_ast
      |> Macro.prewalk([], &skip_quote_then(&1, &2, context, matcher))
      |> elem(1)
      |> Enum.reverse()
    end
  end

  defp guarded?(clause_ast, context) do
    matcher = &find_guard_call/3

    clause_ast
    |> Macro.prewalk(false, &skip_quote_then(&1, &2, context, matcher))
    |> elem(1)
  end

  # Quoted code (`quote do ... end`) is data describing code that runs at the
  # macro's call site, not in this file — neither a guard nor an exported-call
  # trigger found inside it is real, so both inner walks prune it the same
  # way the outer walk does.
  defp skip_quote_then({:quote, _, args}, acc, _context, _matcher) when is_list(args) do
    {nil, acc}
  end

  defp skip_quote_then(ast, acc, context, matcher), do: matcher.(ast, acc, context)

  defp find_guard_call(
         {{:., _, [{:__aliases__, _, module}, function]}, _, args} = ast,
         found,
         context
       )
       when is_atom(function) and is_list(args) do
    {ast, found or {module, function} in context.guard_pairs}
  end

  defp find_guard_call(ast, found, _context), do: {ast, found}

  defp collect_exported_call({function, meta, args} = ast, calls, context)
       when is_atom(function) and is_list(args) do
    if function in context.bare_functions and real_arity?(function, args) do
      {ast, [exported_call(function, meta) | calls]}
    else
      {ast, calls}
    end
  end

  defp collect_exported_call(
         {{:., _, [{:__aliases__, _, module}, function]}, meta, args} = ast,
         calls,
         context
       )
       when is_atom(function) and is_list(args) do
    cond do
      module in @kernel_paths and function in context.bare_functions and
          real_arity?(function, args) ->
        {ast, [exported_call(function, meta) | calls]}

      {module, function} in context.qualified_pairs and real_arity?(function, args) ->
        {ast, [exported_call(function, meta) | calls]}

      true ->
        {ast, calls}
    end
  end

  defp collect_exported_call(ast, calls, _context), do: {ast, calls}

  defp real_arity?(function, args) do
    case Map.fetch(@real_arities, function) do
      {:ok, arity} -> length(args) === arity
      :error -> true
    end
  end

  defp exported_call(function, meta) do
    %{function: function, line_no: meta[:line], column: meta[:column]}
  end

  defp issue_for(call, issue_meta) do
    trigger = "#{call.function}"

    format_issue(issue_meta,
      message:
        "#{trigger} found without Code.ensure_loaded? — guard it: Code.ensure_loaded?(mod) and #{trigger}(mod, fun, arity)",
      trigger: trigger,
      line_no: call.line_no,
      column: call.column
    )
  end
end
