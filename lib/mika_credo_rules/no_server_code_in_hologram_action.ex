defmodule MikaCredoRules.NoServerCodeInHologramAction do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      hologram_modules: [Hologram.Page, Hologram.Component],
      action_callbacks: [:action],
      banned_modules: [
        Repo,
        Ecto,
        Ecto.Query,
        Oban,
        File,
        IO,
        Port,
        Process,
        System,
        Node,
        SharedUtils.HTTP,
        Finch,
        Req,
        HTTPoison
      ],
      banned_functions: [
        :get_session,
        :put_session,
        :delete_session,
        :get_cookie,
        :put_cookie,
        :delete_cookie
      ],
      banned_forms: [:with, :try, :receive]
    ],
    explanations: [
      params: [
        hologram_modules: """
        Modules whose `use` marks a `defmodule` as a Hologram module in scope
        for this check.
        """,
        action_callbacks: """
        Function names treated as client-side action callbacks. Only `def`
        clauses of arity 3 with one of these names are inspected — `command/3`
        and `init/3` run on the server and are never checked.
        """,
        banned_modules: """
        Modules that must not be called from an action. `Repo` is matched by
        its LAST segment (so `MyApp.Repo.insert/1` is caught without listing
        every app's repo module); `Ecto` is matched BY PREFIX (so
        `Ecto.Changeset`, `Ecto.Multi`, and every other `Ecto.*` submodule are
        caught, not just `Ecto` and `Ecto.Query` themselves); every other
        entry is matched by its exact, alias-resolved path.
        """,
        banned_functions: """
        Local (unqualified) function names that must not be called from an
        action. Session and cookie access is only available in `init/3` and
        `command/3`.
        """,
        banned_forms: """
        Special forms not usable inside an action because Hologram's client
        compiler does not implement them yet (as of Hologram 0.8.3) — this
        list is expected to shrink as the framework matures.
        """
      ]
    ]

  alias MikaCredoRules.AstHelpers
  alias MikaCredoRules.HologramModules

  @moduledoc """
  A Hologram action must not call the server, touch sessions/cookies, or use
  a form the client compiler doesn't implement yet — actions run entirely in
  the browser.

  Actions are Hologram's client-side callbacks: no DB, no filesystem, no
  network round-trip, no server session. Work that needs any of those belongs
  in a command, dispatched via `put_command/2,3` and returned to the client
  through `put_action/2,3`.

      # BAD — hits the database from the client
      defmodule MyApp.ProductPage do
        use Hologram.Page

        def action(:save, params, component) do
          MyApp.Repo.insert(%Product{name: params.name})
        end
      end

      # GOOD — defers the write to a command
      defmodule MyApp.ProductPage do
        use Hologram.Page

        def action(:save, params, component) do
          put_command(component, :save_product, name: params.name)
        end

        def command(:save_product, params, server) do
          MyApp.Repo.insert(%Product{name: params.name})
          server
        end
      end

  Three independent things are flagged inside a `def action(...)` clause of
  arity 3 (one issue per offending node):

    * a call on a banned module (`Repo`, `Ecto.*`, `Oban`, `File`, `IO`,
      `Port`, `Process`, `System`, `Node`, `SharedUtils.HTTP`, `Finch`,
      `Req`, `HTTPoison`) — actions run client-side only;
    * a local call to a session/cookie function (`get_session`,
      `put_session`, `delete_session`, `get_cookie`, `put_cookie`,
      `delete_cookie`) — only available in `init/3` and `command/3`;
    * a `with`, `try`, or `receive` form — not implemented in Hologram's
      client compiler as of version 0.8.3.

  Scoped per module, not per file — only a `defmodule` whose own body
  contains `use Hologram.Page`/`use Hologram.Component` is inspected, and
  within it only `action/3` clauses; `command/3` and `init/3` run on the
  server and are exempt. A plain context function called from an action
  (`MyApp.Accounts.list_users()`) is not itself flagged — only the modules
  in `:banned_modules` are.

  ## Limitations

  `:banned_forms` covers the explicit `try do ... end` block only, not the
  implicit `def action(...) do ... rescue ... end` form — Hologram's
  unsupported-forms list is expected to change across versions, so every
  entry is a param; relax or extend it as the framework's client compiler
  gains features.
  """
  @explanation [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    context = build_context(source_file, params)

    source_file
    |> HologramModules.hologram_module_bodies(context.hologram_modules)
    |> Enum.flat_map(fn {_module_ast, body} ->
      HologramModules.own_body_callback_clauses(body, context.action_callbacks)
    end)
    |> Enum.flat_map(&collect_clause_violations(&1, context))
    |> Enum.map(&issue_for(&1, issue_meta))
  end

  defp build_context(source_file, params) do
    banned_modules = Params.get(params, :banned_modules, __MODULE__)

    %{
      hologram_modules: Params.get(params, :hologram_modules, __MODULE__),
      action_callbacks: Params.get(params, :action_callbacks, __MODULE__),
      banned_functions: Params.get(params, :banned_functions, __MODULE__),
      banned_forms: Params.get(params, :banned_forms, __MODULE__),
      module_context: build_module_context(source_file, banned_modules)
    }
  end

  defp build_module_context(source_file, banned_modules) do
    %{
      repo?: Repo in banned_modules,
      ecto_prefix?: Ecto in banned_modules,
      exact_paths: AstHelpers.resolve_aliases(source_file, banned_modules)
    }
  end

  defp collect_clause_violations(clause, context) do
    HologramModules.scan_own_body(clause, [], &collect_action_violation(&1, &2, context))
  end

  defp collect_action_violation(
         {{:., _, [module_ast, function]}, meta, args},
         violations,
         context
       )
       when is_atom(function) and is_list(args) do
    if banned_module_call?(module_ast, context.module_context) do
      [module_violation(module_ast, function, meta) | violations]
    else
      violations
    end
  end

  defp collect_action_violation({node_name, meta, args}, violations, context)
       when is_atom(node_name) and is_list(args) do
    cond do
      node_name in context.banned_functions ->
        [local_call_violation(node_name, meta) | violations]

      node_name in context.banned_forms ->
        [form_violation(node_name, meta) | violations]

      true ->
        violations
    end
  end

  defp collect_action_violation(_node, violations, _context), do: violations

  defp banned_module_call?({:__aliases__, _, segments}, module_context) do
    resolved = strip_elixir_prefix(segments)

    (module_context.repo? and List.last(resolved) === :Repo) or
      (module_context.ecto_prefix? and List.first(resolved) === :Ecto) or
      resolved in module_context.exact_paths
  end

  defp banned_module_call?(_module_ast, _module_context), do: false

  defp module_violation(module_ast, function, meta) do
    %{trigger: "#{module_display(module_ast)}.#{function}", line_no: meta[:line], kind: :module}
  end

  defp module_display({:__aliases__, _, segments}),
    do: segments |> strip_elixir_prefix() |> Enum.join(".")

  defp local_call_violation(function, meta) do
    %{trigger: Atom.to_string(function), line_no: meta[:line], kind: :session_or_cookie}
  end

  defp form_violation(form, meta) do
    %{trigger: Atom.to_string(form), line_no: meta[:line], kind: :form}
  end

  defp strip_elixir_prefix([Elixir | segments]), do: segments
  defp strip_elixir_prefix(segments), do: segments

  defp issue_for(%{kind: :module} = violation, issue_meta) do
    format_issue(issue_meta,
      message:
        "#{violation.trigger} found in a Hologram action — actions run client-side only, move DB/IO/server calls into command/3",
      trigger: violation.trigger,
      line_no: violation.line_no
    )
  end

  defp issue_for(%{kind: :session_or_cookie} = violation, issue_meta) do
    format_issue(issue_meta,
      message:
        "#{violation.trigger} found in a Hologram action — session and cookies are only available in init/3 and command/3, move this into command/3",
      trigger: violation.trigger,
      line_no: violation.line_no
    )
  end

  defp issue_for(%{kind: :form} = violation, issue_meta) do
    format_issue(issue_meta,
      message:
        "#{violation.trigger} found in a Hologram action — with/try/receive are not implemented in the client compiler as of Hologram 0.8.3, move this logic into command/3",
      trigger: violation.trigger,
      line_no: violation.line_no
    )
  end
end
