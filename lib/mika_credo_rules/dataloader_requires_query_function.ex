defmodule MikaCredoRules.DataloaderRequiresQueryFunction do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      excluded_paths: ["_test.exs", "test/"]
    ],
    explanations: [
      params: [
        excluded_paths: """
        A list of path fragments naming files this check skips, matched on
        path-segment boundaries. Defaults to `["_test.exs", "test/"]` — test
        fixtures routinely construct a bare `Dataloader.Ecto` source with no
        need to honour GraphQL filter args.
        """
      ]
    ]

  alias MikaCredoRules.AstHelpers
  alias MikaCredoRules.SourceFilter

  @moduledoc """
  `Dataloader.Ecto.new/1,2` must set `query:` — without it, association loads
  fall back to `Dataloader.Ecto`'s own default query function, which discards
  every GraphQL filter, order, and paginate argument the caller passes.

      # BAD — no query function, so filter args on association loads are dropped
      Dataloader.Ecto.new(MyApp.Repo)

      # GOOD — filter args flow through EctoShorts.CommonFilters
      Dataloader.Ecto.new(MyApp.Repo, query: &EctoShorts.CommonFilters.convert_params_to_filter/2)

  A piped construction (`MyApp.Repo |> Dataloader.Ecto.new(query: ...)`) is
  handled the same way: the pipe's right-hand call carries one fewer argument
  than the call actually has (the repo is the pipe's left-hand side, not a
  call argument), so the true arity is re-derived as `1 + length(args)` and
  the opts — when present — are inspected exactly like the non-piped form. A
  piped call with `query:` set stays silent; one missing it is flagged the
  same as its non-piped equivalent, at its own true arity (`.../1` for zero
  opts, `.../2` for a literal opts list).

  Only a literal opts keyword list is inspected — opts held in a variable or
  built by a helper function is invisible to a static check and left alone
  rather than guessed at (an accepted false negative), whether the call is
  piped or not. `Dataloader.KV.new/1,2` is a different source type with no
  query-function contract and is never matched.

  ## Limitations

    * Opts held in a variable or module attribute
      (`Dataloader.Ecto.new(MyApp.Repo, @opts)`) is invisible and silently
      skipped — the same is true under a pipe
      (`MyApp.Repo |> Dataloader.Ecto.new(opts)`).

  Alias-aware on `Dataloader.Ecto`: an `alias`, an `as:` rename, and the
  fully qualified `Elixir.Dataloader.Ecto` spelling are all resolved.
  Aliases injected by a macro (via `__using__`) are invisible to Credo and
  cannot be resolved.
  """
  @explanation [check: @moduledoc]

  @required_key :query

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    if excluded_path?(source_file.filename, excluded_paths(params)) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      context = build_context(source_file)

      source_file
      |> Credo.Code.prewalk(&traverse(&1, &2, context))
      |> Enum.map(&issue_for(&1, issue_meta))
    end
  end

  defp excluded_paths(params), do: Params.get(params, :excluded_paths, __MODULE__)

  defp excluded_path?(filename, excluded_paths) do
    SourceFilter.matches_fragment?(filename, excluded_paths)
  end

  defp build_context(source_file) do
    %{dataloader_ecto_paths: AstHelpers.resolve_aliases(source_file, [Dataloader.Ecto])}
  end

  # A piped call is consumed here: the pipe's right-hand call node carries one
  # fewer argument than the call actually has (the repo is the pipe's LHS,
  # not a call argument), so the true arity is re-derived as
  # `1 + length(args)` before the same missing-query? check runs, and the
  # call's head is rewritten to a block (keeping args traversable) so the
  # standalone clause below never re-examines the same call at the wrong
  # argument positions.
  defp traverse({:|>, pipe_meta, [lhs, piped_call]} = ast, issues, context) do
    case new_call(piped_call, context) do
      {module, alias_meta, args} when length(args) in [0, 1] ->
        {{:|>, pipe_meta, [lhs, {:__block__, [], args}]},
         collect_issue(issues, module, alias_meta, length(args) + 1, List.first(args))}

      _not_a_matching_new_call ->
        {ast, issues}
    end
  end

  # Dataloader.Ecto.new(repo) — arity 1, opts default to [] at runtime, so
  # :query can never be present.
  defp traverse(ast, issues, context) do
    case new_call(ast, context) do
      {module, alias_meta, [_repo]} ->
        {ast, collect_issue(issues, module, alias_meta, 1, nil)}

      {module, alias_meta, [_repo, opts]} ->
        {ast, collect_issue(issues, module, alias_meta, 2, opts)}

      _not_a_matching_new_call ->
        {ast, issues}
    end
  end

  defp new_call({{:., _, [{:__aliases__, alias_meta, module}, :new]}, _meta, args}, context) do
    if module in context.dataloader_ecto_paths, do: {module, alias_meta, args}
  end

  defp new_call(_ast, _context), do: nil

  defp collect_issue(issues, module, alias_meta, arity, opts) do
    if missing_query?(arity, opts) do
      [dataloader_call(module, arity, alias_meta) | issues]
    else
      issues
    end
  end

  # True arity 1 means no opts were ever written — opts default to [] at
  # runtime, so :query can never be present.
  defp missing_query?(1, _opts), do: true

  # keyword_literal_has_key?/2 is tri-state — :not_literal means opts were
  # built at runtime, which must not count as missing.
  defp missing_query?(2, opts),
    do: match?(false, AstHelpers.keyword_literal_has_key?(opts, @required_key))

  defp dataloader_call(module, arity, meta) do
    %{
      trigger: "#{Enum.join(module, ".")}.new",
      arity: arity,
      line_no: meta[:line],
      column: meta[:column]
    }
  end

  defp issue_for(call, issue_meta) do
    format_issue(issue_meta,
      message:
        "#{call.trigger}/#{call.arity} found — missing query:; without it, GraphQL filter, order, and paginate args on association loads are silently dropped (e.g. query: &EctoShorts.CommonFilters.convert_params_to_filter/2)",
      trigger: call.trigger,
      line_no: call.line_no,
      column: call.column
    )
  end
end
