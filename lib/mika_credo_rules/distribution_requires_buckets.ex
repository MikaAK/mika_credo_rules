defmodule MikaCredoRules.DistributionRequiresBuckets do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      functions: [:distribution],
      required_keys: [:reporter_options],
      excluded_paths: []
    ],
    explanations: [
      params: [
        functions: """
        A list of atoms naming the `Telemetry.Metrics` functions checked.
        Defaults to `[:distribution]`.
        """,
        required_keys: """
        A list of atoms naming the options that must be present in the
        literal opts keyword list. Defaults to `[:reporter_options]`.
        """,
        excluded_paths: """
        A list of path fragments naming files this check skips. A fragment
        matches when the source file's path starts with it, ends with it, or
        contains it after a directory separator. Defaults to `[]`.
        """
      ]
    ]

  alias MikaCredoRules.AstHelpers
  alias MikaCredoRules.SourceFilter

  @moduledoc """
  `Telemetry.Metrics.distribution/2` must set `:reporter_options` with
  `:buckets`.

  A Prometheus histogram with no configured buckets has nothing to sort
  observations into — the reporter emits no usable data for the metric.

      # BAD
      distribution("my_app.job.duration.microseconds",
        event_name: @stop,
        measurement: :duration
      )

      # GOOD
      distribution("my_app.job.duration.microseconds",
        event_name: @stop,
        measurement: :duration,
        reporter_options: [buckets: @buckets]
      )

  Both the imported local call (behind `import Telemetry.Metrics` in the same
  file) and the qualified `Telemetry.Metrics.distribution(...)` are caught,
  including aliases of the module and the fully-qualified
  `Elixir.Telemetry.Metrics.distribution(...)`. A bare local `distribution/2`
  call with no `import Telemetry.Metrics` in the file is left alone — a local
  function that happens to share the name is not this library's
  `distribution/2`.

  ## Known limitations

  Only a literal keyword list opts argument is inspected — opts built by a
  helper function or held in a variable are invisible to a static check and
  silently skipped rather than guessed at. `distribution/1` (no opts argument
  at all) is out of scope; only the two-argument form is checked.
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
      modules: AstHelpers.resolve_aliases(source_file, [Telemetry.Metrics]),
      functions: Params.get(params, :functions, __MODULE__),
      required_keys: Params.get(params, :required_keys, __MODULE__),
      imports_telemetry_metrics?: imports_telemetry_metrics?(source_file)
    }
  end

  defp imports_telemetry_metrics?(source_file) do
    Credo.Code.prewalk(source_file, &find_telemetry_metrics_import/2, false)
  end

  defp find_telemetry_metrics_import(
         {:import, _, [{:__aliases__, _, target} | _]} = ast,
         found?
       ) do
    {ast, found? or strip_elixir_prefix(target) === [:Telemetry, :Metrics]}
  end

  defp find_telemetry_metrics_import(ast, found?), do: {ast, found?}

  defp strip_elixir_prefix([Elixir | segments]), do: segments
  defp strip_elixir_prefix(segments), do: segments

  # Qualified: Telemetry.Metrics.distribution(name, opts) — or an alias of it.
  defp traverse(
         {{:., _, [{:__aliases__, _, module}, function]}, meta, [_name, opts]} = ast,
         missing,
         context
       ) do
    if module in context.modules and function in context.functions do
      collect_missing(ast, meta, function, opts, missing, context)
    else
      {ast, missing}
    end
  end

  # Local/imported: distribution(name, opts) — only when the file imports
  # Telemetry.Metrics, otherwise a same-named local function is left alone.
  defp traverse({function, meta, [_name, opts]} = ast, missing, context)
       when is_atom(function) do
    if context.imports_telemetry_metrics? and function in context.functions do
      collect_missing(ast, meta, function, opts, missing, context)
    else
      {ast, missing}
    end
  end

  defp traverse(ast, missing, _context), do: {ast, missing}

  defp collect_missing(ast, meta, function, opts, missing, context) do
    case missing_keys(opts, context.required_keys) do
      [] -> {ast, missing}
      keys -> {ast, [distribution_call(function, keys, meta) | missing]}
    end
  end

  defp missing_keys(opts, required_keys) do
    Enum.filter(required_keys, &(AstHelpers.keyword_literal_has_key?(opts, &1) === false))
  end

  defp distribution_call(function, missing_keys, meta) do
    %{function: function, missing_keys: missing_keys, line_no: meta[:line], column: meta[:column]}
  end

  defp issue_for(distribution_call, issue_meta) do
    trigger = to_string(distribution_call.function)
    missing = distribution_call.missing_keys |> Enum.map_join(", ", &inspect/1)

    format_issue(issue_meta,
      message:
        "#{trigger}/2 found — missing #{missing}; a histogram with no buckets emits no usable data (e.g. reporter_options: [buckets: [...]])",
      trigger: trigger,
      line_no: distribution_call.line_no,
      column: distribution_call.column
    )
  end
end
