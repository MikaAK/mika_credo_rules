defmodule MikaCredoRules.NoSelfSendZeroDelay do
  use Credo.Check,
    base_priority: :normal,
    category: :refactor,
    param_defaults: [
      also_flag_send_self_in_init: true,
      behaviour_modules: [GenServer, GenStage],
      excluded_paths: []
    ],
    explanations: [
      params: [
        also_flag_send_self_in_init: """
        When `true` (the default), also flag `send(self(), _)` inside `init/1` of a
        module using one of `:behaviour_modules` — the zero-delay anti-pattern
        without even a delay argument to give it away.
        """,
        behaviour_modules: """
        Modules whose `use` marks a file as worth scanning for the `init/1` half of
        this check. Alias-aware via `MikaCredoRules.AstHelpers.resolve_aliases/2`.
        """,
        excluded_paths: """
        Path fragments naming files to skip entirely, matched on segment boundaries.
        """
      ]
    ]

  alias MikaCredoRules.AstHelpers
  alias MikaCredoRules.SourceFilter

  @moduledoc """
  `Process.send_after(self(), _, 0)` and `send(self(), _)` in `init/1` schedule a
  message to yourself with no delay so a later callback can do the real work —
  that is exactly what `{:continue, term}` is for.

  `GenServerRequiresHandleContinue` allow-lists `Process.send_after` in `init/1`
  by default, because a *nonzero* delay is a genuine self-scheduled timer. A
  *zero*-delay one is not a timer at all — nothing about it needs the message
  queue round-trip, it is `{:continue, term}` wearing a disguise. This check
  closes that gap.

      # BAD — indirection for exactly what a continue does directly
      def init(opts) do
        Process.send_after(self(), :load, 0)
        {:ok, opts}
      end

      def handle_info(:load, state), do: {:noreply, do_load(state)}

      # GOOD
      def init(opts), do: {:ok, opts, {:continue, :load}}
      def handle_continue(:load, state), do: {:noreply, do_load(state)}

  `send(self(), _)` in `init/1` is the same anti-pattern without even the delay
  argument to give it away:

      # BAD
      def init(opts) do
        send(self(), :load)
        {:ok, opts}
      end

      # GOOD
      def init(opts), do: {:ok, opts, {:continue, :load}}

  `Process.send_after(self(), _, 0)` is flagged everywhere it appears, regardless
  of whether the file uses GenServer — a zero-delay self-timer is the same
  anti-pattern wherever it lives. `send(self(), _)` is far too common a
  message-passing primitive to flag everywhere, so that half is scoped to
  `init/1` of a module using one of `:behaviour_modules` (default `GenServer`,
  `GenStage`), behind `:also_flag_send_self_in_init` — inside `init/1`
  specifically, sending yourself a message before you have even finished
  starting is unambiguous.

  ## Limitations

    * Only the literal delay `0` is flagged for `Process.send_after/3,4` — a
      delay computed from a variable or expression that evaluates to `0` at
      runtime is invisible to this check.
    * `:erlang.send_after/3,4` is invisible to this check — its argument order
      (`time, dest, msg`) differs from `Process.send_after/3,4`'s
      (`dest, msg, time`), so a shared literal-`0` matcher cannot cover both
      without risking a false positive on the wrong position.
    * Only unqualified `send/2` is matched for the `init/1` half — a qualified
      `Kernel.send(self(), _)` is invisible to this check.
    * `self()` must be written with parentheses; other equivalent spellings
      (a variable bound to `self()` earlier) are invisible to this check.
    * `send(self(), _)` inside an anonymous `fn` is never flagged, even inside
      `init/1` — the fn's `self()` resolves to whatever process eventually
      calls it, not necessarily the GenServer.
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

      zero_delay_issues(source_file, issue_meta) ++
        send_in_init_issues(source_file, params, issue_meta)
    end
  end

  defp zero_delay_issues(source_file, issue_meta) do
    process_paths = AstHelpers.resolve_aliases(source_file, [Process])

    source_file
    |> Credo.Code.prewalk(&collect_zero_delay_sends(&1, &2, process_paths), [])
    |> Enum.reverse()
    |> Enum.map(&zero_delay_issue_for(&1, issue_meta))
  end

  # A piped self() |> Process.send_after(msg, delay) drops self() out of the
  # dot-call's own args (it becomes the pipe's left-hand side instead), so it
  # is matched here, at the pipe node, before the standalone clause below ever
  # sees the inner call.
  defp collect_zero_delay_sends(
         {:|>, _pipe_meta,
          [lhs, {{:., _, [{:__aliases__, alias_meta, module}, :send_after]}, _meta, args}]} =
           ast,
         calls,
         process_paths
       )
       when is_list(args) do
    if module in process_paths and self_call?(lhs) and piped_zero_delay?(args) do
      {ast, [zero_delay_call(module, alias_meta) | calls]}
    else
      {ast, calls}
    end
  end

  defp collect_zero_delay_sends(
         {{:., _, [{:__aliases__, alias_meta, module}, :send_after]}, _meta, args} = ast,
         calls,
         process_paths
       )
       when is_list(args) do
    if module in process_paths and zero_delay_self_send?(args) do
      {ast, [zero_delay_call(module, alias_meta) | calls]}
    else
      {ast, calls}
    end
  end

  defp collect_zero_delay_sends(ast, calls, _process_paths), do: {ast, calls}

  defp zero_delay_self_send?(args) when length(args) in [3, 4] do
    self_call?(Enum.at(args, 0)) and Enum.at(args, 2) === 0
  end

  defp zero_delay_self_send?(_args), do: false

  defp piped_zero_delay?(args) when length(args) in [2, 3], do: Enum.at(args, 1) === 0
  defp piped_zero_delay?(_args), do: false

  defp self_call?({:self, _, []}), do: true
  defp self_call?(_ast), do: false

  defp zero_delay_call(module, alias_meta) do
    %{
      trigger: "#{Enum.join(module, ".")}.send_after",
      line_no: alias_meta[:line],
      column: alias_meta[:column]
    }
  end

  defp zero_delay_issue_for(call, issue_meta) do
    format_issue(issue_meta,
      message:
        "Process.send_after found with a zero delay — that is {:continue, term} wearing a disguise. Return {:ok, state, {:continue, term}} from init/1 (or the appropriate callback) and do the work in handle_continue/2.",
      trigger: call.trigger,
      line_no: call.line_no,
      column: call.column
    )
  end

  defp send_in_init_issues(source_file, params, issue_meta) do
    behaviour_modules = Params.get(params, :behaviour_modules, __MODULE__)

    if Params.get(params, :also_flag_send_self_in_init, __MODULE__) and
         AstHelpers.uses_module?(source_file, behaviour_modules) do
      source_file
      |> AstHelpers.callback_clauses([:init])
      |> Enum.flat_map(&send_self_calls/1)
      |> Enum.map(&send_in_init_issue_for(&1, issue_meta))
    else
      []
    end
  end

  defp send_self_calls(clause) do
    clause
    |> Macro.prewalk([], &collect_send_self/2)
    |> elem(1)
    |> Enum.reverse()
  end

  # An anonymous fn stored in state runs whenever and wherever it is later
  # invoked, not necessarily inside init/1 — self() inside it resolves at
  # call time, in whatever process calls the fn. Prune the subtree.
  defp collect_send_self({:fn, _meta, _clauses}, calls), do: {nil, calls}

  defp collect_send_self({:send, meta, [destination, _message]} = ast, calls) do
    if self_call?(destination) do
      {ast, [%{line_no: meta[:line], column: meta[:column]} | calls]}
    else
      {ast, calls}
    end
  end

  defp collect_send_self(ast, calls), do: {ast, calls}

  defp send_in_init_issue_for(call, issue_meta) do
    format_issue(issue_meta,
      message:
        "send(self(), _) found in init/1 — that is {:continue, term} wearing a disguise, without even a delay to give it away. Return {:ok, state, {:continue, term}} and do the work in handle_continue/2.",
      trigger: "send",
      line_no: call.line_no,
      column: call.column
    )
  end
end
