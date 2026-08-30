defmodule MikaCredoRules.TaskAsyncStreamRequiresTimeout do
  use Credo.Check,
    base_priority: :normal,
    category: :warning,
    param_defaults: [
      functions: [
        {Task, :async_stream},
        {Task.Supervisor, :async_stream},
        {Task.Supervisor, :async_stream_nolink}
      ],
      excluded_paths: []
    ],
    explanations: [
      params: [
        functions: """
        `{module, function}` pairs whose trailing options list is checked for an
        explicit `:timeout`.
        """,
        excluded_paths: """
        Path fragments naming files to skip, matched on segment boundaries.
        """
      ]
    ]

  alias MikaCredoRules.AstHelpers
  alias MikaCredoRules.SourceFilter

  @moduledoc """
  `Task.async_stream/2,3` and `Task.Supervisor.async_stream/3,4` (and its
  `async_stream_nolink` sibling) default to a **5-second per-item** timeout when
  no `:timeout` option is given. One slow item then crashes the whole stream —
  pass `timeout:` explicitly, even when the value is `:infinity`.

      # BAD — silently uses the 5s default and kills long batches
      Task.async_stream(symbols, &process_one/1, max_concurrency: 5)

      # BAD — no options argument at all
      Task.async_stream(symbols, &process_one/1)

      # GOOD
      Task.async_stream(symbols, &process_one/1, max_concurrency: 5, timeout: 35_000)

  ## Limitations

  Only a LITERAL trailing options keyword list is inspected. Options built by a
  helper, held in a variable, or passed through (`Task.async_stream(items, fun,
  opts)`) are invisible to this check — an accepted false negative, not a bug:
  the check cannot know at compile time whether a runtime value carries
  `:timeout`, and guessing wrong in either direction is worse than staying
  silent. Both the 2-argument function form (`enumerable, fun`) and the
  module/function/args form (`enumerable, module, function, args`) are matched
  the same way — whichever positional argument is last is inspected.
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
      banned_entries = banned_entries(source_file, params)

      source_file
      |> Credo.Code.prewalk(&collect_calls(&1, &2, banned_entries), [])
      |> Enum.reverse()
      |> Enum.map(&issue_for(&1, issue_meta))
    end
  end

  defp banned_entries(source_file, params) do
    params
    |> Params.get(:functions, __MODULE__)
    |> Enum.map(fn {module, function} ->
      {AstHelpers.resolve_aliases(source_file, [module]), function}
    end)
  end

  defp collect_calls(
         {{:., _, [{:__aliases__, alias_meta, module}, function]}, _meta, args} = ast,
         calls,
         banned_entries
       )
       when is_list(args) and args !== [] do
    if banned?(module, function, banned_entries) and missing_timeout?(List.last(args)) do
      trigger = "#{Enum.join(module, ".")}.#{function}"
      call = %{trigger: trigger, line_no: alias_meta[:line], column: alias_meta[:column]}
      {ast, [call | calls]}
    else
      {ast, calls}
    end
  end

  defp collect_calls(ast, calls, _banned_entries), do: {ast, calls}

  defp banned?(module, function, banned_entries) do
    Enum.any?(banned_entries, fn {paths, banned_function} ->
      module in paths and function === banned_function
    end)
  end

  # A bare variable in the trailing position is assumed to be an opts list
  # built elsewhere — an accepted false negative, not a bug (see moduledoc).
  defp missing_timeout?({name, _meta, context}) when is_atom(name) and is_atom(context) do
    false
  end

  defp missing_timeout?(last_arg) when is_list(last_arg) do
    if Enum.all?(last_arg, &keyword_entry?/1) do
      not Enum.any?(last_arg, fn {key, _value} -> key === :timeout end)
    else
      true
    end
  end

  defp missing_timeout?(_last_arg), do: true

  defp keyword_entry?({key, _value}) when is_atom(key), do: true
  defp keyword_entry?(_entry), do: false

  defp issue_for(call, issue_meta) do
    format_issue(issue_meta,
      message:
        "#{call.trigger} found with no explicit :timeout — it defaults to a 5-second per-item timeout and one slow item crashes the whole stream. Pass timeout: ms or timeout: :infinity explicitly.",
      trigger: call.trigger,
      line_no: call.line_no,
      column: call.column
    )
  end
end
