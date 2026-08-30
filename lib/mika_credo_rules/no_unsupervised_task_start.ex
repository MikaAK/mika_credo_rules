defmodule MikaCredoRules.NoUnsupervisedTaskStart do
  use Credo.Check,
    base_priority: :normal,
    category: :warning,
    param_defaults: [
      also_flag_start_link: false,
      excluded_paths: ["_test.exs", "test/"]
    ],
    explanations: [
      params: [
        also_flag_start_link: """
        When `true`, also flag `Task.start_link/1,3`. `false` by default — a linked
        task is a different, often intentional trade-off (the caller wants to go
        down with the task), not the silently-lost-crash bug this check guards
        against.
        """,
        excluded_paths: """
        Path fragments naming files to skip, matched on segment boundaries. A
        fire-and-forget task in a test fixture rarely needs a supervisor.
        """
      ]
    ]

  alias MikaCredoRules.AstHelpers
  alias MikaCredoRules.SourceFilter

  @moduledoc """
  `Task.start/1,3` must not be used — a crash inside the task is silently
  discarded. Nothing supervises it and nothing is linked to it, so the failure
  disappears with no log, no restart and no trace.

      # BAD — a crash here is silently lost
      def notify(payload), do: Task.start(fn -> send_webhook(payload) end)

      # GOOD — supervised; a crash is visible and can be handled
      def notify(payload) do
        Task.Supervisor.start_child(MyApp.TaskSupervisor, fn -> send_webhook(payload) end)
      end

  `Task.Supervisor.start_child/2` needs a `Task.Supervisor` already running in
  the app's supervision tree (`{Task.Supervisor, name: MyApp.TaskSupervisor}`).

  `Task.start_link/1,3` links the caller instead of losing the crash silently —
  a different, often intentional trade-off (the caller wants to go down with the
  task) — so it is left alone by default. Set `:also_flag_start_link` to also
  require it go through supervised start for consistent handling.

  Matched alias-aware via `MikaCredoRules.AstHelpers.resolve_aliases/2`, and
  scoped to lib code by default — `:excluded_paths` exempts test files.
  """
  @explanation [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    excluded_paths = Params.get(params, :excluded_paths, __MODULE__)

    if SourceFilter.matches_fragment?(source_file.filename, excluded_paths) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      banned_functions = banned_functions(params)
      task_paths = AstHelpers.resolve_aliases(source_file, [Task])

      source_file
      |> Credo.Code.prewalk(&collect_calls(&1, &2, task_paths, banned_functions), [])
      |> Enum.reverse()
      |> Enum.map(&issue_for(&1, issue_meta))
    end
  end

  defp banned_functions(params) do
    if Params.get(params, :also_flag_start_link, __MODULE__) do
      [:start, :start_link]
    else
      [:start]
    end
  end

  defp collect_calls(
         {{:., _, [{:__aliases__, alias_meta, module}, function]}, _meta, args} = ast,
         calls,
         task_paths,
         banned_functions
       )
       when is_list(args) do
    if module in task_paths and function in banned_functions do
      trigger = "#{Enum.join(module, ".")}.#{function}"
      call = %{trigger: trigger, line_no: alias_meta[:line], column: alias_meta[:column]}
      {ast, [call | calls]}
    else
      {ast, calls}
    end
  end

  defp collect_calls(ast, calls, _task_paths, _banned_functions), do: {ast, calls}

  defp issue_for(call, issue_meta) do
    format_issue(issue_meta,
      message:
        "#{call.trigger} found — a crash inside it is silently discarded. Use Task.Supervisor.start_child/2 (with a Task.Supervisor already in your app's supervision tree) so a crash is supervised and visible.",
      trigger: call.trigger,
      line_no: call.line_no,
      column: call.column
    )
  end
end
