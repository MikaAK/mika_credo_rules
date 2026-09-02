defmodule MikaCredoRules.NoPipeIntoControlFlow do
  use Credo.Check,
    base_priority: :high,
    category: :readability,
    param_defaults: [
      constructs: [:case, :if, :unless, :cond, :with]
    ],
    explanations: [
      params: [
        constructs: """
        A list of control-flow construct atoms that count as a violation when
        piped into directly.

        Defaults to `[:case, :if, :unless, :cond, :with]` — every branching
        construct that accepts a subject as its piped-in argument.
        """
      ]
    ]

  @moduledoc """
  Piping directly into `case`/`if`/`unless`/`cond`/`with` obscures the piped
  subject — bind it to a name first, then branch on the name.

  `|> case do` (and its `if`/`unless`/`cond`/`with` siblings) buries the value
  under branch on the far side of a pipe operator, so a reader has to hold the
  whole pipeline in their head before they can even see what is being matched.
  Binding it first names the subject and reads top to bottom.

      # BAD — the branched-on value never gets a name
      defmodule MyApp.Orders.Pricing do
        def apply_discount(order) do
          order
          |> calculate_total()
          |> case do
            total when total > 100 -> total * 0.9
            total -> total
          end
        end
      end

      # GOOD — bind the pipeline's result, then branch on the name
      defmodule MyApp.Orders.Pricing do
        def apply_discount(order) do
          total = order |> calculate_total()

          case total do
            total when total > 100 -> total * 0.9
            total -> total
          end
        end
      end

  `then/2` is the escape hatch for a genuine one-off transform that still
  wants to stay in the pipe:

      # GOOD — then/2 keeps the branch inside the pipe without hiding the subject
      order
      |> calculate_total()
      |> then(fn total -> if total > 100, do: total * 0.9, else: total end)

  Only a bare pipe into the construct itself is flagged. A construct nested
  inside a piped anonymous function is left alone — the pipe's actual target
  is the function that receives it (`Enum.map/2`, `then/2`, ...), not the
  construct:

      # GOOD — the pipe target is Enum.map/2, not case
      orders
      |> Enum.map(fn order ->
        case order do
          %{total: total} -> total
        end
      end)

  ## Limitations

  `cond` is kept in the default `constructs` list for parity with its
  siblings, but a real `|> cond do ... end` does not compile — `cond` only
  accepts a do-block, so piping into it produces a call to a nonexistent
  `cond/2`. Only the outermost pipe segment immediately preceding the
  construct is checked — a construct reached via a prefix-form `Kernel.|>/2`
  call evades the AST shape this check keys on.
  """
  @explanation [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    constructs = Params.get(params, :constructs, __MODULE__)

    source_file
    |> Credo.Code.prewalk(&traverse(&1, &2, constructs))
    |> Enum.map(&issue_for(&1, issue_meta))
  end

  defp traverse({:|>, meta, [_piped_value, {construct, _, _}]} = ast, pipe_calls, constructs)
       when is_atom(construct) do
    if construct in constructs do
      {ast, [pipe_call(construct, meta) | pipe_calls]}
    else
      {ast, pipe_calls}
    end
  end

  defp traverse(ast, pipe_calls, _constructs), do: {ast, pipe_calls}

  defp pipe_call(construct, meta) do
    %{construct: construct, line_no: meta[:line], column: meta[:column]}
  end

  defp issue_for(pipe_call, issue_meta) do
    label = "|> #{pipe_call.construct}"

    format_issue(issue_meta,
      message: "#{label} found — bind the piped value first, then branch on it",
      trigger: "|>",
      line_no: pipe_call.line_no,
      column: pipe_call.column
    )
  end
end
