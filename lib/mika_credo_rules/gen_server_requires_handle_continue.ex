defmodule MikaCredoRules.GenServerRequiresHandleContinue do
  use Credo.Check,
    base_priority: :normal,
    category: :refactor,
    param_defaults: [
      allowed_modules: [
        Access,
        Enum,
        Keyword,
        Kernel,
        List,
        Logger,
        Map,
        NimbleOptions,
        String,
        {Process, :flag},
        {Process, :monitor},
        {Process, :send_after}
      ]
    ],
    explanations: [
      params: [
        allowed_modules: """
        Modules and functions that may be called from `init/1` without deferring to
        `handle_continue/2`. A bare module (e.g. `Keyword`) allows every function on
        it; a `{module, function}` tuple (e.g. `{Process, :flag}`) allows only that
        function, keeping the rest of the module flagged.

        The list replaces the default rather than extending it, so include the defaults
        again when adding your own. Erlang modules are given as plain atoms (e.g. `:ets`
        or `{:ets, :new}`).
        """
      ]
    ]

  alias MikaCredoRules.AstHelpers

  @moduledoc """
  GenServer `init/1` must defer real work to `handle_continue/2`.

  `init/1` blocks `GenServer.start_link/3` and with it everything else the supervisor
  still has to start. An `init/1` that hits the database, another process or the
  network delays the whole supervision tree and risks the five second `init` timeout.
  Build the initial state, return `{:ok, state, {:continue, term}}`, and do the work
  in `handle_continue/2`.

      # BAD — blocks the supervisor while the query runs
      defmodule MyApp.Server do
        use GenServer

        def init(opts) do
          rows = MyApp.Repo.all(MyApp.Row)
          {:ok, %{rows: rows, opts: opts}}
        end
      end

      # GOOD — init/1 only builds state, the query runs in handle_continue/2
      defmodule MyApp.Server do
        use GenServer

        def init(opts) do
          {:ok, %{rows: [], opts: opts}, {:continue, :load}}
        end

        def handle_continue(:load, state) do
          {:noreply, %{state | rows: MyApp.Repo.all(MyApp.Row)}}
        end
      end

  This check is a heuristic. Files without a literal `use GenServer` are skipped
  entirely. In files that have one, an `init/1` clause is flagged when it contains a
  remote call not covered by the `:allowed_modules` list and no `{:continue, _}`
  tuple anywhere in the clause. Each clause is judged on its own — a `{:continue, _}`
  in one clause does not excuse blocking work in another — and each violating clause
  produces one issue, anchored at its first disallowed call.

  The allow-list mixes whole modules and single functions. A bare module entry
  (`Keyword`, `Logger`) allows every call on it; a `{module, function}` tuple grants
  one function surgically. The defaults allow the cheap init idioms
  `Process.flag/2`, `Process.monitor/1` and `Process.send_after/3` without allowing
  `Process` wholesale — so a blocking `Process.sleep/1` in `init/1` stays flagged.

  Known approximations, chosen to keep the check cheap and false positives rare:

    * A `{:continue, _}` tuple anywhere in a clause counts as deferring, even when it
      is not in return position.
    * Local function calls are always allowed — the check cannot cheaply resolve what
      a private helper does.
    * Struct literals (`%__MODULE__{}`, `%SomeStruct{}`) and calls on `__MODULE__`
      are allowed.
    * `use GenServer` is detected per file, so every `init/1` in a file that uses
      GenServer anywhere is checked, and a `use` injected by another macro's
      `__using__` is invisible.
    * Aliases are not resolved — a module is matched by the name it is written as, so
      `alias MyApp.Repo` followed by `Repo.all/1` is flagged as `Repo`, not
      `MyApp.Repo`.
  """
  @explanation [check: @moduledoc]

  @genserver_paths AstHelpers.module_paths(GenServer)

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    if genserver_file?(source_file) do
      issue_meta = IssueMeta.for(source_file, params)
      allowed_entries = allowed_entries(params)

      source_file
      |> Credo.Code.prewalk(&collect_init_clauses/2)
      |> Enum.flat_map(&clause_violations(&1, allowed_entries))
      |> Enum.map(&issue_for(&1, issue_meta))
    else
      []
    end
  end

  defp genserver_file?(source_file) do
    Credo.Code.prewalk(source_file, &detect_use_genserver/2, false)
  end

  defp detect_use_genserver({:use, _, [{:__aliases__, _, path} | _]} = ast, _found)
       when path in @genserver_paths do
    {ast, true}
  end

  defp detect_use_genserver(ast, found), do: {ast, found}

  defp allowed_entries(params) do
    params
    |> Params.get(:allowed_modules, __MODULE__)
    |> Enum.map(&normalize_allowed_entry/1)
  end

  defp normalize_allowed_entry({module, function}), do: {normalize_atom_module(module), function}
  defp normalize_allowed_entry(module), do: normalize_atom_module(module)

  defp normalize_atom_module(module) do
    case Atom.to_string(module) do
      "Elixir." <> _rest -> Module.split(module)
      _erlang_name -> module
    end
  end

  defp collect_init_clauses({:def, _, [head, _body]} = ast, clauses) do
    if init_head?(head) do
      {ast, [ast | clauses]}
    else
      {ast, clauses}
    end
  end

  defp collect_init_clauses(ast, clauses), do: {ast, clauses}

  defp init_head?({:when, _, [head | _guards]}), do: init_head?(head)
  defp init_head?({:init, _, [_single_arg]}), do: true
  defp init_head?(_head), do: false

  defp clause_violations(clause, allowed_entries) do
    if contains_continue?(clause) do
      []
    else
      clause
      |> remote_calls()
      |> Enum.filter(&disallowed?(&1, allowed_entries))
      |> Enum.take(1)
    end
  end

  defp contains_continue?(clause) do
    clause
    |> Macro.prewalk(false, &detect_continue/2)
    |> elem(1)
  end

  defp detect_continue({:continue, _term} = ast, _found), do: {ast, true}
  defp detect_continue(ast, found), do: {ast, found}

  defp remote_calls(clause) do
    clause
    |> Macro.prewalk([], &collect_remote_calls/2)
    |> elem(1)
    |> Enum.reverse()
  end

  defp collect_remote_calls({{:., _, [target, function]}, meta, args} = ast, calls)
       when is_atom(function) and is_list(args) do
    case call_target(target) do
      nil -> {ast, calls}
      module -> {ast, [%{module: module, function: function, line_no: meta[:line]} | calls]}
    end
  end

  defp collect_remote_calls(ast, calls), do: {ast, calls}

  # Alias paths become lists of name strings, erlang modules stay atoms. Targets
  # that are not statically named modules (variables, `__MODULE__`, dynamic
  # segments) resolve to nil and are treated as local.
  defp call_target({:__aliases__, _, path}) do
    if Enum.all?(path, &is_atom/1) do
      path
      |> Enum.map(&Atom.to_string/1)
      |> strip_elixir_prefix()
    end
  end

  defp call_target({:__MODULE__, _, _}), do: nil
  defp call_target(module) when is_atom(module), do: normalize_atom_module(module)
  defp call_target(_target), do: nil

  defp strip_elixir_prefix(["Elixir" | rest]) when rest !== [], do: rest
  defp strip_elixir_prefix(path), do: path

  defp disallowed?(%{module: module, function: function}, allowed_entries) do
    module not in allowed_entries and {module, function} not in allowed_entries
  end

  defp issue_for(remote_call, issue_meta) do
    trigger = "#{module_name(remote_call.module)}.#{remote_call.function}"

    format_issue(issue_meta,
      message:
        "#{trigger} found in GenServer init/1 — defer init work to handle_continue/2 by returning {:ok, state, {:continue, term}}",
      trigger: trigger,
      line_no: remote_call.line_no
    )
  end

  defp module_name(path) when is_list(path), do: Enum.join(path, ".")
  defp module_name(erlang_module), do: inspect(erlang_module)
end
