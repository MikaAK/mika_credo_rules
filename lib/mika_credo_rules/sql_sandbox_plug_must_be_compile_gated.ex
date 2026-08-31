defmodule MikaCredoRules.SqlSandboxPlugMustBeCompileGated do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      gate_functions: [{Application, :compile_env}],
      excluded_paths: []
    ],
    explanations: [
      params: [
        gate_functions: """
        A list of `{module, function}` tuples. The sandbox plug is considered gated
        when it sits inside an `if` whose condition calls one of these, alias-aware.
        Defaults to `[{Application, :compile_env}]`.
        """,
        excluded_paths: """
        A list of path fragments naming files this check skips. A fragment matches
        when the source file's path starts with it, ends with it, or contains it
        after a directory separator. Defaults to `[]`.
        """
      ]
    ]

  alias MikaCredoRules.AstHelpers
  alias MikaCredoRules.SourceFilter

  @moduledoc """
  `plug Phoenix.Ecto.SQL.Sandbox` must be compile-gated — never shipped unguarded.

  The sandbox plug hands any client that knows the header format control over the
  request's database connection. It exists purely to let Wallaby/feature tests
  share a transaction with the test process; an unguarded plug ships that door to
  production.

      # BAD — ships to prod
      plug Phoenix.Ecto.SQL.Sandbox

      # GOOD — gated on a flag only config/test.exs ever sets
      if Application.compile_env(:my_web, :sql_sandbox, false) do
        plug Phoenix.Ecto.SQL.Sandbox
      end

  Every spelling of the module is caught: fully qualified, a prefix alias
  (`alias Phoenix.Ecto.SQL` then `plug SQL.Sandbox`), a full alias (`alias
  Phoenix.Ecto.SQL.Sandbox` then `plug Sandbox`, `as:` renames included), and the
  `:"Elixir.Phoenix.Ecto.SQL.Sandbox"` atom. The gate's module is resolved the
  same way — `alias MyApp.Application` shadows Elixir's `Application` file-wide,
  so `if Application.compile_env(...)` no longer counts as a gate in that file
  and the plug underneath it is still flagged.

  ## Known limitations

  A gate expressed through a module attribute is not recognised:

      # NOT recognised as gated — still flagged
      @sandbox? Application.compile_env(:my_web, :sql_sandbox, false)
      if @sandbox?, do: plug(Phoenix.Ecto.SQL.Sandbox)

  Rewrite the `if` to call `Application.compile_env/2,3` directly, or suppress
  the false positive explicitly:

      # credo:disable-for-next-line MikaCredoRules.SqlSandboxPlugMustBeCompileGated
      if @sandbox?, do: plug(Phoenix.Ecto.SQL.Sandbox)
  """
  @explanation [check: @moduledoc]

  @sandbox_module Phoenix.Ecto.SQL.Sandbox

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    if excluded_path?(source_file.filename, excluded_paths(params)) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      context = build_context(source_file, params)
      protected = guarded_if_blocks(source_file, context)

      source_file
      |> Credo.Code.prewalk(&collect_unguarded_plug(&1, &2, protected, context), [])
      |> Enum.reverse()
      |> Enum.map(&issue_for(&1, issue_meta))
    end
  end

  defp excluded_paths(params), do: Params.get(params, :excluded_paths, __MODULE__)

  defp excluded_path?(filename, excluded_paths) do
    SourceFilter.matches_fragment?(filename, excluded_paths)
  end

  defp build_context(source_file, params) do
    %{
      sandbox_paths: sandbox_paths(source_file),
      prefix_aliases: collect_prefix_aliases(source_file),
      gate_entries: gate_entries(source_file, params)
    }
  end

  defp sandbox_paths(source_file) do
    source_file
    |> AstHelpers.resolve_aliases([@sandbox_module])
    |> Enum.map(&strip_elixir_prefix/1)
    |> Enum.uniq()
  end

  defp gate_entries(source_file, params) do
    params
    |> Params.get(:gate_functions, __MODULE__)
    |> Enum.map(fn {module, function} ->
      {AstHelpers.resolve_aliases(source_file, [module]), function}
    end)
  end

  # A local, file-level table mapping a one-segment alias name to the full
  # (Elixir-stripped) module it stands for. Used to expand a prefix-aliased
  # dotted access (`alias Phoenix.Ecto.SQL` then `SQL.Sandbox`) that
  # AstHelpers.resolve_aliases cannot see — it resolves identity for one exact
  # target module, not identity of a longer path built from an aliased prefix.
  defp collect_prefix_aliases(source_file) do
    Credo.Code.prewalk(source_file, &collect_alias_pair/2, [])
  end

  defp collect_alias_pair({:alias, _, [{:__aliases__, _, target}]} = ast, aliases) do
    {ast, [{[List.last(target)], strip_elixir_prefix(target)} | aliases]}
  end

  defp collect_alias_pair({:alias, _, [{:__aliases__, _, target}, opts]} = ast, aliases)
       when is_list(opts) do
    {ast, [{alias_name(target, opts), strip_elixir_prefix(target)} | aliases]}
  end

  defp collect_alias_pair(
         {:alias, _, [{{:., _, [{:__aliases__, _, base}, :{}]}, _, inner_nodes}]} = ast,
         aliases
       ) do
    grouped_aliases =
      for {:__aliases__, _, inner} <- inner_nodes do
        {[List.last(inner)], strip_elixir_prefix(base ++ inner)}
      end

    {ast, grouped_aliases ++ aliases}
  end

  defp collect_alias_pair(ast, aliases), do: {ast, aliases}

  defp alias_name(target, opts) do
    case Keyword.get(opts, :as) do
      {:__aliases__, _, name} -> name
      _no_rename -> [List.last(target)]
    end
  end

  defp guarded_if_blocks(source_file, context) do
    Credo.Code.prewalk(source_file, &collect_guarded_if(&1, &2, context), [])
  end

  defp collect_guarded_if({construct, _, [condition | _rest]} = node, protected, context)
       when construct in [:if, :unless] do
    if calls_gate?(condition, context.gate_entries) do
      {node, [node | protected]}
    else
      {node, protected}
    end
  end

  defp collect_guarded_if(node, protected, _context), do: {node, protected}

  defp calls_gate?(ast, gate_entries) do
    ast
    |> Macro.prewalk(false, fn
      node, true -> {node, true}
      node, false -> {node, gate_call?(node, gate_entries)}
    end)
    |> elem(1)
  end

  defp gate_call?({{:., _, [{:__aliases__, _, path}, function]}, _, args}, gate_entries)
       when is_list(args) do
    Enum.any?(gate_entries, fn {module_paths, gate_function} ->
      path in module_paths and function === gate_function
    end)
  end

  defp gate_call?(_node, _gate_entries), do: false

  defp collect_unguarded_plug(node, issues, protected, context) do
    if protected?(node, protected) do
      {nil, issues}
    else
      append_plug_issue(node, issues, context)
    end
  end

  defp protected?(node, protected), do: Enum.any?(protected, &(&1 === node))

  defp append_plug_issue(node, issues, context) do
    case plug_sandbox_line(node, context) do
      nil -> {node, issues}
      line_no -> {node, [line_no | issues]}
    end
  end

  defp plug_sandbox_line({:plug, meta, [module | _rest]}, context) do
    if sandbox_module?(module, context), do: meta[:line]
  end

  defp plug_sandbox_line(_node, _context), do: nil

  defp sandbox_module?({:__aliases__, _, path}, context) do
    path
    |> strip_elixir_prefix()
    |> substitute_alias(context.prefix_aliases)
    |> Kernel.in(context.sandbox_paths)
  end

  defp sandbox_module?(module, context) when is_atom(module) do
    if elixir_module_atom?(module) do
      [stripped | _elixir_prefixed] = AstHelpers.module_paths(module)
      stripped in context.sandbox_paths
    else
      false
    end
  end

  defp sandbox_module?(_other, _context), do: false

  defp elixir_module_atom?(module) do
    case Atom.to_string(module) do
      "Elixir." <> _rest -> true
      _erlang_name -> false
    end
  end

  defp substitute_alias([first | rest] = path, prefix_aliases) do
    case Enum.find(prefix_aliases, fn {name, _target} -> name === [first] end) do
      {_name, target} -> target ++ rest
      nil -> path
    end
  end

  defp strip_elixir_prefix([Elixir | segments]), do: segments
  defp strip_elixir_prefix(segments), do: segments

  defp issue_for(line_no, issue_meta) do
    format_issue(issue_meta,
      message:
        "plug Phoenix.Ecto.SQL.Sandbox found — gate it behind Application.compile_env/2,3 (default false; only config/test.exs sets it true) so it never ships to prod",
      trigger: "plug",
      line_no: line_no
    )
  end
end
