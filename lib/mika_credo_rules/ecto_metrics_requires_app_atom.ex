defmodule MikaCredoRules.EctoMetricsRequiresAppAtom do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      functions: [{PrometheusTelemetry.Metrics.Ecto, :metrics}],
      excluded_paths: []
    ],
    explanations: [
      params: [
        functions: """
        A list of `{module, function}` tuples naming zero-arity calls that
        must instead receive an app atom. Defaults to
        `[{PrometheusTelemetry.Metrics.Ecto, :metrics}]`.
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
  `PrometheusTelemetry.Metrics.Ecto.metrics/0` must not be called — pass the
  app atom.

  `metrics/1` takes exactly one argument (an app atom, used as the telemetry
  event-name prefix and the metric's label tag) and has no `metrics/0`
  clause — calling it with no arguments does not compile. Passing the app
  atom is also what puts the label on every emitted metric.

      # BAD — metrics/0 has no clause; this does not compile
      metrics: [PrometheusTelemetry.Metrics.Ecto.metrics()]

      # GOOD — the app atom is the telemetry event-name prefix and label
      metrics: [PrometheusTelemetry.Metrics.Ecto.metrics(:my_app)]

  Every spelling of the module is caught, including
  `alias PrometheusTelemetry.Metrics` + `Metrics.Ecto.metrics()` and the
  fully-qualified `Elixir.PrometheusTelemetry.Metrics.Ecto.metrics()`.

  ## Known limitations

  Module identity is resolved by splitting each configured `{module,
  function}` pair into its parent (`PrometheusTelemetry.Metrics`) and its
  last segment (`Ecto`), then alias-resolving only the parent — a call's
  module path matches only when everything but its last segment resolves to
  the parent AND the last segment is literally the configured one. This
  deliberately never matches a bare `Ecto.metrics()` — even one reached via
  `alias PrometheusTelemetry.Metrics.Ecto` (aliasing the full submodule down
  to its bare last segment) — because `Ecto` is too common a name to trust a
  bare alias for on its own; that specific spelling is a known false
  negative, accepted to avoid flagging an unrelated module that happens to
  be named `Ecto`.
  """
  @explanation [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    if excluded_path?(source_file.filename, excluded_paths(params)) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      pair_contexts = build_pair_contexts(source_file, params)

      source_file
      |> Credo.Code.prewalk(&traverse(&1, &2, pair_contexts))
      |> Enum.map(&issue_for(&1, issue_meta))
    end
  end

  defp excluded_paths(params), do: Params.get(params, :excluded_paths, __MODULE__)

  defp excluded_path?(filename, excluded_paths) do
    SourceFilter.matches_fragment?(filename, excluded_paths)
  end

  defp build_pair_contexts(source_file, params) do
    params
    |> Params.get(:functions, __MODULE__)
    |> Enum.map(&pair_context(source_file, &1))
  end

  defp pair_context(source_file, {module, function}) do
    {parent_segments, last_segment} = split_module(module)

    %{
      parent_paths: AstHelpers.resolve_aliases(source_file, [Module.concat(parent_segments)]),
      last_segment: last_segment,
      function: function
    }
  end

  # `Module.split/1` returns each segment as a string, but the segment atoms
  # already exist — they were created when this module atom itself was
  # first referenced in source (e.g. as a param default or a `.credo.exs`
  # override) — so String.to_existing_atom/1 is always safe here, never a
  # fresh dynamic atom.
  defp split_module(module) do
    segments = module |> Module.split() |> Enum.map(&String.to_existing_atom/1)
    {parent_segments, [last_segment]} = Enum.split(segments, -1)
    {parent_segments, last_segment}
  end

  defp traverse(
         {{:., _, [{:__aliases__, _, module}, function]}, meta, []} = ast,
         calls,
         pair_contexts
       ) do
    if Enum.any?(pair_contexts, &matches_pair?(&1, module, function)) do
      {ast, [zero_arity_call(module, function, meta) | calls]}
    else
      {ast, calls}
    end
  end

  defp traverse(ast, calls, _pair_contexts), do: {ast, calls}

  defp matches_pair?(pair_context, module, function) do
    function === pair_context.function and parent_matches?(module, pair_context)
  end

  defp parent_matches?(module, pair_context) do
    case Enum.split(module, -1) do
      {parent, [last]} ->
        last === pair_context.last_segment and parent in pair_context.parent_paths

      _ ->
        false
    end
  end

  defp zero_arity_call(module, function, meta) do
    %{
      module: Enum.join(module, "."),
      function: function,
      line_no: meta[:line],
      column: meta[:column]
    }
  end

  defp issue_for(zero_arity_call, issue_meta) do
    trigger = to_string(zero_arity_call.function)
    full_call = "#{zero_arity_call.module}.#{trigger}"

    format_issue(issue_meta,
      message:
        "#{full_call}/0 found — pass the app atom, e.g. #{full_call}(:my_app); #{trigger}/1 requires one argument and there is no #{trigger}/0",
      trigger: trigger,
      line_no: zero_arity_call.line_no,
      column: zero_arity_call.column
    )
  end
end
