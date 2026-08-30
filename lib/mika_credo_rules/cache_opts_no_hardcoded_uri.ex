defmodule MikaCredoRules.CacheOptsNoHardcodedUri do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      cache_modules: [Cache],
      literal_keys: [:uri, :host, :port, :password],
      excluded_paths: ["elixir_cache/"]
    ],
    explanations: [
      params: [
        cache_modules: """
        A list of modules that count as `elixir_cache`'s `Cache` when named in a
        `use` expression. Alias-aware — an `alias`, an `as:` rename, or a
        project module shadowing a single-segment name are all resolved.
        Defaults to `[Cache]`.
        """,
        literal_keys: """
        A list of atoms naming `opts:` keys that must not carry a string or
        integer literal. Defaults to `[:uri, :host, :port, :password]`.
        """,
        excluded_paths: """
        A list of path fragments naming files this check skips, matched on
        path-segment boundaries. Defaults to `["elixir_cache/"]`, exempting the
        library that owns the real connection code.
        """
      ]
    ]

  alias MikaCredoRules.AstHelpers
  alias MikaCredoRules.SourceFilter

  @moduledoc """
  A `use Cache, ..., opts: [...]` definition must not hardcode a connection
  secret or address — use runtime config instead.

  A literal `uri:`, `host:`, `port:` or `password:` in `opts:` bakes the
  connection target (and often a credential) into compiled code, shared by
  every environment the release ships to.

      # BAD — hardcoded in every environment, including the compiled release
      defmodule MyApp.UserCache do
        use Cache,
          adapter: Cache.Redis,
          name: :c,
          sandbox?: Mix.env() === :test,
          opts: [uri: "redis://localhost:6379"]
      end

      # GOOD — resolved at runtime
      defmodule MyApp.UserCache do
        use Cache,
          adapter: Cache.Redis,
          name: :c,
          sandbox?: Mix.env() === :test,
          opts: {MyApp.Config, :redis_opts, []}
      end

  Only a literal `opts:` keyword list is inspected — an MFA tuple, an
  `{app, key}` tuple, an application-env atom, a zero-arity function
  reference, or a variable are all `elixir_cache`'s documented runtime-config
  forms and are never flagged. `Cache` is alias-aware: a project module
  shadowing the bare name (`alias MyApp.Cache`) is correctly not treated as
  `elixir_cache`'s `Cache`.

  `excluded_paths` defaults to `["elixir_cache/"]` — the library's own tests
  and adapters legitimately construct literal connection opts.
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
        literal_keys: Params.get(params, :literal_keys, __MODULE__)
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
        {ast, collect_hardcoded_literals(use_kwlist, context.literal_keys, meta) ++ issues}
    end
  end

  defp traverse(ast, issues, _context), do: {ast, issues}

  defp collect_hardcoded_literals(use_kwlist, literal_keys, meta) do
    use_kwlist
    |> literal_cache_opts()
    |> Enum.filter(&hardcoded_key?(&1, literal_keys))
    |> Enum.map(&hardcoded_literal(&1, meta))
  end

  defp literal_cache_opts(use_kwlist) do
    case Keyword.get(use_kwlist, :opts) do
      cache_opts when is_list(cache_opts) ->
        if Keyword.keyword?(cache_opts), do: cache_opts, else: []

      _other ->
        []
    end
  end

  defp hardcoded_key?({key, value}, literal_keys),
    do: key in literal_keys and literal_value?(value)

  defp literal_value?(value), do: is_binary(value) or is_integer(value)

  defp hardcoded_literal({key, value}, meta) do
    %{key: key, value: value, line_no: meta[:line]}
  end

  defp issue_for(hardcoded, issue_meta) do
    trigger = "#{hardcoded.key}: #{inspect(hardcoded.value)}"

    format_issue(issue_meta,
      message:
        "#{trigger} found — hardcoded #{hardcoded.key} in opts:, use runtime config (e.g. opts: {MyApp.Config, :redis_opts, []})",
      trigger: trigger,
      line_no: hardcoded.line_no
    )
  end
end
