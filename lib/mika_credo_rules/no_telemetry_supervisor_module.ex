defmodule MikaCredoRules.NoTelemetrySupervisorModule do
  use Credo.Check,
    base_priority: :high,
    category: :design,
    param_defaults: [
      module_suffixes: [:Telemetry],
      supervisor_modules: [Supervisor],
      excluded_paths: []
    ],
    explanations: [
      params: [
        module_suffixes: """
        A list of atoms. A `defmodule` whose last name segment is one of these is
        inspected. Defaults to `[:Telemetry]`.
        """,
        supervisor_modules: """
        A list of modules that count as the `Supervisor` behaviour when named in a
        `use` expression. Alias-aware — an `alias`, an `as:` rename, or a project
        module shadowing a single-segment name are all resolved. Defaults to
        `[Supervisor]`.
        """,
        excluded_paths: """
        A list of path fragments naming files this check skips, matched on
        path-segment boundaries.
        """
      ]
    ]

  alias MikaCredoRules.AstHelpers
  alias MikaCredoRules.SourceFilter

  @moduledoc """
  A dedicated `*Telemetry` supervisor module must not exist — add a
  `{PrometheusTelemetry, ...}` child spec to `application.ex` instead.

  `phx.new` generates a `MyAppWeb.Telemetry` supervisor that wraps
  `:telemetry_poller` and `Telemetry.Metrics`. The house convention replaces it
  with `PrometheusTelemetry`, started directly as a child of the application —
  a separate supervisor module for it only adds indirection.

      # BAD — the file phx.new generates
      defmodule MyAppWeb.Telemetry do
        use Supervisor

        def start_link(arg), do: Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
      end

      # GOOD — a child spec in application.ex, no separate supervisor module
      children = [{PrometheusTelemetry, exporter: [enabled?: @is_prod], metrics: [...]}]

  A `defmodule` is flagged when its last name segment is a member of
  `:module_suffixes` (default `[:Telemetry]`) **and** its own body contains
  `use Supervisor` (or an alias resolving to one of `:supervisor_modules`).
  Scoped per module, not per file — a nested `defmodule Telemetry do ... end`
  is its own scope, independent of its parent, the same way
  `NoJasonDeriveOnEctoSchema` scopes `@derive`. A `Telemetry` module that is
  not a `Supervisor`, or a `Supervisor` not named `Telemetry`, is left alone.
  """
  @explanation [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    if excluded_path?(source_file.filename, excluded_paths(params)) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)

      context = %{
        module_suffixes: Params.get(params, :module_suffixes, __MODULE__),
        supervisor_paths:
          AstHelpers.resolve_aliases(
            source_file,
            Params.get(params, :supervisor_modules, __MODULE__)
          )
      }

      source_file
      |> Credo.Code.prewalk(&traverse(&1, &2, context))
      |> Enum.map(&issue_for(&1, issue_meta))
    end
  end

  defp excluded_paths(params), do: Params.get(params, :excluded_paths, __MODULE__)

  defp excluded_path?(filename, excluded_paths) do
    SourceFilter.matches_fragment?(filename, excluded_paths)
  end

  # Each defmodule is its own scope: only its own body (nested defmodules
  # excluded) decides whether it is a Telemetry-named Supervisor. Nested
  # defmodules are still visited by the outer prewalk, so each gets the same
  # treatment independently.
  defp traverse(
         {:defmodule, meta, [{:__aliases__, _, segments}, [{:do, body} | _]]} = ast,
         issues,
         context
       ) do
    if telemetry_suffix?(segments, context.module_suffixes) and
         uses_supervisor?(body, context.supervisor_paths) do
      {ast, [%{line_no: meta[:line]} | issues]}
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _context), do: {ast, issues}

  defp telemetry_suffix?(segments, module_suffixes), do: List.last(segments) in module_suffixes

  defp uses_supervisor?(body, supervisor_paths) do
    scan_own_body(body, false, fn
      {:use, _, [module | _]}, found -> found or supervisor_module?(module, supervisor_paths)
      _node, found -> found
    end)
  end

  # Walks a module body, pruning nested defmodule subtrees — an inner module
  # neither inherits the outer telemetry/supervisor status nor contributes to it.
  defp scan_own_body(body, initial, fun) do
    body
    |> Macro.prewalk(initial, fn
      {:defmodule, _, _}, acc -> {nil, acc}
      node, acc -> {node, fun.(node, acc)}
    end)
    |> elem(1)
  end

  defp supervisor_module?({:__aliases__, _, segments}, supervisor_paths),
    do: strip_elixir_prefix(segments) in supervisor_paths

  defp supervisor_module?(module, _supervisor_paths) when is_atom(module),
    do: module === Supervisor

  defp supervisor_module?(_other, _supervisor_paths), do: false

  defp strip_elixir_prefix([Elixir | segments]), do: segments
  defp strip_elixir_prefix(segments), do: segments

  defp issue_for(telemetry_module, issue_meta) do
    format_issue(issue_meta,
      message:
        "defmodule ...Telemetry with use Supervisor found — add a {PrometheusTelemetry, ...} child spec to application.ex instead of a separate Telemetry supervisor module",
      trigger: "defmodule",
      line_no: telemetry_module.line_no
    )
  end
end
