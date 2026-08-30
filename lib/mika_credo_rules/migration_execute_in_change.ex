defmodule MikaCredoRules.MigrationExecuteInChange do
  use Credo.Check,
    base_priority: :normal,
    category: :warning,
    param_defaults: [
      migration_paths: ["migrations/"]
    ],
    explanations: [
      params: [
        migration_paths: """
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
  `execute/1` inside `def change` is irreversible — Ecto cannot roll it back.

  `change/0` is used for both `up` and `down`; Ecto rolls it back by replaying
  each reversible operation in reverse. A single-argument `execute/1` has no
  down side, so `mix ecto.rollback` either does nothing for that statement or
  raises `Ecto.MigrationError`. Move the statement into `up/0` and `down/0`, or
  supply the down SQL explicitly with `execute/2`.

      # BAD — no way to roll this back
      def change do
        execute "UPDATE users SET role = 'student' WHERE role IS NULL"
      end

      # GOOD — moved to up/down
      def up, do: execute("UPDATE users SET role = 'student' WHERE role IS NULL")
      def down, do: :ok

      # ALSO GOOD — reversible two-arg form
      def change, do: execute("CREATE EXTENSION citext", "DROP EXTENSION citext")

  `execute/2` is fine everywhere — the second argument is the down statement, so
  the operation is reversible by construction. `execute/1` inside `def up` or
  `def down` is fine too — those functions already commit to irreversibility, so
  there is no additional risk `change/0` doesn't already carry.

  Migration files are identified by path via the `:migration_paths` param, so
  this works the same in an umbrella (`apps/my_app/priv/repo/migrations/...`)
  and a single app (`priv/repo/migrations/...`).
  """
  @explanation [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    if migration_file?(source_file.filename, migration_paths(params)) do
      issue_meta = IssueMeta.for(source_file, params)

      source_file
      |> Credo.Code.prewalk(&collect_change_clauses/2)
      |> Enum.flat_map(&irreversible_executes/1)
      |> Enum.map(&issue_for(&1, issue_meta))
    else
      []
    end
  end

  defp migration_paths(params), do: Params.get(params, :migration_paths, __MODULE__)

  defp migration_file?(filename, migration_paths) do
    SourceFilter.matches_fragment?(filename, migration_paths)
  end

  defp collect_change_clauses({:def, _, [{:change, _, _args}, [{:do, _body}]]} = ast, clauses) do
    {ast, [ast | clauses]}
  end

  defp collect_change_clauses(ast, clauses), do: {ast, clauses}

  defp irreversible_executes({:def, _, [{:change, _, _args}, [{:do, body}]]}) do
    body
    |> Macro.prewalk([], &collect_execute_calls/2)
    |> elem(1)
    |> Enum.reverse()
  end

  defp collect_execute_calls({:execute, meta, [_sql]} = ast, calls) do
    {ast, [%{line_no: meta[:line], column: meta[:column]} | calls]}
  end

  defp collect_execute_calls(ast, calls), do: {ast, calls}

  defp issue_for(execute_call, issue_meta) do
    format_issue(issue_meta,
      message:
        "execute/1 found inside def change — irreversible; move it to up/0 and down/0, or use execute/2 with an explicit down statement",
      trigger: "execute",
      line_no: execute_call.line_no,
      column: execute_call.column
    )
  end
end
