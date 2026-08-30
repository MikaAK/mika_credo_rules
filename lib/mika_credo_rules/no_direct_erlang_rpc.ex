defmodule MikaCredoRules.NoDirectErlangRpc do
  use Credo.Check,
    base_priority: :high,
    category: :design,
    param_defaults: [
      erlang_modules: [:rpc, :erpc],
      functions: [{Node, :spawn}, {Node, :spawn_link}, {Node, :spawn_monitor}],
      excluded_paths: ["rpc_load_balancer/", "elixir_cache/"]
    ],
    explanations: [
      params: [
        erlang_modules: """
        A list of erlang module atoms banned outright — every remote call on one
        of these modules is flagged, whatever the function. Defaults to
        `[:rpc, :erpc]`.
        """,
        functions: """
        A list of `{module, function}` pairs to ban, alias-aware. Defaults to
        `Node.spawn/1..3`, `Node.spawn_link/1..3`, and `Node.spawn_monitor/1..3` —
        spawning a process directly on a remote node bypasses the same
        load-balancing and error handling as a direct `:rpc`/`:erpc` call.
        """,
        excluded_paths: """
        A list of path fragments. A source file is exempt when its path starts or
        ends with a fragment, or contains one after a `/` — matching happens on
        path-segment boundaries, so `rpc_load_balancer/` does not exempt
        `fake_rpc_load_balancer_helper.ex`.

        Defaults to `["rpc_load_balancer/", "elixir_cache/"]`, exempting the
        libraries that implement the RPC wrapper itself and legitimately call
        `:erpc`/`:rpc` directly.
        """
      ]
    ]

  alias MikaCredoRules.AstHelpers
  alias MikaCredoRules.SourceFilter

  @moduledoc """
  Remote nodes must be called through the app's RPC wrapper, never directly.

  Direct `:rpc`/`:erpc` calls scatter node selection, error handling, and
  telemetry across the codebase. Each umbrella defines a thin app-level module
  wrapping `RpcLoadBalancer` instead, giving every remote call consistent
  load-balancing, error handling, and a `call_directly?` escape hatch for
  dev/test.

      # BAD — direct erlang RPC
      :rpc.call(node, SharedFeedUtils.FeedServer, :get_state, [adapter, id])

      # GOOD — routed through the app's RPC wrapper
      MyApp.RPC.call_on_random_node("options_feed", SharedFeedUtils.FeedServer, :get_state, [adapter, id])

  Spawning a process directly on a remote node bypasses the same wrapper and is
  banned the same way:

      # BAD — direct remote spawn
      Node.spawn(node, fn -> :ok end)

      # GOOD — spawn through the wrapper's async call helper instead
      MyApp.RPC.call_on_random_node("options_feed", MyWorker, :start_async, [args])

  Files under `:excluded_paths` (default `["rpc_load_balancer/", "elixir_cache/"]`)
  are exempt — those libraries implement the wrapper itself and legitimately
  call `:erpc`/`:rpc` directly.
  """
  @explanation [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    if excluded_path?(source_file.filename, excluded_paths(params)) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      context = build_context(source_file, params)

      source_file
      |> Credo.Code.prewalk(&traverse(&1, &2, context))
      |> Enum.map(&issue_for(&1, issue_meta))
    end
  end

  defp excluded_paths(params), do: Params.get(params, :excluded_paths, __MODULE__)

  defp excluded_path?(filename, excluded_paths) do
    SourceFilter.matches_fragment?(filename, excluded_paths)
  end

  defp build_context(source_file, params) do
    banned_functions = Params.get(params, :functions, __MODULE__)

    %{
      erlang_modules: Params.get(params, :erlang_modules, __MODULE__),
      function_bans: resolve_function_bans(source_file, banned_functions)
    }
  end

  defp resolve_function_bans(source_file, banned_functions) do
    banned_functions
    |> Enum.group_by(fn {module, _function} -> module end, fn {_module, function} -> function end)
    |> Enum.flat_map(&function_bans_for_module(source_file, &1))
    |> MapSet.new()
  end

  defp function_bans_for_module(source_file, {module, functions}) do
    for module_path <- AstHelpers.resolve_aliases(source_file, [module]),
        function <- functions,
        do: {module_path, function}
  end

  defp traverse({{:., _, [erlang_module, function]}, meta, args} = ast, calls, context)
       when is_atom(erlang_module) and is_list(args) do
    if erlang_module in context.erlang_modules do
      trigger = "#{inspect(erlang_module)}.#{function}/#{length(args)}"
      {ast, [reference(trigger, meta) | calls]}
    else
      {ast, calls}
    end
  end

  defp traverse(
         {{:., _, [{:__aliases__, _, module_segments}, function]}, meta, args} = ast,
         calls,
         context
       )
       when is_list(args) do
    if {module_segments, function} in context.function_bans do
      trigger = "#{Enum.join(module_segments, ".")}.#{function}/#{length(args)}"
      {ast, [reference(trigger, meta) | calls]}
    else
      {ast, calls}
    end
  end

  defp traverse(ast, calls, _context), do: {ast, calls}

  defp reference(trigger, meta), do: %{trigger: trigger, line_no: meta[:line]}

  defp issue_for(reference, issue_meta) do
    format_issue(issue_meta,
      message:
        "#{reference.trigger} found — route remote calls through your app's RPC module " <>
          "built on RpcLoadBalancer instead (e.g. MyApp.RPC.call_on_random_node/4)",
      trigger: reference.trigger,
      line_no: reference.line_no
    )
  end
end
