defmodule MikaCredoRules.PrometheusExporterMustBeGated do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      keys: [:exporter],
      excluded_paths: ["test/"]
    ],
    explanations: [
      params: [
        keys: """
        A list of atoms naming the outer keyword-list keys inspected for a
        hardcoded `enabled?: true` value. Defaults to `[:exporter]`.
        """,
        excluded_paths: """
        A list of path fragments naming files this check skips, matched on
        path-segment boundaries. Defaults to `["test/"]` — a test double
        whose entire purpose is a running exporter (e.g. a mock supervisor in
        `test/support/`) is not production config and the suggested
        `@is_prod` gate would break it. `.exs` files are always exempt
        regardless of this param — a config file may legitimately hardcode
        the flag for a single environment.
        """
      ]
    ]

  alias MikaCredoRules.SourceFilter

  @moduledoc """
  The Prometheus exporter must not be hardcoded to `enabled?: true` — gate it
  to production so metrics aren't exposed in dev and test.

  An always-on exporter opens an HTTP endpoint in every environment. The
  idiomatic gate is a compile-time flag derived from
  `Application.compile_env/3`.

      # BAD — the exporter runs in every environment, including dev and test
      @is_prod Application.compile_env(:my_app, :env) === :prod
      {PrometheusTelemetry, exporter: [enabled?: true], metrics: [...]}

      # GOOD — gated to production
      @is_prod Application.compile_env(:my_app, :env) === :prod
      {PrometheusTelemetry, exporter: [enabled?: @is_prod], metrics: [...]}

  Only the literal `enabled?: true` pair inside a keyword list or map literal
  keyed by one of `:keys` (default `[:exporter]`) is flagged, wherever it
  appears in the file. A computed value (`enabled?: @is_prod`,
  `enabled?: some_var()`) always passes — the check can only reason about a
  literal `true`.

  `.exs` files are exempt — `config/prod.exs` may legitimately hardcode
  `enabled?: true` for a single environment's config file. A `case`/`fn`
  clause head (a pattern, not literal config) and the body of a `@type`/
  `@spec` (a type variable, not literal config) are never inspected.

  ## Known limitations

  Two-element tuples of literals carry no position metadata in the Elixir AST
  (the same trap `ErrorMessageRequired` documents), so the reported line is
  the nearest enclosing expression that has one — exact when the exporter
  tuple is written on one line, approximate for a hand-wrapped multi-line
  child spec.

  The check only recognises a literal `enabled?: true` pair written directly
  inside the keyed list — none of these evade it, and none currently trigger
  a warning:

    * `exporter: [enabled?: true] ++ extra()` — a runtime concatenation
    * `Keyword.put([], :enabled?, true)` — built via a function call
    * `conf = [enabled?: true]; exporter: conf` — assigned to a variable
      first, then referenced — the realistic way a hardcoded flag evades
      review, since the offending literal and the flagged key are on
      different lines
  """
  @explanation [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    if exempt_file?(source_file.filename, params) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      context = %{keys: Params.get(params, :keys, __MODULE__)}

      source_file
      |> Credo.Code.prewalk(&traverse(&1, &2, context), %{line: nil, issues: []})
      |> Map.fetch!(:issues)
      |> Enum.map(&issue_for(&1, issue_meta))
    end
  end

  defp exempt_file?(filename, params) do
    SourceFilter.script_file?(filename) or
      SourceFilter.matches_fragment?(filename, excluded_paths(params))
  end

  defp excluded_paths(params), do: Params.get(params, :excluded_paths, __MODULE__)

  # @type/@spec bodies are type variables, not literal config — prune the
  # whole attribute so an `enabled?: true` inside a typespec is never
  # inspected (the suggested @is_prod fix is not valid there anyway).
  defp traverse({:@, _meta, [{attr, _, _}]}, acc, _context) when attr in [:type, :spec] do
    {nil, acc}
  end

  # case/fn clause heads are patterns, not literal data — a keyword literal
  # there is a match test, not hardcoded config. Prune the head, keep the
  # body traversable.
  defp traverse({:->, meta, [_lhs, body]}, acc, context) do
    ast = {:->, meta, [[], body]}
    acc = remember_line(acc, ast)

    {ast, record_gated_pair(ast, acc, context)}
  end

  defp traverse(ast, acc, context) do
    acc = remember_line(acc, ast)

    {ast, record_gated_pair(ast, acc, context)}
  end

  # Two-element tuples (and keyword pairs, which share the same AST shape)
  # carry no position metadata, so issues are reported at the line of the
  # nearest enclosing expression that has one.
  defp remember_line(acc, {_form, meta, _args}) when is_list(meta) do
    case meta[:line] do
      nil -> acc
      line -> %{acc | line: line}
    end
  end

  defp remember_line(acc, _ast), do: acc

  defp record_gated_pair({key, value}, acc, context) when is_atom(key) and is_list(value) do
    if key in context.keys and enabled_true?(value) do
      %{acc | issues: [%{key: key, line_no: acc.line} | acc.issues]}
    else
      acc
    end
  end

  defp record_gated_pair(_ast, acc, _context), do: acc

  defp enabled_true?(value), do: {:enabled?, true} in value

  defp issue_for(gated_pair, issue_meta) do
    trigger = "#{gated_pair.key}: [enabled?: true]"

    format_issue(issue_meta,
      message:
        "#{trigger} found — gate the exporter to prod (e.g. enabled?: @is_prod with @is_prod Application.compile_env(:my_app, :env) === :prod)",
      trigger: trigger,
      line_no: gated_pair.line_no
    )
  end
end
