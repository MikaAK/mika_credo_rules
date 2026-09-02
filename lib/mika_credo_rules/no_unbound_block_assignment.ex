defmodule MikaCredoRules.NoUnboundBlockAssignment do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [excluded_paths: []],
    explanations: [
      params: [
        excluded_paths: """
        A list of path fragments exempt from the check, matched at a
        path-segment boundary.

        Defaults to `[]` — the classic `socket = assign(...)` bug is exactly as
        real in a test as anywhere else, so nothing is exempt by default.
        """
      ]
    ]

  alias MikaCredoRules.AstHelpers
  alias MikaCredoRules.SourceFilter

  @moduledoc """
  An `if`/`case`/`cond`/`unless` used as a STATEMENT must not end a branch in a
  bare assignment — the binding is scoped to that branch and never escapes the
  block, so the assignment is silently lost. This is the classic
  `socket = assign(...)` LiveView bug.

      # BAD — `socket` inside the `if` never reaches the return value
      def handle(socket, val) do
        if connected?(socket) do
          socket = assign(socket, :val, val)
        end

        {:noreply, socket}
      end

      # GOOD — bind the `if`'s own result instead
      def handle(socket, val) do
        socket = if connected?(socket), do: assign(socket, :val, val), else: socket
        {:noreply, socket}
      end

  `case` and `cond` branches, and `unless`, are checked the same way — any
  branch whose body ends in a bare `variable = ...` is flagged when the
  surrounding `case`/`cond`/`unless` is itself in statement position:

      # BAD — a case branch ending in a bare assignment
      def handle(socket, msg) do
        case msg do
          :connect -> socket = assign(socket, :connected, true)
          _ -> :ok
        end

        socket
      end

  A construct is only "in statement position" when it is an element of a block
  that is not the block's own last expression — the same rule
  `NoForWithDiscardedResult` uses for `for`. When it IS the last expression
  (its value becomes the block's own return value), the lost binding is moot,
  because the caller receives the branch's value directly, not the shadowed
  variable — but that only holds if the enclosing block's own value is itself
  used. Being the last expression of a NESTED if/case/cond/unless is not
  enough: if the outer construct is itself in statement position, its value
  (and so the inner construct's value) is discarded too, so the inner
  construct's own tail assignment is chased through the same way, however
  deep the nesting goes:

      # BAD — the inner `if`'s own last expression is discarded too
      def handle(socket, val) do
        if connected?(socket) do
          if ready?(socket) do
            socket = assign(socket, :val, val)
          end
        end

        {:noreply, socket}
      end

      # GOOD — the `if` is the function's own return value
      def handle(socket, val) do
        if connected?(socket) do
          assign(socket, :val, val)
        end
      end

  Only an assignment in TAIL position of a branch body is inspected — an
  earlier assignment that the branch itself goes on to use, entirely within
  the branch, is not what this check flags:

      # GOOD — `computed` is a fresh variable, fully consumed inside the branch
      def handle(socket, val) do
        if connected?(socket) do
          computed = assign(socket, :val, val)
          Logger.info("assigned \#{inspect(computed)}")
        end

        :ok
      end

  ## Limitations

  Only a bare single-variable left-hand side is recognised as "the assigned
  variable" — a destructuring tail assignment (`{a, b} = compute()`) is not
  flagged, assigning to the wildcard `_` OR any `_`-prefixed name (`_socket`)
  is never flagged (the compiler suppresses its own unused-variable warning
  for exactly these names, so it is an explicit discard, not a lost binding),
  and `var!(socket) = ...` (unquoted assignment inside a macro body) is not
  flagged either — its left-hand side is a `var!/1` call, not a bare variable
  node.

  A branch's tail statement is chased through nested `if`/`case`/`cond`/
  `unless` to any depth, since a discarded value stays discarded no matter
  how many of those constructs it passes through on the way down. Other
  nested constructs are not chased: an assignment buried inside a `with`/
  `try`/`receive` whose OWN last expression is the bare assignment is not
  flagged — only `if`/`case`/`cond`/`unless` tails count. Only the bare macro
  spelling is recognised — a fully-qualified call (`Kernel.if/2`,
  `Kernel.case/2`) is not.
  """
  @explanation [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    if excluded_file?(source_file.filename, params) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)

      source_file
      |> Credo.Code.prewalk(&traverse/2)
      |> Enum.map(&issue_for(&1, issue_meta))
    end
  end

  defp excluded_file?(filename, params) do
    SourceFilter.matches_fragment?(filename, Params.get(params, :excluded_paths, __MODULE__))
  end

  defp traverse({:__block__, _meta, exprs} = ast, assignments) when is_list(exprs) do
    {ast, collect_unbound_assignments(exprs, assignments)}
  end

  defp traverse(ast, assignments), do: {ast, assignments}

  defp collect_unbound_assignments(exprs, assignments) do
    exprs
    |> Enum.drop(-1)
    |> Enum.flat_map(&branch_assignments/1)
    |> Kernel.++(assignments)
  end

  defp branch_assignments({keyword, _meta, [_condition, clauses]})
       when keyword in [:if, :unless] and is_list(clauses) do
    clauses
    |> Keyword.take([:do, :else])
    |> Enum.flat_map(fn {_branch, body} -> tail_assignment(body) end)
  end

  defp branch_assignments({:case, _meta, [_value, [do: clauses]]}) when is_list(clauses) do
    Enum.flat_map(clauses, &clause_assignment/1)
  end

  defp branch_assignments({:cond, _meta, [[do: clauses]]}) when is_list(clauses) do
    Enum.flat_map(clauses, &clause_assignment/1)
  end

  defp branch_assignments(_expr), do: []

  # The `->` head is a pattern, not a branch body — only the body (second
  # element) is ever inspected here.
  defp clause_assignment({:->, _meta, [_head, body]}), do: tail_assignment(body)

  defp tail_assignment(body) do
    body
    |> AstHelpers.block_statements()
    |> List.last()
    |> tail_statement_assignments()
  end

  # The branch's own tail statement is a bare assignment — flag it directly.
  # Otherwise, when the tail statement is ITSELF an if/case/cond/unless, its
  # value is exactly as discarded as the branch that contains it (however
  # deep the nesting goes), so its own branches are chased the same way.
  defp tail_statement_assignments(statement) do
    case assignment_match(statement) do
      nil -> branch_assignments(statement)
      assignment -> [assignment]
    end
  end

  defp assignment_match({:=, _meta, [{name, var_meta, context}, _rhs]})
       when is_atom(name) and is_atom(context) do
    if discarded_name?(name) do
      nil
    else
      %{variable: Atom.to_string(name), line_no: var_meta[:line], column: var_meta[:column]}
    end
  end

  defp assignment_match(_statement), do: nil

  # Matches the wildcard `_` itself and every `_`-prefixed name (`_socket`) —
  # the compiler suppresses its own unused-variable warning for exactly these
  # names, so the developer has already marked the binding as an explicit
  # discard. Same rule as NoSingleLetterVariables' underscore exemption.
  defp discarded_name?(name), do: String.starts_with?(Atom.to_string(name), "_")

  defp issue_for(assignment, issue_meta) do
    format_issue(issue_meta,
      message:
        "#{assignment.variable} found — assignment discarded when the branch ends; bind the if/case/cond/unless block's own result instead",
      trigger: assignment.variable,
      line_no: assignment.line_no,
      column: assignment.column
    )
  end
end
