defmodule MikaCredoRules.NoContinueFromLiveViewMount do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      excluded_paths: []
    ],
    explanations: [
      params: [
        excluded_paths: """
        A list of path fragments naming files this check skips. A fragment matches
        when the source file's path starts with it, ends with it, or contains it
        after a directory separator. Defaults to `[]`.
        """
      ]
    ]

  alias MikaCredoRules.SourceFilter

  @moduledoc """
  `mount/3` must not return `{:ok, socket, {:continue, term}}`.

  `{:continue, term}` is a `GenServer.init/1` return value — LiveView's `mount/3`
  does not implement that protocol. Returning it either does nothing (the third
  element is ignored) or crashes, depending on the LiveView version; either way it
  is not what the author meant by "load this after mount".

      # BAD — {:continue, _} is GenServer-only; mount/3 does not implement it
      def mount(_params, _session, socket), do: {:ok, socket, {:continue, :load}}

      # GOOD — gate the deferred load on connected?/1 and message yourself
      def mount(_params, _session, socket) do
        if connected?(socket), do: send(self(), :load)
        {:ok, socket}
      end

  Deferred loading in a LiveView is a message the process sends itself
  (`send(self(), :load)`, picked up by a `handle_info/2`) or `start_async/3`, gated
  on `connected?/1` so it only fires once the socket is live — see
  `LiveViewSubscribeRequiresConnected` for the same guard used on PubSub
  subscriptions.

  Only the clause's own **last expression** is inspected — a continue tuple
  produced inside a `case`/`cond`/`if` branch and not literally the trailing
  expression of the `def` body is not statically the return value and is not
  flagged. Every `def mount/3` clause in the file is checked independently; a
  `mount/2` (not a LiveView callback — GenServer's is `init/1`) is left alone
  regardless of what it returns.

  ## Cross-reference

  This is the mirror image of `GenServerRequiresHandleContinue`, which
  *requires* `{:continue, term}` from a GenServer's `init/1`. Same shape, opposite
  callback, opposite advice — don't "fix" a flagged `mount/3` by reaching for that
  check's guidance.
  """
  @explanation [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    if excluded_path?(source_file.filename, excluded_paths(params)) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)

      source_file
      |> Credo.Code.prewalk(&collect_mount_clauses/2)
      |> Enum.map(&continue_return/1)
      |> Enum.filter(& &1)
      |> Enum.map(&issue_for(&1, issue_meta, source_file))
    end
  end

  defp excluded_paths(params), do: Params.get(params, :excluded_paths, __MODULE__)

  defp excluded_path?(filename, excluded_paths) do
    SourceFilter.matches_fragment?(filename, excluded_paths)
  end

  defp collect_mount_clauses({:def, _, [head, body]} = ast, clauses) when is_list(body) do
    if mount_head?(head), do: {ast, [ast | clauses]}, else: {ast, clauses}
  end

  defp collect_mount_clauses(ast, clauses), do: {ast, clauses}

  defp mount_head?({:when, _, [head | _guards]}), do: mount_head?(head)
  defp mount_head?({:mount, _, [_first, _second, _third]}), do: true
  defp mount_head?(_head), do: false

  defp continue_return({:def, _, [_head, body]}) do
    case Keyword.get(body, :do) do
      nil -> nil
      do_body -> do_body |> last_expression() |> continue_tuple_line()
    end
  end

  defp last_expression({:__block__, _, exprs}) when exprs !== [], do: List.last(exprs)
  defp last_expression(expr), do: expr

  defp continue_tuple_line({:{}, meta, [:ok, _socket, {:continue, _term}]}), do: meta[:line]
  defp continue_tuple_line(_expr), do: nil

  defp issue_for(line_no, issue_meta, source_file) do
    format_issue(issue_meta,
      message:
        ":continue found in mount/3 return — {:continue, term} is a GenServer.init/1 shape, not a LiveView one; gate the deferred load on connected?(socket) and send(self(), :load) instead",
      trigger: ":continue",
      line_no: line_no,
      column: continue_column(source_file, line_no)
    )
  end

  # Credo's own auto-column lookup (Credo.SourceFile.column/3) requires the
  # trigger to sit at a word boundary — whitespace, `(`, `)`, `,` — right
  # before it. `:continue` always sits right after the opening `{` of its
  # enclosing tuple, so that lookup returns nil and real `mix credo` output
  # renders the line with no column marker at all. Locate it ourselves with a
  # plain substring search instead of trusting AST metadata: the outer 3-tuple
  # node is the only one in `{:ok, socket, {:continue, term}}` carrying line
  # metadata (2-tuples carry none), and its own column points at the `{`, not
  # at `:continue` — passing it verbatim would mislabel the trigger.
  defp continue_column(source_file, line_no) do
    case source_file |> Credo.SourceFile.line_at(line_no) |> :binary.match(":continue") do
      {index, _length} -> index + 1
      :nomatch -> nil
    end
  end
end
