defmodule MikaCredoRules.AbsintheDataloaderPluginRequired do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      required_plugins: [Absinthe.Middleware.Dataloader],
      excluded_paths: []
    ],
    explanations: [
      params: [
        required_plugins: """
        A list of modules that must all appear somewhere in `plugins/0`'s body
        when the schema builds a `Dataloader`. Defaults to
        `[Absinthe.Middleware.Dataloader]`.
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
  A `use Absinthe.Schema` module that builds a `Dataloader` must list
  `Absinthe.Middleware.Dataloader` in `plugins/0`.

  Absinthe never runs the Dataloader batches unless the middleware is
  registered — a schema with a `context/1` that builds a loader but no matching
  `plugins/0` compiles and runs fine, and every `dataloader/1,2` field silently
  returns `nil` instead of erroring, which is far harder to diagnose.

      # BAD — no plugins/0, so the loader never batches
      defmodule MyAppWeb.Schema do
        use Absinthe.Schema

        def context(ctx) do
          loader = Dataloader.new() |> Dataloader.add_source(MyApp.Accounts, source())
          Map.put(ctx, :loader, loader)
        end
      end

      # GOOD — the plugin is registered alongside the framework defaults
      defmodule MyAppWeb.Schema do
        use Absinthe.Schema

        def context(ctx) do
          loader = Dataloader.new() |> Dataloader.add_source(MyApp.Accounts, source())
          Map.put(ctx, :loader, loader)
        end

        def plugins, do: [Absinthe.Middleware.Dataloader] ++ Absinthe.Plugin.defaults()
      end

  The check only fires when the module actually builds a loader (`Dataloader.new`
  or `Dataloader.add_source`, alias-aware) — a schema with no Dataloader usage has
  nothing to register and is left alone regardless of `plugins/0`. A `plugins/0`
  is accepted in any shape as long as every required module appears somewhere in
  its body: a bare list, a `++` chain in either order, or something more elaborate.

  Scoped per module, not per file — only a `defmodule` whose own body has
  `use Absinthe.Schema` is inspected, mirroring
  [`NoJasonDeriveOnEctoSchema`](#nojasonderiveonectoschema)'s scoping. A nested
  `defmodule` is its own separate scope and never inherits the outer module's
  `use`.
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
    %{
      schema_paths: AstHelpers.resolve_aliases(source_file, [Absinthe.Schema]),
      dataloader_paths: AstHelpers.resolve_aliases(source_file, [Dataloader]),
      required_plugin_paths: required_plugin_paths(source_file, params)
    }
  end

  defp required_plugin_paths(source_file, params) do
    params
    |> Params.get(:required_plugins, __MODULE__)
    |> Enum.map(&AstHelpers.resolve_aliases(source_file, [&1]))
  end

  # Each defmodule is its own scope: only its own body (nested defmodules
  # excluded) decides whether it is an Absinthe schema and whether its own
  # plugins/0 satisfies the requirement.
  defp traverse({:defmodule, _, [_name, [{:do, body} | _]]} = ast, issues, context) do
    if uses_absinthe_schema?(body, context.schema_paths) do
      {ast, module_issues(body, context) ++ issues}
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _context), do: {ast, issues}

  defp module_issues(body, context) do
    if dataloader_used?(body, context.dataloader_paths) and
         not valid_plugins?(body, context.required_plugin_paths) do
      body |> use_line(context.schema_paths) |> List.wrap()
    else
      []
    end
  end

  defp uses_absinthe_schema?(body, schema_paths) do
    scan_own_body(body, false, fn
      {:use, _, [module | _opts]}, found -> found or module_reference?(module, schema_paths)
      _node, found -> found
    end)
  end

  defp dataloader_used?(body, dataloader_paths) do
    scan_own_body(body, false, fn
      {{:., _, [module, function]}, _, args}, found when is_list(args) ->
        found or (function in [:new, :add_source] and module_reference?(module, dataloader_paths))

      _node, found ->
        found
    end)
  end

  defp valid_plugins?(body, required_plugin_paths) do
    case plugins_def_body(body) do
      nil -> false
      plugins_body -> Enum.all?(required_plugin_paths, &plugin_referenced?(plugins_body, &1))
    end
  end

  defp plugins_def_body(body) do
    scan_own_body(body, nil, fn
      {:def, _, [{:plugins, _, args}, [do: plugins_body]]}, nil when args in [nil, []] ->
        plugins_body

      _node, found ->
        found
    end)
  end

  defp plugin_referenced?(ast, match_set) do
    ast
    |> Macro.prewalk(false, fn
      node, true -> {node, true}
      node, false -> {node, module_reference?(node, match_set)}
    end)
    |> elem(1)
  end

  defp use_line(body, schema_paths) do
    scan_own_body(body, nil, fn
      {:use, meta, [module | _opts]}, nil ->
        if module_reference?(module, schema_paths), do: meta[:line]

      _node, found ->
        found
    end)
  end

  # Walks a module body, pruning nested defmodule subtrees — an inner module
  # is a separate scope for every predicate above.
  defp scan_own_body(body, initial, fun) do
    body
    |> Macro.prewalk(initial, fn
      {:defmodule, _, _}, acc -> {nil, acc}
      node, acc -> {node, fun.(node, acc)}
    end)
    |> elem(1)
  end

  defp module_reference?({:__aliases__, _, segments}, match_set) do
    strip_elixir_prefix(segments) in match_set
  end

  defp module_reference?(module, match_set) when is_atom(module) do
    if elixir_module_atom?(module) do
      [stripped | _elixir_prefixed] = AstHelpers.module_paths(module)
      stripped in match_set
    else
      false
    end
  end

  defp module_reference?(_other, _match_set), do: false

  defp elixir_module_atom?(module) do
    case Atom.to_string(module) do
      "Elixir." <> _rest -> true
      _erlang_name -> false
    end
  end

  defp strip_elixir_prefix([Elixir | segments]), do: segments
  defp strip_elixir_prefix(segments), do: segments

  defp issue_for(line_no, issue_meta) do
    format_issue(issue_meta,
      message:
        "use Absinthe.Schema found — this schema builds a Dataloader but plugins/0 does not list Absinthe.Middleware.Dataloader, so dataloader fields will silently return nil",
      trigger: "use",
      line_no: line_no
    )
  end
end
