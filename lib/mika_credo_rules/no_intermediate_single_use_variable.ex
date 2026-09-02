defmodule MikaCredoRules.NoIntermediateSingleUseVariable do
  use Credo.Check,
    base_priority: :low,
    category: :refactor,
    param_defaults: [max_inline_length: 60],
    explanations: [
      params: [
        max_inline_length: """
        Exclusive upper bound (via `Macro.to_string/1`) on a right-hand side
        call or pipe chain's textual length — inlining is only worth it
        below this length.

        Defaults to `60` — at or above that length, moving the call into the
        next expression would make that line harder to read than the two
        lines it replaces, so the check stays silent.
        """
      ]
    ]

  alias MikaCredoRules.AstHelpers

  @moduledoc """
  A variable bound once and used exactly once, immediately after, adds a name
  with no payoff — inline the right-hand side into the statement that
  consumes it.

      # BAD — `provider` is bound once and used once, immediately after
      def config_provider(opts) do
        provider = Keyword.get(opts, :provider, :ses)
        case provider do
          :ses -> MyApp.Mailer.SES
          :smtp -> MyApp.Mailer.SMTP
        end
      end

      # GOOD — the call moves into the `case` subject
      def config_provider(opts) do
        case Keyword.get(opts, :provider, :ses) do
          :ses -> MyApp.Mailer.SES
          :smtp -> MyApp.Mailer.SMTP
        end
      end

  This is DELIBERATELY narrow, to keep false positives near zero. ALL of the
  following must hold for the binding statement:

  the right-hand side is call-shaped — a function call, a pipe chain, an
  operator expression, a module attribute, or dot-field access all qualify —
  never a literal (including sigils, binaries, unary-minus/-plus numbers
  like `-1`, and an operator expression whose operands are themselves all
  literals, like `1..10` or `1 + 2`), an `if`/`case`/`with`/`cond`, or a
  capture; the very next statement in the same block consumes the variable
  as its SOLE use — a `case` subject, the one argument of a call (`f(var)`,
  `Mod.f(var)`, `fun.(var)`), or the source piped into a chain whose first
  stage is a zero-arg call (`var |> f()`, `var |> f() |> g(3)`); the
  variable appears nowhere else in the
  enclosing function clause — bound once, used once; and the right-hand
  side's own text stays under `:max_inline_length` characters (below the
  default of 60), so inlining does not make the next line harder to read
  than the two lines it replaces.

  A variable used more than once is untouched — this check nudges, it does
  not chase every intermediate variable:

      # GOOD — `provider` is used again after the call, nothing to inline
      def config_provider(opts) do
        provider = Keyword.get(opts, :provider, :ses)
        log_provider(provider)
        provider
      end

  ## Limitations

  Only the function clause's own top-level block is scanned — a bind-and-use
  pair nested inside an `if`/`case`/`cond` branch is not chased. An
  underscore-prefixed variable (`_provider`) is never flagged, since the
  leading underscore already marks the binding as deliberately named for its
  own sake. For a pipe consumer whose right-hand side is a call WITH
  arguments (`var = f(a); var |> g()`), following the advice moves that call
  to the head of the chain, which `Credo.Check.Refactor.PipeChainStart`, if
  enabled, will separately ask to be extracted back out — this check does
  not account for that other check's rule. This is a readability nudge
  (`base_priority: :low`), not a correctness rule — and that low priority
  means a plain `mix credo` run never reports it at all; `mix credo
  --strict` (or a `min_priority` override) is required to see its issues.
  """
  @explanation [check: @moduledoc]

  @non_call_heads [
    :case,
    :cond,
    :if,
    :unless,
    :with,
    :fn,
    :receive,
    :try,
    :quote,
    :for,
    :&,
    :%{},
    :%,
    :{},
    :super,
    :__block__,
    :__aliases__,
    :<<>>
  ]

  @operator_heads [
    :+,
    :-,
    :*,
    :/,
    :++,
    :--,
    :<>,
    :..,
    :"..//",
    :==,
    :!=,
    :===,
    :!==,
    :<,
    :>,
    :<=,
    :>=,
    :and,
    :or,
    :not,
    :&&,
    :||,
    :!,
    :in
  ]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    max_inline_length = Params.get(params, :max_inline_length, __MODULE__)

    source_file
    |> Credo.Code.prewalk(&traverse(&1, &2, max_inline_length))
    |> Enum.map(&issue_for(&1, issue_meta))
  end

  defp traverse({def_kind, _meta, [_head, kw]} = ast, matches, max_inline_length)
       when def_kind in [:def, :defp, :defmacro, :defmacrop] and is_list(kw) do
    {ast, collect_matches(ast, kw, matches, max_inline_length)}
  end

  defp traverse(ast, matches, _max_inline_length), do: {ast, matches}

  defp collect_matches(clause_ast, kw, matches, max_inline_length) do
    case Keyword.get(kw, :do) do
      nil ->
        matches

      body ->
        body
        |> AstHelpers.block_statements()
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.reduce(matches, &collect_pair(&1, &2, clause_ast, max_inline_length))
    end
  end

  defp collect_pair([statement, next], matches, clause_ast, max_inline_length) do
    case bind_and_pass_once(statement, next, clause_ast, max_inline_length) do
      nil -> matches
      match -> [match | matches]
    end
  end

  defp bind_and_pass_once(
         {:=, _meta, [{name, var_meta, context}, rhs]},
         next,
         clause_ast,
         max_inline_length
       )
       when is_atom(name) and is_atom(context) do
    with true <- intermediate_name?(name),
         true <- call_or_pipe?(rhs),
         rhs_text = Macro.to_string(rhs),
         true <- String.length(rhs_text) < max_inline_length,
         true <- sole_use?(next, name),
         2 <- variable_occurrences(clause_ast, name) do
      %{
        line_no: var_meta[:line],
        column: var_meta[:column],
        trigger: Atom.to_string(name),
        rhs_text: rhs_text
      }
    else
      _ -> nil
    end
  end

  defp bind_and_pass_once(_statement, _next, _clause_ast, _max_inline_length), do: nil

  defp intermediate_name?(:_), do: false
  defp intermediate_name?(name), do: not String.starts_with?(Atom.to_string(name), "_")

  defp call_or_pipe?({:|>, _, [_lhs, _rhs]}), do: true

  defp call_or_pipe?({{:., _, [_, _]}, _, args}) when is_list(args), do: true

  defp call_or_pipe?({{:., _, [_fun]}, _, args}) when is_list(args), do: true

  defp call_or_pipe?({head, _, [arg]}) when head in [:-, :+] and is_number(arg), do: false

  defp call_or_pipe?({head, _, args})
       when is_atom(head) and is_list(args) and head not in @non_call_heads,
       do: not sigil_head?(head) and not literal_operator?(head, args)

  defp call_or_pipe?(_rhs), do: false

  defp sigil_head?(head), do: head |> Atom.to_string() |> String.starts_with?("sigil_")

  defp literal_operator?(head, args),
    do: head in @operator_heads and Enum.all?(args, &literal_value?/1)

  defp literal_value?(value) when is_number(value) or is_atom(value) or is_binary(value), do: true
  defp literal_value?(value) when is_list(value), do: Enum.all?(value, &literal_value?/1)
  defp literal_value?({key, value}), do: literal_value?(key) and literal_value?(value)

  defp literal_value?({head, _meta, args}) when head in @operator_heads and is_list(args),
    do: Enum.all?(args, &literal_value?/1)

  defp literal_value?({:%{}, _meta, pairs}), do: Enum.all?(pairs, &literal_value?/1)
  defp literal_value?({:<<>>, _meta, segments}), do: Enum.all?(segments, &literal_value?/1)
  defp literal_value?({head, _meta, _args}) when is_atom(head), do: sigil_head?(head)

  defp literal_value?(_value), do: false

  defp sole_use?({:case, _, [{name, _, context}, [do: _clauses]]}, name) when is_atom(context),
    do: true

  defp sole_use?({{:., _, [_, _]} = call_head, _, [{name, _, context}]}, name)
       when is_atom(context) and is_tuple(call_head),
       do: true

  defp sole_use?({{:., _, [_fun]} = call_head, _, [{name, _, context}]}, name)
       when is_atom(context) and is_tuple(call_head),
       do: true

  defp sole_use?({call_head, _, [{name, _, context}]}, name)
       when is_atom(context) and is_atom(call_head) and call_head not in @non_call_heads,
       do: true

  defp sole_use?({:|>, _, _} = pipe, name) do
    case pipe_chain(pipe) do
      [{^name, _, context}, first_stage | _rest] when is_atom(context) ->
        zero_arg_call?(first_stage)

      _chain ->
        false
    end
  end

  defp sole_use?(_next, _name), do: false

  defp pipe_chain(ast), do: pipe_chain(ast, [])
  defp pipe_chain({:|>, _, [lhs, rhs]}, acc), do: pipe_chain(lhs, [rhs | acc])
  defp pipe_chain(ast, acc), do: [ast | acc]

  defp zero_arg_call?({{:., _, [_, _]}, _, []}), do: true

  defp zero_arg_call?({{:., _, [_fun]}, _, []}), do: true

  defp zero_arg_call?({call_head, _, []})
       when is_atom(call_head) and call_head not in @non_call_heads,
       do: true

  defp zero_arg_call?(_stage), do: false

  defp variable_occurrences(clause_ast, name) do
    {_ast, count} =
      Macro.prewalk(clause_ast, 0, fn
        {^name, _, context} = node, count when is_atom(context) -> {node, count + 1}
        node, count -> {node, count}
      end)

    count
  end

  defp issue_for(match, issue_meta) do
    format_issue(issue_meta,
      message: "bind-and-pass-once found — inline `#{match.rhs_text}` into the next expression",
      trigger: match.trigger,
      line_no: match.line_no,
      column: match.column
    )
  end
end
