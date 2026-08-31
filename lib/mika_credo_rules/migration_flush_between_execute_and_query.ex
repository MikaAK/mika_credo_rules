defmodule MikaCredoRules.MigrationFlushBetweenExecuteAndQuery do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      migration_paths: ["migrations/"],
      direct_query_functions: [:query, :query!, :query_many, :query_many!],
      flush_function: :flush
    ],
    explanations: [
      params: [
        migration_paths: """
        A list of path fragments treated as migration directories, matched at a
        path-segment boundary via `MikaCredoRules.SourceFilter.matches_fragment?/2`.

        Defaults to `["migrations/"]`, which covers both an umbrella
        (`apps/my_app/priv/repo/migrations/...`) and a single app
        (`priv/repo/migrations/...`).
        """,
        direct_query_functions: """
        A list of atoms naming the `repo()` functions that run immediately, on a
        separate connection from the deferred `execute/1,2` DSL. Defaults to
        `[:query, :query!, :query_many, :query_many!]`.
        """,
        flush_function: """
        The name of the function that forces deferred `execute/1,2` statements to
        run before continuing. Defaults to `:flush`.
        """
      ]
    ]

  @moduledoc """
  A direct `repo().query`/`query!`/`query_many`/`query_many!` call must not
  follow `execute/1,2` in the same migration body without a `flush()` between
  them.

  `execute/1,2` is DSL — Ecto queues it to run at the end of the migration, on the
  migration runner's connection. `repo().query!/1` runs immediately, on a separate
  connection from the pool. Without `flush()` between them, the direct query sees
  the pre-`execute` state, not the state the migration just wrote.

      # BAD — the SELECT runs before the UPDATE has committed
      def up do
        execute "UPDATE oban_jobs SET queue = 'scanner' WHERE worker IN ('A','B')"
        repo().query!("SELECT DISTINCT worker FROM oban_jobs WHERE queue = 'default'")
      end

      # GOOD — flush() forces the UPDATE to run first
      def up do
        execute "UPDATE oban_jobs SET queue = 'scanner' WHERE worker IN ('A','B')"
        flush()
        repo().query!("SELECT DISTINCT worker FROM oban_jobs WHERE queue = 'default'")
      end

  The check reads only the top-level statements of a `def up`/`down`/`change`
  body — a plain, in-order scan for `execute`, `flush()` and a direct query call.
  A `flush()` resets the pairing; anything else between an `execute` and a query
  (a `Logger` call, another DSL statement) does not.

  ## Limitations

    * Only top-level statements are inspected. An `execute`/query pair nested
      inside a conditional branch, or a `flush()` hidden inside a helper function
      called between them, is invisible to this check.
  """
  @explanation [check: @moduledoc]

  alias MikaCredoRules.SourceFilter

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    if migration_file?(source_file.filename, migration_paths(params)) do
      issue_meta = IssueMeta.for(source_file, params)
      context = build_context(params)

      source_file
      |> Credo.Code.prewalk(&collect_migration_clauses/2)
      |> Enum.flat_map(&violations_in_clause(&1, context))
      |> Enum.map(&issue_for(&1, issue_meta))
    else
      []
    end
  end

  defp migration_paths(params), do: Params.get(params, :migration_paths, __MODULE__)

  defp migration_file?(filename, migration_paths) do
    SourceFilter.matches_fragment?(filename, migration_paths)
  end

  defp build_context(params) do
    %{
      direct_query_functions: Params.get(params, :direct_query_functions, __MODULE__),
      flush_function: Params.get(params, :flush_function, __MODULE__)
    }
  end

  @migration_callbacks [:up, :down, :change]

  defp collect_migration_clauses({:def, _, [{name, _, _args}, [{:do, body}]]} = ast, clauses)
       when name in @migration_callbacks do
    {ast, [body | clauses]}
  end

  defp collect_migration_clauses(ast, clauses), do: {ast, clauses}

  defp violations_in_clause(body, context) do
    body
    |> block_statements()
    |> scan_statements(context)
  end

  defp block_statements({:__block__, _, statements}), do: statements
  defp block_statements(statement), do: [statement]

  defp scan_statements(statements, context) do
    {violations, _pending_execute?} =
      Enum.reduce(statements, {[], false}, &scan_statement(&1, &2, context))

    Enum.reverse(violations)
  end

  defp scan_statement(statement, {violations, pending_execute?}, context) do
    case classify_statement(statement, context) do
      :execute -> {violations, true}
      :flush -> {violations, false}
      {:query, query} when pending_execute? -> {[query | violations], pending_execute?}
      _other -> {violations, pending_execute?}
    end
  end

  defp classify_statement({:execute, _meta, args}, _context) when is_list(args), do: :execute

  defp classify_statement({function, _meta, []}, %{flush_function: flush_function})
       when function === flush_function,
       do: :flush

  defp classify_statement(
         {{:., _, [{:repo, _, []}, _function]}, _meta, args} = ast,
         %{direct_query_functions: direct_query_functions}
       )
       when is_list(args) do
    ast |> dot_call_query(direct_query_functions) |> query_or_other()
  end

  # `case repo().query!(...) do ... end` — the query is the case's subject,
  # evaluated eagerly before any branch. This is the shape
  # `dev-ai/.../rename_oban_default_queue.exs` was mined from; without this
  # clause the query is invisible because the top-level statement is `:case`,
  # not a direct dot-call.
  defp classify_statement(
         {:case, _meta, [subject | _clauses]},
         %{direct_query_functions: direct_query_functions}
       ) do
    subject |> find_nested_query(direct_query_functions) |> query_or_other()
  end

  # `{:ok, result} = repo().query!(...)` — the query is the match's right-hand
  # side, also evaluated eagerly.
  defp classify_statement(
         {:=, _meta, [_lhs, rhs]},
         %{direct_query_functions: direct_query_functions}
       ) do
    rhs |> find_nested_query(direct_query_functions) |> query_or_other()
  end

  defp classify_statement(_statement, _context), do: :other

  defp query_or_other(nil), do: :other
  defp query_or_other(query), do: {:query, query}

  defp find_nested_query(expr, direct_query_functions) do
    {_ast, queries} =
      Macro.prewalk(expr, [], &collect_dot_call_query(&1, &2, direct_query_functions))

    List.last(queries)
  end

  defp collect_dot_call_query(ast, queries, direct_query_functions) do
    case dot_call_query(ast, direct_query_functions) do
      nil -> {ast, queries}
      query -> {ast, [query | queries]}
    end
  end

  defp dot_call_query(
         {{:., _, [{:repo, repo_meta, []}, function]}, _meta, args},
         direct_query_functions
       )
       when is_list(args) do
    if function in direct_query_functions do
      %{function: function, line_no: repo_meta[:line], column: repo_meta[:column]}
    end
  end

  defp dot_call_query(_ast, _direct_query_functions), do: nil

  defp issue_for(query, issue_meta) do
    trigger = "repo().#{query.function}"

    format_issue(issue_meta,
      message:
        "#{trigger} found after execute/1,2 with no flush() between them — execute/1,2 is deferred to the end of the migration, so a direct query on another connection sees the pre-execute state; call flush() first",
      trigger: trigger,
      line_no: query.line_no,
      column: query.column
    )
  end
end
