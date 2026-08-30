defmodule MikaCredoRules.EnsureLoadedBeforeExported do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      functions: [:function_exported?, :macro_exported?],
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
        A list of atoms naming the module-capability checks that must be guarded.
        Defaults to `[:function_exported?, :macro_exported?]`.
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
  `function_exported?/3` and `macro_exported?/3` must be guarded by
  `Code.ensure_loaded?/1` in the same clause body.

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
  `def`/`defp` clause body satisfies the guard — order does not matter, and
  the guard does not need to wrap the call directly. Every spelling of `Code`
  is caught (aliased, renamed via `as:`), via `:guard_functions`.

  Both local/imported (`function_exported?(...)`) and `Kernel.`-qualified
  (`Kernel.function_exported?(...)`) spellings of the checked functions are
  caught. Each `def`/`defp` clause is checked independently — a guard in one
  clause does not satisfy an unguarded sibling clause.
  """
  @explanation [check: @moduledoc]

  @kernel_paths AstHelpers.module_paths(Kernel)

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
    guard_functions = Params.get(params, :guard_functions, __MODULE__)

    %{
      functions: Params.get(params, :functions, __MODULE__),
      guard_pairs: resolve_guard_pairs(source_file, guard_functions)
    }
  end

  defp resolve_guard_pairs(source_file, guard_functions) do
    unique_modules = guard_functions |> Enum.map(&elem(&1, 0)) |> Enum.uniq()

    resolved_modules =
      Map.new(unique_modules, &{&1, AstHelpers.resolve_aliases(source_file, [&1])})

    for {module, function} <- guard_functions,
        module_path <- Map.fetch!(resolved_modules, module) do
      {module_path, function}
    end
  end

  # `quote do ... end` defines code at the macro's call site, not in this
  # file — don't descend into quoted code.
  defp traverse({:quote, _, args}, unguarded_calls, _context) when is_list(args) do
    {nil, unguarded_calls}
  end

  # Each def/defp clause body is its own scope: pruning here and walking it
  # ourselves keeps the outer prewalk from visiting it (and mixing clauses)
  # a second time.
  defp traverse({kind, _, [_head, _body]} = ast, unguarded_calls, context)
       when kind in [:def, :defp] do
    {nil, collect_unguarded_calls(ast, context) ++ unguarded_calls}
  end

  defp traverse(ast, unguarded_calls, _context), do: {ast, unguarded_calls}

  defp collect_unguarded_calls(clause_ast, context) do
    if guarded?(clause_ast, context) do
      []
    else
      clause_ast
      |> Macro.prewalk([], &collect_exported_call(&1, &2, context))
      |> elem(1)
      |> Enum.reverse()
    end
  end

  defp guarded?(clause_ast, context) do
    clause_ast
    |> Macro.prewalk(false, &find_guard_call(&1, &2, context))
    |> elem(1)
  end

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
    if function in context.functions do
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
       when module in @kernel_paths and is_atom(function) and is_list(args) do
    if function in context.functions do
      {ast, [exported_call(function, meta) | calls]}
    else
      {ast, calls}
    end
  end

  defp collect_exported_call(ast, calls, _context), do: {ast, calls}

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
