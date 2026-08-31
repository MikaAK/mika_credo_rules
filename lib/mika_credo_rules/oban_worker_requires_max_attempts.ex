defmodule MikaCredoRules.ObanWorkerRequiresMaxAttempts do
  use Credo.Check,
    base_priority: :high,
    category: :design,
    param_defaults: [
      required_keys: [:max_attempts],
      excluded_paths: ["test/"]
    ],
    explanations: [
      params: [
        required_keys: """
        A list of atoms naming the `use Oban.Worker` options that must be
        present in the literal keyword list. Defaults to `[:max_attempts]`.
        """,
        excluded_paths: """
        A list of path fragments naming files this check skips. A fragment
        matches when the source file's path starts with it, ends with it, or
        contains it after a directory separator.

        Defaults to `["test/"]`, exempting throwaway fixture workers defined
        purely to exercise Oban itself.
        """
      ]
    ]

  alias MikaCredoRules.AstHelpers
  alias MikaCredoRules.SourceFilter

  @moduledoc """
  `use Oban.Worker` must set `:max_attempts` explicitly.

  Oban silently falls back to its own retry default when `:max_attempts` is
  omitted, but different job shapes need different attempt counts — a
  fail-fast ingestion job, an auth-refresh job, and a one-shot cron job all
  want different numbers. A worker that never states its count is a worker
  nobody has actually thought about.

      # BAD — relies on whatever Oban currently defaults to
      defmodule MyApp.Workers.SyncOrder do
        use Oban.Worker, queue: :orders
      end

      # BAD — no opts at all
      defmodule MyApp.Workers.SyncOrder do
        use Oban.Worker
      end

      # GOOD — the attempt count is a deliberate part of the worker's contract
      defmodule MyApp.Workers.SyncOrder do
        use Oban.Worker, queue: :orders, max_attempts: 3
      end

  Every spelling of the module is caught, including `alias Oban.Worker` and
  the fully-qualified `Elixir.Oban.Worker`. `:unique` is deliberately not
  required by default — pick it per worker, not by blanket rule.

  ## Known limitations

  Only a literal keyword list in the `use` clause is inspected. A non-literal
  option list — a module attribute (`use Oban.Worker, @worker_opts`) or a
  call that builds the options — is invisible to a static check and is
  silently skipped rather than guessed at.

  `use Oban.Pro.Worker, ...` is a different, unrelated module — it never
  matches the hardcoded `Oban.Worker` alias set this check resolves against,
  so it is invisible to this check.
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
      modules: AstHelpers.resolve_aliases(source_file, [Oban.Worker]),
      required_keys: Params.get(params, :required_keys, __MODULE__)
    }
  end

  defp traverse({:use, meta, [{:__aliases__, _, module}]} = ast, incomplete_uses, context) do
    collect_incomplete_use(ast, meta, module, [], incomplete_uses, context)
  end

  defp traverse(
         {:use, meta, [{:__aliases__, _, module}, opts]} = ast,
         incomplete_uses,
         context
       ) do
    collect_incomplete_use(ast, meta, module, opts, incomplete_uses, context)
  end

  defp traverse(ast, incomplete_uses, _context), do: {ast, incomplete_uses}

  defp collect_incomplete_use(ast, meta, module, opts, incomplete_uses, context) do
    if module in context.modules do
      case missing_keys(opts, context.required_keys) do
        [] -> {ast, incomplete_uses}
        missing -> {ast, [incomplete_use(missing, meta) | incomplete_uses]}
      end
    else
      {ast, incomplete_uses}
    end
  end

  defp missing_keys(opts, required_keys) do
    Enum.filter(required_keys, &(AstHelpers.keyword_literal_has_key?(opts, &1) === false))
  end

  defp incomplete_use(missing_keys, meta) do
    %{missing_keys: missing_keys, line_no: meta[:line], column: meta[:column]}
  end

  defp issue_for(incomplete_use, issue_meta) do
    missing = Enum.map_join(incomplete_use.missing_keys, ", ", &inspect/1)

    format_issue(issue_meta,
      message:
        "use Oban.Worker found — missing #{missing}; set it per job shape (e.g. max_attempts: 3)",
      trigger: "use",
      line_no: incomplete_use.line_no,
      column: incomplete_use.column
    )
  end
end
