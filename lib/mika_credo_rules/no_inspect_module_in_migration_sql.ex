defmodule MikaCredoRules.NoInspectModuleInMigrationSql do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      migration_paths: ["migrations/"],
      also_flag_interpolation: true
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
        also_flag_interpolation: """
        Whether string interpolation of a module alias (`"\#{MyApp.Worker}"`) is
        flagged in addition to `inspect/1`. Defaults to `true`; set to `false` to
        narrow the check to `inspect/1` only.
        """
      ]
    ]

  alias MikaCredoRules.SourceFilter

  @moduledoc """
  A module alias must not be rendered with `inspect/1` or string interpolation
  inside a migration.

  Oban's `worker` column (and any similar SQL allow-list of module names) stores
  names WITHOUT the `Elixir.` prefix. `inspect(MyApp.Worker)` and
  `"\#{MyApp.Worker}"` both render `"Elixir.MyApp.Worker"`, so a `WHERE worker IN
  (...)` built from either never matches a row.

      # BAD
      worker_list = Enum.map([DeveloperAi.Workers.TicketScanner], &inspect/1) |> Enum.join("','")
      execute "UPDATE oban_jobs SET queue = 'scanner' WHERE worker IN ('\#{worker_list}')"

      # GOOD
      workers = ~w(DeveloperAi.Workers.TicketScanner) |> Enum.join("','")
      execute "UPDATE oban_jobs SET queue = 'scanner' WHERE worker IN ('\#{workers}')"

  Both spellings are caught anywhere in a migration file: `inspect(MyApp.Worker)`
  and `"\#{MyApp.Worker}"`. Module names have no business being rendered in a
  migration except as a bare string literal.

  ## Limitations

    * Only the literal-argument form is detected. The BAD example above is
      flagged through its `Enum.join("','")` interpolation, not through the
      `Enum.map([...], &inspect/1)` capture — an `inspect/1` capture applied
      indirectly to a list is invisible to this check.
    * `:also_flag_interpolation` set to `false` narrows the check to `inspect/1`
      only.
  """
  @explanation [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    if migration_file?(source_file.filename, migration_paths(params)) do
      issue_meta = IssueMeta.for(source_file, params)
      also_flag_interpolation = Params.get(params, :also_flag_interpolation, __MODULE__)

      source_file
      |> Credo.Code.prewalk(&traverse(&1, &2, also_flag_interpolation))
      |> Enum.map(&issue_for(&1, issue_meta))
    else
      []
    end
  end

  defp migration_paths(params), do: Params.get(params, :migration_paths, __MODULE__)

  defp migration_file?(filename, migration_paths) do
    SourceFilter.matches_fragment?(filename, migration_paths)
  end

  defp traverse({:inspect, meta, [{:__aliases__, _, segments}]} = ast, violations, _also_flag) do
    {ast, [violation(:inspect, meta, segments) | violations]}
  end

  defp traverse(
         {:"::", _,
          [
            {{:., _, [Kernel, :to_string]}, _, [{:__aliases__, alias_meta, segments}]},
            {:binary, _, _}
          ]} = ast,
         violations,
         also_flag_interpolation
       ) do
    if also_flag_interpolation do
      {ast, [violation(:interpolation, alias_meta, segments) | violations]}
    else
      {ast, violations}
    end
  end

  defp traverse(ast, violations, _also_flag_interpolation), do: {ast, violations}

  defp violation(kind, meta, segments) do
    %{kind: kind, line_no: meta[:line], column: meta[:column], module_name: module_name(segments)}
  end

  defp module_name(segments), do: Enum.map_join(segments, ".", &Atom.to_string/1)

  defp issue_for(%{kind: :inspect} = violation, issue_meta) do
    format_issue(issue_meta,
      message:
        "inspect/1 on a module alias found — Oban's worker column strips the Elixir. prefix, so inspect/1's rendered value never matches; use a bare string literal instead",
      trigger: "inspect",
      line_no: violation.line_no,
      column: violation.column
    )
  end

  defp issue_for(%{kind: :interpolation} = violation, issue_meta) do
    format_issue(issue_meta,
      message:
        "string interpolation of a module alias found — Oban's worker column strips the Elixir. prefix, so the interpolated value never matches; use a bare string literal instead",
      trigger: violation.module_name,
      line_no: violation.line_no,
      column: violation.column
    )
  end
end
