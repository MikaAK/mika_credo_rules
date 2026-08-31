defmodule MikaCredoRules.NoRawEts do
  use Credo.Check,
    base_priority: :high,
    category: :design,
    param_defaults: [
      erlang_modules: [:ets],
      allowed_functions: [:info, :whereis, :all],
      excluded_paths: ["elixir_cache/"]
    ],
    explanations: [
      params: [
        erlang_modules: """
        A list of erlang module atoms banned as raw in-memory stores. Defaults
        to `[:ets]`. Add `:dets` or `:persistent_term` to widen the ban — they
        are opt-in because they serve different purposes than `:ets`.
        """,
        allowed_functions: """
        A list of function names on a banned module that are never flagged,
        even outside `:excluded_paths`. Defaults to `[:info, :whereis, :all]` —
        pure diagnostics that neither create nor mutate a table.
        """,
        excluded_paths: """
        A list of path fragments. A source file is exempt when its path starts
        or ends with a fragment, or contains one after a `/` — matching
        happens on path-segment boundaries.

        Defaults to `["elixir_cache/"]`, exempting the library that implements
        the `Cache.ETS` adapter itself.
        """
      ]
    ]

  alias MikaCredoRules.SourceFilter

  @moduledoc """
  Raw `:ets` must not be used for caching — wrap it in `Cache.ETS`.

  `:ets.new/2`, `:ets.insert/2`, and `:ets.lookup/2` reimplement what
  `elixir_cache` already provides with TTL, sandboxing, and a consistent API.
  A hand-rolled ETS cache also skips the test isolation a `Cache` sandbox gives
  every other cache-backed test.

      # BAD
      table = :ets.new(:price_cache, [:set, :named_table, read_concurrency: true])
      :ets.insert(table, {"AAPL", 150.25})
      [{_, price}] = :ets.lookup(table, "AAPL")

      # GOOD
      defmodule MyApp.PriceCache do
        use Cache, adapter: Cache.ETS, name: :price_cache, sandbox?: Mix.env() === :test
      end

      MyApp.PriceCache.put("AAPL", 150.25)

  This check scans test files as well as `lib/` — `elixir_cache`'s own rule
  extends the ban to test fixtures, since a raw `:ets` table in a test setup
  breaks the same async-safety guarantees a `Cache` sandbox provides.

  Diagnostic-only functions (`:ets.info/1,2`, `:ets.whereis/1`, `:ets.all/0`)
  are always allowed, even outside `:excluded_paths` — they read process-wide
  state and never create or mutate a table.

  ## Limitations

  This check is architectural, not universal — `elixir-distributed`'s
  feed-server pattern legitimately builds its whole design on raw `:ets` for
  lock-free, high-read shared state, and that skill's own reference
  implementation calls `:ets.new`/`:ets.insert`/`:ets.lookup` directly.
  Adopters running feed servers should add those paths to `:excluded_paths`
  before enabling this check — treat it as opt-in, not default-on, in any repo
  that owns a feed server.

  `apply(:ets, :insert, [table, entry])` and `mod = :ets; mod.insert(...)` are
  both undetected — only a literal `:ets.function(...)` dot-call is matched.
  """
  @explanation [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    if excluded_path?(source_file.filename, excluded_paths(params)) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      context = build_context(params)

      source_file
      |> Credo.Code.prewalk(&traverse(&1, &2, context))
      |> Enum.map(&issue_for(&1, issue_meta))
    end
  end

  defp excluded_paths(params), do: Params.get(params, :excluded_paths, __MODULE__)

  defp excluded_path?(filename, excluded_paths) do
    SourceFilter.matches_fragment?(filename, excluded_paths)
  end

  defp build_context(params) do
    %{
      erlang_modules: Params.get(params, :erlang_modules, __MODULE__),
      allowed_functions: Params.get(params, :allowed_functions, __MODULE__)
    }
  end

  defp traverse({{:., _, [erlang_module, function]}, meta, args} = ast, calls, context)
       when is_atom(erlang_module) and is_list(args) do
    if erlang_module in context.erlang_modules and function not in context.allowed_functions do
      trigger = "#{inspect(erlang_module)}.#{function}/#{length(args)}"
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
        "#{reference.trigger} found — use Cache.ETS from elixir_cache instead of raw :ets " <>
          "(e.g. `use Cache, adapter: Cache.ETS`)",
      trigger: reference.trigger,
      line_no: reference.line_no
    )
  end
end
