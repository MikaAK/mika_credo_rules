defmodule MikaCredoRules.MigrationForeignKeyNeedsIndex do
  use Credo.Check,
    base_priority: :normal,
    category: :warning,
    param_defaults: [
      migration_paths: ["migrations/"],
      index_functions: [:index, :unique_index]
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
        index_functions: """
        A list of atoms naming the `create`/`create_if_not_exists` functions that
        count as an index. Defaults to `[:index, :unique_index]`.
        """
      ]
    ]

  alias MikaCredoRules.AstHelpers
  alias MikaCredoRules.SourceFilter

  @moduledoc """
  A `references(...)` foreign key column needs a covering index in the same
  migration file.

  An unindexed foreign key forces a sequential scan on every join, and on every
  cascading delete or update from the referenced table. Postgres does not create
  one automatically for a `references/1,2` column the way it does for a primary
  key.

      # BAD
      create table(:users) do
        add :organization_id, references(:organizations), null: false
      end

      # GOOD
      create table(:users) do
        add :organization_id, references(:organizations), null: false
      end

      create index(:users, [:organization_id])

  Any index whose column list includes the foreign key column covers it — a
  composite index counts regardless of the column's position, and
  `create_if_not_exists index(..., concurrently: true)` counts the same as a
  plain `create index(...)`.

  ## Limitations

    * Foreign keys are collected from `add`/`add_if_not_exists` inside a
      `create table(...)`, `create_if_not_exists table(...)`, or `alter
      table(...)` block, and only when both the table name and the column name
      are literal atoms. A dynamically built table or column name is silently
      skipped, not flagged. `modify` is never collected — a pre-existing,
      already-indexed foreign key widened via `modify` would otherwise be a
      false positive.
    * An index added in a *different* migration file is invisible to this
      check — coverage is only checked within the same file.
    * A covering index created by raw SQL (`execute "CREATE INDEX ..."`)
      instead of the `index/1,2` DSL is invisible to this check and still
      fires.
  """
  @explanation [check: @moduledoc]

  @table_creators [:create, :create_if_not_exists]
  @table_modifiers [:create, :create_if_not_exists, :alter]
  @add_functions [:add, :add_if_not_exists]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    if migration_file?(source_file.filename, migration_paths(params)) do
      issue_meta = IssueMeta.for(source_file, params)
      index_functions = Params.get(params, :index_functions, __MODULE__)

      foreign_keys =
        source_file |> Credo.Code.prewalk(&collect_foreign_keys/2, []) |> Enum.reverse()

      indexed_columns =
        Credo.Code.prewalk(source_file, &collect_indexed_columns(&1, &2, index_functions), [])

      foreign_keys
      |> Enum.reject(&covered?(&1, indexed_columns))
      |> Enum.map(&issue_for(&1, issue_meta))
    else
      []
    end
  end

  defp migration_paths(params), do: Params.get(params, :migration_paths, __MODULE__)

  defp migration_file?(filename, migration_paths) do
    SourceFilter.matches_fragment?(filename, migration_paths)
  end

  defp collect_foreign_keys(
         {creator, _, [{:table, _, [table | _opts]}, [{:do, body}]]} = ast,
         foreign_keys
       )
       when creator in @table_modifiers and is_atom(table) do
    {ast, table |> foreign_keys_in_table(body) |> Enum.reverse() |> Enum.concat(foreign_keys)}
  end

  defp collect_foreign_keys(ast, foreign_keys), do: {ast, foreign_keys}

  defp foreign_keys_in_table(table, body) do
    body
    |> AstHelpers.block_statements()
    |> Enum.flat_map(&foreign_key_from_add(table, &1))
  end

  defp foreign_key_from_add(
         table,
         {function, _meta, [column, {:references, ref_meta, ref_args} | _opts]}
       )
       when function in @add_functions and is_atom(column) do
    case ref_args do
      [referenced_table | _] when is_atom(referenced_table) ->
        [
          %{
            table: table,
            column: column,
            referenced_table: referenced_table,
            line_no: ref_meta[:line],
            column_no: ref_meta[:column]
          }
        ]

      _other ->
        []
    end
  end

  defp foreign_key_from_add(_table, _statement), do: []

  defp collect_indexed_columns(
         {creator, _, [{index_fn, _, [table | rest]}]} = ast,
         indexed_columns,
         index_functions
       )
       when creator in @table_creators and is_atom(table) do
    if index_fn in index_functions do
      case columns_from_index_args(rest) do
        nil -> {ast, indexed_columns}
        columns -> {ast, [%{table: table, columns: columns} | indexed_columns]}
      end
    else
      {ast, indexed_columns}
    end
  end

  defp collect_indexed_columns(ast, indexed_columns, _index_functions), do: {ast, indexed_columns}

  defp columns_from_index_args([columns | _opts]) when is_list(columns), do: columns
  defp columns_from_index_args([column | _opts]) when is_atom(column), do: [column]
  defp columns_from_index_args(_args), do: nil

  defp covered?(foreign_key, indexed_columns) do
    Enum.any?(indexed_columns, fn index ->
      index.table === foreign_key.table and foreign_key.column in index.columns
    end)
  end

  defp issue_for(foreign_key, issue_meta) do
    format_issue(issue_meta,
      message:
        "references(#{inspect(foreign_key.referenced_table)}) on #{inspect(foreign_key.column)} found without an index — add `create index(#{inspect(foreign_key.table)}, [#{inspect(foreign_key.column)}])`",
      trigger: "references",
      line_no: foreign_key.line_no,
      column: foreign_key.column_no
    )
  end
end
