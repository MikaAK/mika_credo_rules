defmodule MikaCredoRules.LiveViewSubscribeRequiresConnected do
  use Credo.Check,
    base_priority: :normal,
    category: :warning,
    param_defaults: [
      subscribe_functions: [:subscribe],
      subscribe_modules: [],
      guard_functions: [:connected?],
      excluded_paths: []
    ],
    explanations: [
      params: [
        subscribe_functions: """
        A list of atoms naming functions that count as a PubSub subscribe. Matched
        by name only — local calls and calls on any module both count. Defaults to
        `[:subscribe]`.
        """,
        subscribe_modules: """
        A list of modules that a *remote* call must resolve to in order to count as
        a subscribe, alias-aware. Defaults to `[]`, meaning any module (or none, for
        a local call) counts — the name-only heuristic described above. Narrows the
        heuristic when a same-named function on an unrelated module would otherwise
        false-positive. Does not affect local (unqualified) calls, which carry no
        module to check and remain matched by name alone regardless of this param.
        """,
        guard_functions: """
        A list of atoms naming functions that, when called inside an `if`/`unless`
        condition, a `case`/`cond` subject or clause head, or the left side of
        `&&`/`and`, count as guarding the subscribe. Defaults to `[:connected?]`.

        Add a project helper here (e.g. `:live?`) when the guard is delegated
        rather than calling `connected?/1` directly.
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
  A PubSub subscribe inside `mount/3` must be guarded by `connected?/1`.

  LiveView calls `mount/3` twice per navigation: once for the static (disconnected)
  render, once for the live (connected) render after the socket upgrades. An
  unguarded subscribe runs on both, leaking a subscription from the discarded
  static render and letting a message handler receive updates a process that no
  longer serves any client.

      # BAD — subscribes on the static render too
      def mount(_params, _session, socket) do
        MyApp.PubSub.subscribe("topic")
        {:ok, socket}
      end

      # GOOD — only the live render subscribes
      def mount(_params, _session, socket) do
        if connected?(socket), do: MyApp.PubSub.subscribe("topic")
        {:ok, socket}
      end

  Only the presence of a guard call is checked, not its polarity or its truth —
  `unless connected?(socket) do ... else subscribe(...) end` and
  `case connected?(socket) do true -> subscribe(...); false -> :ok end` both count
  as guarded, since the subscribe sits lexically inside a construct whose
  condition references `connected?/1`. `cond` and `&&`/`and` are recognised the
  same way. This is a heuristic, not a data-flow analysis.

  Only `def mount/3` clauses are inspected — `mount/2` is not a LiveView callback
  (GenServer's is `init/1`), so it is left alone entirely. Each clause of a
  multi-clause `mount/3` is checked independently. Scoping is purely by function
  head shape: any `def mount/3` calling a subscribe-named function fires whether
  or not the enclosing module actually `use`s `Phoenix.LiveView` — the check
  never inspects the module's `use` list.

  ## Known limitations

    * The guard is recognised only by function name. A guard hoisted into a
      helper (`if live?(socket), do: subscribe(...)`) is flagged unless the
      helper's name is added to `:guard_functions`.
    * `subscribe_functions` matches by name only, local or on any module — a
      same-named function that is not a PubSub subscribe is indistinguishable
      from one that is. Set `:subscribe_modules` to narrow a *remote* call to a
      specific module (alias-aware); a local (unqualified) call carries no
      module to check and is unaffected by that param.
    * `apply(Phoenix.PubSub, :subscribe, [pubsub, topic])` is undetected —
      only a literal remote (`Mod.fun(...)`) or local (`fun(...)`) call shape
      is matched.
  """
  @explanation [check: @moduledoc]

  @guard_constructs [:if, :unless]
  @guard_operators [:&&, :and]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    if excluded_path?(source_file.filename, excluded_paths(params)) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      context = build_context(source_file, params)

      source_file
      |> Credo.Code.prewalk(&collect_mount_clauses/2)
      |> Enum.flat_map(&clause_violations(&1, context))
      |> Enum.map(&issue_for(&1, issue_meta))
    end
  end

  defp excluded_paths(params), do: Params.get(params, :excluded_paths, __MODULE__)

  defp excluded_path?(filename, excluded_paths) do
    SourceFilter.matches_fragment?(filename, excluded_paths)
  end

  defp build_context(source_file, params) do
    subscribe_modules = Params.get(params, :subscribe_modules, __MODULE__)

    %{
      subscribe_functions: Params.get(params, :subscribe_functions, __MODULE__),
      subscribe_module_paths: AstHelpers.resolve_aliases(source_file, subscribe_modules),
      guard_functions: Params.get(params, :guard_functions, __MODULE__)
    }
  end

  defp collect_mount_clauses({:def, _, [head, body]} = ast, clauses) when is_list(body) do
    if mount_head?(head), do: {ast, [ast | clauses]}, else: {ast, clauses}
  end

  defp collect_mount_clauses(ast, clauses), do: {ast, clauses}

  defp mount_head?({:when, _, [head | _guards]}), do: mount_head?(head)
  defp mount_head?({:mount, _, [_first, _second, _third]}), do: true
  defp mount_head?(_head), do: false

  defp clause_violations({:def, _, [_head, body]}, context) do
    case Keyword.get(body, :do) do
      nil -> []
      do_body -> mount_body_violations(do_body, context)
    end
  end

  # Two-pass: first collect every guarded subtree (an if/unless/case/cond/&&/and
  # whose condition calls a guard function), then walk again pruning those
  # subtrees with `{nil, acc}` so a subscribe nested inside one is never seen.
  defp mount_body_violations(body, context) do
    protected = guarded_subtrees(body, context.guard_functions)

    body
    |> Macro.prewalk([], &collect_unguarded_subscribe(&1, &2, protected, context))
    |> elem(1)
    |> Enum.reverse()
  end

  defp collect_unguarded_subscribe(node, calls, protected, context) do
    if guarded_node?(node, protected) do
      {nil, calls}
    else
      append_subscribe_call(node, calls, context)
    end
  end

  defp append_subscribe_call(node, calls, context) do
    case subscribe_call(node, context) do
      nil -> {node, calls}
      call -> {node, [call | calls]}
    end
  end

  defp guarded_node?(node, protected), do: Enum.any?(protected, &(&1 === node))

  defp guarded_subtrees(body, guard_functions) do
    body
    |> Macro.prewalk([], &collect_guarded_subtree(&1, &2, guard_functions))
    |> elem(1)
  end

  defp collect_guarded_subtree(
         {construct, _, [condition | _rest]} = node,
         protected,
         guard_functions
       )
       when construct in @guard_constructs do
    mark_if_guarded(node, condition, guard_functions, protected)
  end

  defp collect_guarded_subtree({:case, _, [subject, _clauses]} = node, protected, guard_functions) do
    mark_if_guarded(node, subject, guard_functions, protected)
  end

  defp collect_guarded_subtree({:cond, _, [[do: clauses]]} = node, protected, guard_functions) do
    if Enum.any?(clauses, &cond_clause_guarded?(&1, guard_functions)) do
      {node, [node | protected]}
    else
      {node, protected}
    end
  end

  defp collect_guarded_subtree({operator, _, [left, _right]} = node, protected, guard_functions)
       when operator in @guard_operators do
    mark_if_guarded(node, left, guard_functions, protected)
  end

  defp collect_guarded_subtree(node, protected, _guard_functions), do: {node, protected}

  defp mark_if_guarded(node, condition, guard_functions, protected) do
    if calls_guard?(condition, guard_functions) do
      {node, [node | protected]}
    else
      {node, protected}
    end
  end

  defp cond_clause_guarded?({:->, _, [[condition], _body]}, guard_functions) do
    calls_guard?(condition, guard_functions)
  end

  defp calls_guard?(ast, guard_functions) do
    ast
    |> Macro.prewalk(false, fn
      node, true -> {node, true}
      node, false -> {node, guard_call?(node, guard_functions)}
    end)
    |> elem(1)
  end

  defp guard_call?({{:., _, [_module, name]}, _, args}, guard_functions)
       when is_atom(name) and is_list(args) do
    name in guard_functions
  end

  defp guard_call?({name, _, args}, guard_functions)
       when is_atom(name) and is_list(args) do
    name in guard_functions
  end

  defp guard_call?(_node, _guard_functions), do: false

  defp subscribe_call({{:., _, [module, name]}, meta, args}, context)
       when is_atom(name) and is_list(args) do
    if name in context.subscribe_functions and
         remote_module_matches?(module, context.subscribe_module_paths) do
      %{trigger: to_string(name), line_no: meta[:line], column: meta[:column]}
    end
  end

  defp subscribe_call({name, meta, args}, context)
       when is_atom(name) and is_list(args) do
    if name in context.subscribe_functions do
      %{trigger: to_string(name), line_no: meta[:line], column: meta[:column]}
    end
  end

  defp subscribe_call(_ast, _context), do: nil

  defp remote_module_matches?(_module, []), do: true

  defp remote_module_matches?({:__aliases__, _, segments}, allowed_paths) do
    strip_elixir_prefix(segments) in allowed_paths
  end

  defp remote_module_matches?(module, allowed_paths) when is_atom(module) do
    if elixir_module_atom?(module) do
      [stripped | _elixir_prefixed] = AstHelpers.module_paths(module)
      stripped in allowed_paths
    else
      false
    end
  end

  defp remote_module_matches?(_module, _allowed_paths), do: false

  defp elixir_module_atom?(module) do
    case Atom.to_string(module) do
      "Elixir." <> _rest -> true
      _erlang_name -> false
    end
  end

  defp strip_elixir_prefix([Elixir | segments]), do: segments
  defp strip_elixir_prefix(segments), do: segments

  defp issue_for(call, issue_meta) do
    format_issue(issue_meta,
      message:
        "#{call.trigger} found — guard it with connected?(socket) (mount/3 runs on both the static and live render; an unguarded subscribe leaks one)",
      trigger: call.trigger,
      line_no: call.line_no,
      column: call.column
    )
  end
end
