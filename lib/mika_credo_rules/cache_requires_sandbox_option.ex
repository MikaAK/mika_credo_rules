defmodule MikaCredoRules.CacheRequiresSandboxOption do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      cache_modules: [Cache],
      required_keys: [:sandbox?],
      excluded_paths: []
    ],
    explanations: [
      params: [
        cache_modules: """
        A list of modules that count as `elixir_cache`'s `Cache` when named in a
        `use` expression. Alias-aware — an `alias`, an `as:` rename, or a
        project module shadowing a single-segment name are all resolved.
        Defaults to `[Cache]`.
        """,
        required_keys: """
        A list of atoms that must be present in a `use Cache, ...` literal
        keyword list. Defaults to `[:sandbox?]`.
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
  A `use Cache, ...` module definition must set `sandbox?: Mix.env() === :test`
  — without it, tests hit the real backend (Redis, ETS) and break async safety.

      # BAD — tests hit the real Redis backend
      defmodule MyApp.UserCache do
        use Cache, adapter: Cache.Redis, name: :my_app_user_cache, opts: :my_app
      end

      # GOOD — the sandbox swaps in a per-test in-memory adapter
      defmodule MyApp.UserCache do
        use Cache,
          adapter: Cache.Redis,
          name: :my_app_user_cache,
          sandbox?: Mix.env() === :test,
          opts: :my_app
      end

  Only a literal `use Cache, ...` keyword list is inspected — `use Cache, @opts`
  or any other non-literal options are left alone, since the check cannot
  reason about what an attribute or variable holds. `Cache` is alias-aware: a
  project module shadowing the bare name (`alias MyApp.Cache`) is correctly not
  treated as `elixir_cache`'s `Cache`, so `use Cache, ...` under that alias
  never fires.

  `NoMixEnvAtRuntime` only flags `Mix.env()`/`Mix.target()` calls inside a
  `def`/`defp` body — a module-body `use Cache, sandbox?: Mix.env() === :test`
  is a `use` option list, not a function body, so the two checks do not
  conflict; running both together is safe.
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
        cache_paths:
          AstHelpers.resolve_aliases(source_file, Params.get(params, :cache_modules, __MODULE__)),
        required_keys: Params.get(params, :required_keys, __MODULE__)
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

  defp traverse({:use, meta, _} = ast, issues, context) do
    case AstHelpers.use_options(ast, context.cache_paths) do
      nil ->
        {ast, issues}

      use_kwlist ->
        if missing_required_keys?(use_kwlist, context.required_keys) do
          {ast, [%{line_no: meta[:line]} | issues]}
        else
          {ast, issues}
        end
    end
  end

  defp traverse(ast, issues, _context), do: {ast, issues}

  defp missing_required_keys?(use_kwlist, required_keys) do
    Enum.any?(required_keys, &(not Keyword.has_key?(use_kwlist, &1)))
  end

  defp issue_for(cache_use, issue_meta) do
    format_issue(issue_meta,
      message:
        "use Cache without :sandbox? found — add sandbox?: Mix.env() === :test or tests hit the real backend",
      trigger: "use",
      line_no: cache_use.line_no
    )
  end
end
