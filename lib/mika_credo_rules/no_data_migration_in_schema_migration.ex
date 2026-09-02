defmodule MikaCredoRules.NoDataMigrationInSchemaMigration do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      included_paths: ["migrations/"]
    ],
    explanations: [
      params: [
        included_paths: """
        A list of path fragments treated as migration directories, matched at a
        path-segment boundary via `MikaCredoRules.SourceFilter.matches_fragment?/2`.

        Defaults to `["migrations/"]`, which covers both an umbrella
        (`apps/my_app/priv/repo/migrations/...`) and a single app
        (`priv/repo/migrations/...`).
        """
      ]
    ]

  alias MikaCredoRules.SourceFilter

  @moduledoc """
  A migration must not mix DDL with data DML in the same `change`/`up` body.

  A migration that both alters the schema and rewrites data holds the DDL's lock
  across the data rewrite — every row the `UPDATE`/`INSERT`/`DELETE`/`MERGE`
  touches sits behind the same transaction as the `create`/`alter`/`drop` — and
  it can't be safely retried, since re-running a partially-applied migration
  re-runs the DDL too. Split the data step into its own migration, an Oban job,
  or a `mix run` task.

      # BAD — the UPDATE shares a transaction with the alter's lock
      def change do
        alter table(:users) do
          add :status, :string
        end

        execute "UPDATE users SET status = 'active' WHERE status IS NULL"
      end

      # GOOD — the data rewrite moves to its own migration
      def change do
        alter table(:users) do
          add :status, :string
        end
      end

      # BAD — repo().update_all is the same shape as an execute() UPDATE
      def up do
        create index(:users, [:status])
        repo().update_all(MyApp.User, set: [status: "active"])
      end

      # GOOD — a pure data migration, on its own, is legitimate
      def change do
        execute "UPDATE users SET status = 'active' WHERE status IS NULL"
      end

  Both `execute/1,2` string literals (matched case-insensitively against
  `UPDATE`/`INSERT`/`DELETE`/`MERGE` at the start of the SQL, including the
  leading literal segment of a heredoc that goes on to interpolate) and
  `repo().update_all/insert_all/delete_all` count as the data-DML half. For
  the `repo()` spellings, piped into (`from(...) |> repo().update_all(...)`)
  or called directly makes no difference; `execute/1,2` is only recognised
  called directly (see Limitations). The DDL half is `create`,
  `create_if_not_exists`, `alter`, `drop`, `drop_if_exists`, or `rename` on a
  `table(...)`/`index(...)`/`unique_index(...)` target. Only `def change` and
  `def up` are scanned — `def down` is exempt, since it only ever reverses
  what `up` already committed. A `rescue`/`after`/`else`/`catch` clause on
  `def change`/`def up` does not shrink what's scanned — the `do` body is
  still scanned the same as without one.

  ## Limitations

    * `execute/1,2`'s SQL must be a plain double-quoted string, a heredoc, or
      a heredoc/string whose leading literal segment (before its first
      `\#{...}`) contains the DML keyword; a sigil literal (`~s(...)`), a
      variable, or a DML keyword that only appears inside or after an
      interpolation is invisible to this check.
    * `execute/1,2` piped into (`sql |> execute()`) is invisible to this
      check — unlike the `repo()` spellings, only the directly-called form
      is recognised.
    * Only the bare, unqualified `execute(...)` and
      `repo().update_all/insert_all/delete_all` spellings are recognised — a
      qualified `Ecto.Migration.execute(...)` call is not.
    * The DDL half only recognises a `table(...)`/`index(...)`/`unique_index(...)`
      target — `create constraint(...)` does not count as DDL for this check.
    * Both halves must live directly in the scanned `change`/`up` body —
      moving the DML into a helper `defp` called from `change`/`up` (an
      ordinary refactor) hides it from this check.
    * The DDL half must be a `table(...)`/`index(...)`/`unique_index(...)`
      call target — a DDL statement written as raw SQL
      (`execute "CREATE TABLE ..."`) is not recognised as the DDL half.
    * The DML regex anchors at the very start of the SQL string with no
      multiline flag — a leading SQL comment line (e.g. in a heredoc) before
      the `UPDATE`/`INSERT`/`DELETE`/`MERGE` keyword hides the match.
  """
  @explanation [check: @moduledoc]

  @scanned_callbacks [:change, :up]
  @ddl_functions [:create, :create_if_not_exists, :alter, :drop, :drop_if_exists, :rename]
  @ddl_targets [:table, :index, :unique_index]
  @dml_repo_functions [:update_all, :insert_all, :delete_all]
  @dml_pattern ~r/^\s*(UPDATE|INSERT|DELETE|MERGE)\b/i

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    if migration_file?(source_file.filename, included_paths(params)) do
      issue_meta = IssueMeta.for(source_file, params)

      source_file
      |> Credo.Code.prewalk(&collect_scanned_bodies/2)
      |> Enum.flat_map(&data_dml_sites/1)
      |> Enum.map(&issue_for(&1, issue_meta))
    else
      []
    end
  end

  defp included_paths(params), do: Params.get(params, :included_paths, __MODULE__)

  defp migration_file?(filename, included_paths),
    do: SourceFilter.matches_fragment?(filename, included_paths)

  defp collect_scanned_bodies(
         {:def, _, [{name, _, _args}, [{:do, body} | _rescue_after_else]]} = ast,
         bodies
       )
       when name in @scanned_callbacks do
    {ast, [body | bodies]}
  end

  defp collect_scanned_bodies(ast, bodies), do: {ast, bodies}

  defp data_dml_sites(body) do
    {_ast, {ddl_present?, dml_sites}} = Macro.prewalk(body, {false, []}, &classify_node/2)

    if ddl_present?, do: Enum.reverse(dml_sites), else: []
  end

  defp classify_node(ast, {ddl_present?, dml_sites}) do
    case dml_site(ast) do
      nil -> {ast, {ddl_present? or ddl_call?(ast), dml_sites}}
      site -> {ast, {ddl_present?, [site | dml_sites]}}
    end
  end

  defp ddl_call?({function, _meta, [{target, _target_meta, _target_args} | _rest]})
       when function in @ddl_functions and target in @ddl_targets,
       do: true

  defp ddl_call?(_ast), do: false

  defp dml_site({:execute, meta, [sql | _rest]}) do
    case dml_sql_text(sql) do
      nil ->
        nil

      text ->
        if Regex.match?(@dml_pattern, text) do
          %{line_no: meta[:line], column: meta[:column], trigger: "execute"}
        end
    end
  end

  defp dml_site({{:., _, [{:repo, repo_meta, []}, function]}, _meta, args})
       when function in @dml_repo_functions and is_list(args) do
    %{line_no: repo_meta[:line], column: repo_meta[:column], trigger: "repo().#{function}"}
  end

  defp dml_site(_ast), do: nil

  defp dml_sql_text(sql) when is_binary(sql), do: sql
  defp dml_sql_text({:<<>>, _meta, [first | _rest]}) when is_binary(first), do: first
  defp dml_sql_text(_sql), do: nil

  defp issue_for(site, issue_meta) do
    format_issue(issue_meta,
      message:
        "#{site.trigger} found alongside DDL in the same migration — mixing schema DDL with a data rewrite holds the DDL's lock across it and can't be safely retried; move the data step into its own migration, an Oban job, or a mix task",
      trigger: site.trigger,
      line_no: site.line_no,
      column: site.column
    )
  end
end
