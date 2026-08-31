defmodule MikaCredoRules.NoTaskAsyncInGenServer do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      banned: [{Task, :async}, {Task.Supervisor, :async}],
      callbacks: [
        :init,
        :handle_call,
        :handle_cast,
        :handle_info,
        :handle_continue,
        :handle_events,
        :handle_demand,
        :terminate
      ],
      behaviour_modules: [GenServer, GenStage]
    ],
    explanations: [
      params: [
        banned: """
        `{module, function}` pairs that must not be called from inside a callback
        body. Matched by exact function name only — `Task.async_stream/2` is a
        different, unlinked API and is never caught by the default
        `{Task, :async}` entry.
        """,
        callbacks: """
        Function names treated as GenServer/GenStage callbacks — only the bodies of
        clauses with one of these names are inspected. A public client-side
        function defined in the same module runs in the caller's process, not the
        server's, and is never scanned.
        """,
        behaviour_modules: """
        Modules whose `use` marks a file as worth scanning at all. Alias-aware via
        `MikaCredoRules.AstHelpers.resolve_aliases/2`.
        """
      ]
    ]

  alias MikaCredoRules.AstHelpers

  @moduledoc """
  `Task.async` and `Task.Supervisor.async` must not be called from inside a
  GenServer or GenStage callback.

  `Task.async/1,3` LINKS the new task to the process that calls it. If the task
  crashes, the link propagates the crash to that process. Inside a callback, the
  caller IS the GenServer/GenStage process itself — a crashing task takes the
  whole server down with it. `Task.Supervisor.async/2,3,4` links the same way; only
  its `async_nolink` sibling isolates the crash.

      # BAD — a crashing task takes the GenServer down with it
      def handle_continue(:init_work, state) do
        task = Task.async(fn -> expensive_fetch(state.config) end)
        {:noreply, %{state | task_ref: task.ref}}
      end

      # GOOD — isolate the crash, handle it explicitly
      def handle_continue(:init_work, state) do
        task = Task.Supervisor.async_nolink(MyApp.TaskSupervisor, fn -> expensive_fetch(state.config) end)
        {:noreply, %{state | task_ref: task.ref}}
      end

      def handle_info({ref, result}, %{task_ref: ref} = state) do
        Process.demonitor(ref, [:flush])
        {:noreply, %{state | task_ref: nil, data: result}}
      end

      def handle_info({:DOWN, ref, :process, _pid, reason}, %{task_ref: ref} = state) do
        Logger.error("\#{__MODULE__}: task crashed, reason: \#{inspect(reason)}")
        {:noreply, %{state | task_ref: nil}}
      end

  There is no bare `Task.async_nolink/1,2` — only the supervised
  `Task.Supervisor.async_nolink/2,3,4` exists, which needs a `Task.Supervisor`
  already running in the app's supervision tree.

  Only the bodies of callbacks (`:callbacks`, defaulting to `init/1`,
  `handle_call/3`, `handle_cast/2`, `handle_info/2`, `handle_continue/2`,
  `handle_events/3`, `handle_demand/2`, `terminate/2`) are inspected. A public
  client-side function defined in the same module runs in the CALLER's process,
  not the server's, and may legitimately want the link `Task.async` provides (a
  fan-out helper the client calls directly) — so this check never looks at the
  whole module, only at callback bodies.

  `async` is matched by exact function name, never a prefix —
  `Task.async_stream/2` is a different, unlinked API and is never flagged here
  (see `TaskAsyncStreamRequiresTimeout` for that one).

  ## Limitations

    * Only qualified calls (`Task.async(...)`, `Supervisor.async(...)` under
      `alias Task.Supervisor`) are matched. `import Task` followed by a bare
      `async(...)` call, and `apply(Task, :async, [fun])`, are both invisible
      to this check — dynamic dispatch and unqualified calls evade the AST
      matcher, an explicit trade-off, not an oversight.
    * A file is scanned only when it has a literal `use` of one of
      `:behaviour_modules` — a `use` injected by another macro's `__using__` is
      invisible to Credo and to this check.
    * A `Task.async(...)` written inside a `quote` block is never flagged —
      quoted code builds AST at compile time and is not a call the callback
      actually makes.
  """
  @explanation [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    behaviour_modules = Params.get(params, :behaviour_modules, __MODULE__)

    if AstHelpers.uses_module?(source_file, behaviour_modules) do
      issue_meta = IssueMeta.for(source_file, params)
      banned_entries = banned_entries(source_file, params)
      callbacks = Params.get(params, :callbacks, __MODULE__)

      source_file
      |> AstHelpers.callback_clauses(callbacks)
      |> Enum.flat_map(&violations(&1, banned_entries))
      |> Enum.map(&issue_for(&1, issue_meta))
    else
      []
    end
  end

  defp banned_entries(source_file, params) do
    params
    |> Params.get(:banned, __MODULE__)
    |> Enum.map(fn {module, function} ->
      {AstHelpers.resolve_aliases(source_file, [module]), function}
    end)
  end

  defp violations(clause, banned_entries) do
    clause
    |> Macro.prewalk([], &collect_violations(&1, &2, banned_entries))
    |> elem(1)
    |> Enum.reverse()
  end

  # A quote block builds AST at compile time — a Task.async(...) inside it is
  # generated code, not a call this callback actually makes. Prune the subtree.
  defp collect_violations({:quote, _meta, _args}, calls, _banned_entries), do: {nil, calls}

  defp collect_violations(
         {{:., _, [{:__aliases__, alias_meta, module}, function]}, _meta, args} = ast,
         calls,
         banned_entries
       )
       when is_list(args) do
    if banned?(module, function, banned_entries) do
      {ast, [call(module, function, alias_meta) | calls]}
    else
      {ast, calls}
    end
  end

  defp collect_violations(ast, calls, _banned_entries), do: {ast, calls}

  defp banned?(module, function, banned_entries) do
    Enum.any?(banned_entries, fn {paths, banned_function} ->
      module in paths and function === banned_function
    end)
  end

  defp call(module, function, meta) do
    %{
      trigger: "#{Enum.join(module, ".")}.#{function}",
      line_no: meta[:line],
      column: meta[:column]
    }
  end

  defp issue_for(call, issue_meta) do
    format_issue(issue_meta,
      message:
        "#{call.trigger} found in a GenServer/GenStage callback — it links the task to this process, so a crash takes the server down with it. Use Task.Supervisor.async_nolink/2 (with a Task.Supervisor already in your app's supervision tree) and handle {ref, result} and {:DOWN, ...} in handle_info/2.",
      trigger: call.trigger,
      line_no: call.line_no,
      column: call.column
    )
  end
end
