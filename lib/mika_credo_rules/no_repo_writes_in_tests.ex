defmodule MikaCredoRules.NoRepoWritesInTests do
  use Credo.Check,
    base_priority: :high,
    category: :design,
    param_defaults: [
      functions: [
        :insert,
        :insert!,
        :insert_all,
        :update,
        :update!,
        :update_all,
        :delete,
        :delete!,
        :delete_all,
        :insert_or_update,
        :insert_or_update!
      ],
      repo_modules: [],
      test_files: ["_test.exs"],
      excluded_paths: ["test/support/"]
    ],
    explanations: [
      params: [
        functions: """
        A list of atoms naming the write-side `Ecto.Repo` functions to flag.
        Read functions (`get`, `all`, `one`, `preload`) are never in this list —
        asserting on persisted state is the correct way to pin a test.
        """,
        repo_modules: """
        A list of additional repo modules to treat as write targets, for repos
        that are not named `Repo` (or `*.Repo`). Alias-resolved via
        `AstHelpers.resolve_aliases/2`, so `alias MyApp.DataStore` and
        `alias MyApp.DataStore, as: Store` are both caught.

        Defaults to `[]` — the built-in "last alias segment is `:Repo`"
        heuristic already covers the common case without this param.
        """,
        test_files: """
        A list of file path suffixes treated as test files. Defaults to
        `["_test.exs"]`.
        """,
        excluded_paths: """
        A list of path fragments, matched at a path-segment boundary, to skip
        even when the file is a test file. Defaults to `["test/support/"]` —
        factories and `DataCase` helpers under `test/support/` legitimately
        write to the database.
        """
      ]
    ]

  alias MikaCredoRules.AstHelpers
  alias MikaCredoRules.SourceFilter

  @moduledoc """
  Tests must not write to the database directly — use `FactoryEx` for test data.

  A raw `Repo.insert!/1` in a test hardcodes every required association and
  default inline, so it silently drifts from the schema's real constraints and
  breaks the moment a constraint changes elsewhere. `FactoryEx` centralizes
  that shape in one factory module every test shares.

      # BAD
      {:ok, user} = Repo.insert(%User{email: "a@b.c"})
      Repo.insert_all(Order, rows)
      %User{email: "a@b.c"} |> Repo.insert!()

      # GOOD
      user = FactoryEx.insert!(MyApp.Support.Factory.User)

  Reads are left alone — asserting on persisted state is the correct way to pin
  a behavioural test:

      # GOOD — reads are not writes
      assert %User{} = Repo.get(User, user.id)
      assert Repo.all(User) === []

  A repo is identified two ways: any `__aliases__` path whose last segment is
  `:Repo` (`MyApp.Repo`, `Repo`, `Schemas.Repo`) — which needs no alias
  tracking, since Elixir's own aliasing always preserves the last segment —
  plus any module named in `:repo_modules`, alias-resolved for repos that are
  not named `Repo` at all.

  This is the complement of blitz `NoRampantRepos`, which excludes every
  `.exs` file and so never sees a single one of these. Run both.

  ## Limitations

  A repo with no `FactoryEx` setup at all will fail every one of these issues
  with no path forward — ship this opt-in rather than in a recommended-default
  bundle until `FactoryEx` is wired up.
  """
  @explanation [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    if scoped?(source_file.filename, params) do
      issue_meta = IssueMeta.for(source_file, params)
      context = build_context(source_file, params)

      source_file
      |> Credo.Code.prewalk(&traverse(&1, &2, context))
      |> Enum.map(&issue_for(&1, issue_meta))
    else
      []
    end
  end

  defp scoped?(filename, params) do
    SourceFilter.matches_suffix?(filename, test_files(params)) and
      not SourceFilter.matches_fragment?(filename, excluded_paths(params))
  end

  defp test_files(params), do: Params.get(params, :test_files, __MODULE__)
  defp excluded_paths(params), do: Params.get(params, :excluded_paths, __MODULE__)

  defp build_context(source_file, params) do
    repo_modules = Params.get(params, :repo_modules, __MODULE__)

    %{
      repo_module_paths: AstHelpers.resolve_aliases(source_file, repo_modules),
      functions: Params.get(params, :functions, __MODULE__)
    }
  end

  defp traverse(
         {{:., _, [{:__aliases__, _, module}, function]}, meta, args} = ast,
         repo_writes,
         context
       )
       when is_list(args) do
    if repo_module?(module, context) and function in context.functions do
      trigger = "#{Enum.join(module, ".")}.#{function}"
      {ast, [repo_write(trigger, meta) | repo_writes]}
    else
      {ast, repo_writes}
    end
  end

  defp traverse(ast, repo_writes, _context), do: {ast, repo_writes}

  defp repo_module?(module, context) do
    List.last(module) === :Repo or module in context.repo_module_paths
  end

  defp repo_write(trigger, meta), do: %{trigger: trigger, line_no: meta[:line]}

  defp issue_for(repo_write, issue_meta) do
    format_issue(issue_meta,
      message: "#{repo_write.trigger} found in a test — use FactoryEx for test data",
      trigger: repo_write.trigger,
      line_no: repo_write.line_no
    )
  end
end
