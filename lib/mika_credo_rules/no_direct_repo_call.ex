defmodule MikaCredoRules.NoDirectRepoCall do
  use Credo.Check,
    base_priority: :high,
    category: :design,
    param_defaults: [
      repo_suffixes: ["Repo"],
      allowed_functions: [
        :transaction,
        :transact,
        :query,
        :query!,
        :checkout,
        :disconnect_all,
        :config,
        :start_link,
        :stop,
        :load
      ],
      excluded_paths: ["_test.exs", "test/", "priv/repo/", "migrations/"]
    ],
    explanations: [
      params: [
        repo_suffixes: """
        A list of suffixes identifying a repo module by its last alias segment
        as written at the call site — `MyApp.Repo` and, under `alias
        MyApp.Repo`, the bare `Repo` both end in `"Repo"`, as does
        `Schemas.JobsRepo`. Defaults to `["Repo"]`.
        """,
        allowed_functions: """
        A list of atoms naming repo functions that may be called directly.
        Defaults to `[:transaction, :transact, :query, :query!, :checkout,
        :disconnect_all, :config, :start_link, :stop, :load]` — `transaction`
        and `transact` wrap an `Ecto.Multi` or a batch of `EctoShorts.Actions`
        calls, and the rest are raw SQL and pool-management functions that
        `EctoShorts.Actions` has no equivalent for (see Limitations).
        """,
        excluded_paths: """
        A list of path fragments naming files this check skips (matched on
        segment boundaries). Defaults to `["_test.exs", "test/", "priv/repo/",
        "migrations/"]` — tests, seeds, and migrations legitimately touch the
        repo directly.
        """
      ]
    ]

  alias MikaCredoRules.SourceFilter

  @moduledoc """
  Contexts must call `EctoShorts.Actions`, never `Repo` directly.

  A raw `Repo.insert/1` scattered across contexts duplicates the changeset
  pipeline, error mapping, and filtering that `EctoShorts.Actions` already
  centralizes — this is the house rule with the longest incident history.

      # BAD — context calls Repo directly
      defmodule MyApp.Accounts do
        alias MyApp.Repo

        def create_user(attrs) do
          %User{}
          |> User.changeset(attrs)
          |> Repo.insert()
        end
      end

      # GOOD — context calls EctoShorts.Actions
      defmodule MyApp.Accounts do
        alias EctoShorts.Actions

        def create_user(attrs) do
          Actions.create(User, attrs)
        end
      end

  A repo module is identified by its last alias segment *as written at the
  call site* — `MyApp.Repo.insert(changeset)` and, under `alias MyApp.Repo`,
  `Repo.insert(changeset)` are both caught, piped or not, as is a
  differently-named repo such as `Schemas.JobsRepo.delete_all(query)`.
  `Repo.transaction/1` and `Repo.transact/2` are exempt by default (see
  `:allowed_functions`) — they are the direct-Repo calls the house style
  keeps, for wrapping an `Ecto.Multi` or a batch of `Actions` calls. So are
  `Repo.query/2`, `Repo.query!/2`, `Repo.checkout/2`, `Repo.disconnect_all/2`,
  `Repo.config/0`, `Repo.start_link/1`, `Repo.stop/1`, and `Repo.load/2` —
  raw SQL and pool management with no `EctoShorts.Actions` call to redirect
  to. This is a fixed allowlist of those specific functions, not a rule that
  exempts every function `EctoShorts.Actions` cannot express — see
  Limitations for functions that still fire despite having no Actions
  equivalent either.

  A module that itself defines a repo (`use Ecto.Repo`) is exempt entirely,
  including every call inside it:

      # GOOD — the repo module's own body is exempt
      defmodule MyApp.Repo do
        use Ecto.Repo, otp_app: :my_app, adapter: Ecto.Adapters.Postgres

        def custom_insert(changeset) do
          MyApp.Repo.insert(changeset)
        end
      end

  Tests, seeds, and migrations are out of scope by default (see
  `:excluded_paths`) — those layers legitimately talk to the repo directly.

  ## Limitations

    * Module identity is a naming heuristic, not alias resolution, the same
      as `NoBangMailerDeliver`. `alias MyApp.Reporting, as: Repo` would flag
      an unrelated module's calls; renaming a real repo alias away from the
      `Repo` suffix (`alias MyApp.Repo, as: DB`) makes it invisible. The
      heuristic also runs in both directions on the suffix itself: any
      module merely ending in `Repo` is caught, Ecto or not
      (`GitHub.Repo.fetch(name)`), while a repo built on a house wrapper
      instead of a literal `use Ecto.Repo` (`use MyApp.RepoBase, ...`) is
      not recognised as a repo-defining module and stays in scope.
    * Only a literal `Module.function(...)` call at the call site is
      recognised. No import-based `Repo` idiom exists in this house style, so
      an unqualified call is never flagged; an injected repo
      (`@repo.insert!()`, `repo().insert()`) or `apply(Repo, :insert, [x])`
      is also undetected, as is `defdelegate insert(cs), to: MyApp.Repo`
      (no dot-call node exists at the delegate's definition site). So is a
      call through a non-literal alias segment (`__MODULE__.Repo.insert(...)`,
      `unquote(schema).Repo.insert(...)` inside a macro) — the whole alias
      must be written as literal atoms.
    * `:allowed_functions` deliberately omits `Repo.aggregate/3` — unlike the
      functions above it, aggregate queries (`COUNT`, `AVG`, ...) sit closer
      to the CRUD surface `EctoShorts.Actions` covers, so it still fires with
      the Actions message by default; add it via `:allowed_functions` in a
      context that has no Actions equivalent for it.
    * `:allowed_functions` is a fixed list, not "every function
      `EctoShorts.Actions` has no equivalent for" — bulk DML
      (`Repo.insert_all/3`, `Repo.update_all/2`, `Repo.delete_all/2`),
      `Repo.preload/2`, `Repo.exists?/2`, and a house repo wrapper function
      such as `Repo.insert_or_upsert_many/3` all have no `EctoShorts.Actions`
      call to redirect to either, yet still fire with the Actions message by
      default; add whichever ones a given context has no better option for.
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
      repo_suffixes: Params.get(params, :repo_suffixes, __MODULE__),
      allowed_functions: Params.get(params, :allowed_functions, __MODULE__)
    }
  end

  # A module that defines a repo is exempt whole — including every call
  # inside it — so its own `use Ecto.Repo, otp_app: ...` and any
  # self-referential `Repo.insert(...)` never fire. Pruning the whole
  # subtree (`{nil, acc}`) also skips a repo module nested inside another.
  defp traverse(
         {:defmodule, _meta, [_name, [do: body]]} = ast,
         repo_calls,
         _context
       ) do
    if defines_ecto_repo?(body) do
      {nil, repo_calls}
    else
      {ast, repo_calls}
    end
  end

  # @spec/@type/@callback bodies reference types like `Ecto.Repo.t()` in
  # perfectly ordinary code — pruned whole so their arrow types never reach
  # the call clause below.
  defp traverse({:@, _meta, [{attribute, _, _}]}, repo_calls, _context)
       when attribute in [:spec, :type, :typep, :opaque, :callback, :macrocallback] do
    {nil, repo_calls}
  end

  defp traverse(
         {{:., _, [{:__aliases__, alias_meta, module}, function]}, _meta, args} = ast,
         repo_calls,
         context
       )
       when is_list(args) do
    if Enum.all?(module, &is_atom/1) and function !== :{} and
         repo_module?(module, context.repo_suffixes) and
         function not in context.allowed_functions do
      trigger = "#{Enum.join(module, ".")}.#{function}"

      {ast, [repo_call(trigger, alias_meta) | repo_calls]}
    else
      {ast, repo_calls}
    end
  end

  defp traverse(ast, repo_calls, _context), do: {ast, repo_calls}

  # Scans the module's OWN body for `use Ecto.Repo`, pruning nested
  # defmodule subtrees — a nested repo module must not also exempt its
  # enclosing module. The outer prewalk still visits the nested module
  # independently, so it is judged on its own body. `quote` blocks are
  # pruned too: a `use Ecto.Repo` written inside a `__using__` macro's
  # quoted template describes what a CALLER becomes, not this module, so
  # it must not exempt the macro-defining module itself.
  defp defines_ecto_repo?(body) do
    body
    |> Macro.prewalk(false, fn
      {:defmodule, _, _}, found -> {nil, found}
      {:quote, _, _}, found -> {nil, found}
      {:use, _, [{:__aliases__, _, [:Ecto, :Repo]} | _rest]} = ast, _found -> {ast, true}
      ast, found -> {ast, found}
    end)
    |> elem(1)
  end

  defp repo_module?(module, repo_suffixes) do
    last_segment = module |> List.last() |> Atom.to_string()
    Enum.any?(repo_suffixes, &String.ends_with?(last_segment, &1))
  end

  defp repo_call(trigger, meta) do
    %{trigger: trigger, line_no: meta[:line], column: meta[:column]}
  end

  defp issue_for(repo_call, issue_meta) do
    format_issue(issue_meta,
      message:
        "#{repo_call.trigger} found — contexts must call EctoShorts.Actions, never Repo directly",
      trigger: repo_call.trigger,
      line_no: repo_call.line_no,
      column: repo_call.column
    )
  end
end
