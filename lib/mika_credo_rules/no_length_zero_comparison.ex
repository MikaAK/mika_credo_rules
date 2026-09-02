defmodule MikaCredoRules.NoLengthZeroComparison do
  use Credo.Check,
    base_priority: :high,
    category: :readability,
    param_defaults: [
      local_functions: [:length],
      remote_functions: [{Enum, :count}]
    ],
    explanations: [
      params: [
        local_functions: """
        Bare/imported 1-arity function names that count as a length
        computation when compared against the literal `0` or `1`. Defaults
        to `[:length]`.
        """,
        remote_functions: """
        `{Module, function}` pairs naming a remote 1-arity call that counts
        as a length computation. Alias-aware — an `alias`, an `as:` rename,
        and the fully-qualified `Elixir.`-prefixed spelling all resolve to
        the same module. `Module` must be an Elixir module (e.g. `Enum`) —
        an erlang module atom (e.g. `:maps`) raises `ArgumentError` and
        aborts the run. Defaults to `[{Enum, :count}]`.
        """
      ]
    ]

  alias MikaCredoRules.AstHelpers

  @moduledoc """
  Comparing `length/1` (or `Enum.count/1`) against `0` must use
  `Enum.empty?/1` instead.

  `length(list)` walks the entire list — `O(n)` — just to throw the count
  away and keep only whether it was zero. `Enum.empty?/1` answers the same
  question in `O(1)`.

      # BAD — length(list) walks the whole list just to check emptiness
      defmodule MyApp.Worker do
        def none?(list), do: length(list) === 0
      end

      # GOOD — Enum.empty?/1 is O(1) and says what it means
      defmodule MyApp.Worker do
        def none?(list), do: Enum.empty?(list)
      end

  `0` on either side is caught, and every equality operator counts:

      length(list) === 0    # caught
      0 === length(list)    # caught
      length(list) == 0     # caught
      length(list) !== 0    # caught (means "not empty")
      length(list) != 0     # caught (means "not empty")

  `length(list) > 0` and `length(list) >= 1` mean "the list is not empty" —
  the same fact `Enum.empty?/1` answers, negated:

      # BAD
      defmodule MyApp.Worker do
        def some?(list), do: length(list) > 0
      end

      # GOOD
      defmodule MyApp.Worker do
        def some?(list), do: not Enum.empty?(list)
      end

  `Enum.count/1` (no predicate) is caught the same way as `length/1`:

      # BAD
      defmodule MyApp.Worker do
        def none?(collection), do: Enum.count(collection) === 0
      end

      # GOOD
      defmodule MyApp.Worker do
        def none?(collection), do: Enum.empty?(collection)
      end

  Guard clauses are caught too, but `Enum.empty?/1` is not allowed in a
  guard — the guard-safe rewrite is a pattern match against `[]` instead,
  and the message says so:

      # BAD
      defmodule MyApp.Worker do
        def process(list) when length(list) > 0, do: list
      end

      # GOOD
      defmodule MyApp.Worker do
        def process(list) when list !== [], do: list
      end

  ## Limitations

  `Credo.Check.Warning.ExpensiveEmptyEnumCheck` (`EX5003`, a stock Credo
  check that runs by default) is a strict superset of the operators this
  check matches — its operator list is `==`, `!=`, `===`, `!==`, `>`, `<`,
  `>=`, `<=`, over both `length/1` and `Enum.count/*` — so every
  `length(x) === 0` this check flags is ALSO flagged by the stock check, and
  a consumer that registers this check sees two issues on the same line.
  What this check adds: alias-awareness (`alias Enum, as: E; E.count(x) ===
  0` fires here — the stock check's pattern hardcodes the literal `Enum`
  segment and misses the rename — while `alias MyApp.Vendor.Enum;
  Enum.count(x) === 0` correctly stays silent here and is a measured false
  positive on the stock check, which does not resolve aliases at all), a
  `column:` on every issue (so two comparisons on one line get distinct
  locations; the stock check threads only `line_no`), and configurable
  `local_functions`/`remote_functions` (the stock check's targets are
  fixed). What it drops relative to the stock check: `<`/`<=` in any form
  and `Enum.count/2` (see below). Consumers who don't need the extras can
  disable the stock check instead:

      checks: %{
        enabled: [{MikaCredoRules.NoLengthZeroComparison, []}],
        disabled: [{Credo.Check.Warning.ExpensiveEmptyEnumCheck, []}]   # superseded, minus <, <=, Enum.count/2
      }

  Disabling it also drops its `<`/`<=` coverage and its `Enum.count/2`
  advice (`not Enum.any?/2`) — only disable it if that coverage isn't
  otherwise wanted.

  Only the comparison against the literal `0`/`1` is understood — a
  comparison against anything else is left alone, since it is not asking
  an emptiness question: `length(list) === 3`, or `length(list) === len`
  where `len` is a variable.

  `Enum.count/2` (with a predicate) has no `Enum.empty?/1` equivalent and is
  never flagged, regardless of what it is compared to — the predicate form
  answers a different question than plain emptiness.

  Only `local_functions`/`remote_functions` calls are recognised — a call
  to an unlisted function under the same name, such as `String.length/1`,
  is a different function and is silently ignored by default (add it to
  `:remote_functions` to cover it). The reverse also holds: `local_functions`
  matches on the bare call name alone, not on which function it resolves to
  — `import Kernel, except: [length: 1]` followed by `import MyApp.Sizes,
  only: [length: 1]` makes `length(ring) === 0` fire with the
  `Enum.empty?/1` / `=== []` advice even though `MyApp.Sizes.length/1` may
  not return a list-like count at all.

  Only `>`/`>=` are matched, and only with length on the left:
  `length(x) > 0` / `length(x) >= 1`. `0 < length(x)`, `1 <= length(x)`,
  `length(x) < 1`, and `length(x) <= 0` all mean the same "empty"/"not
  empty" question but are not matched here, regardless of which side
  `length(x)` is on — `Credo.Check.Warning.ExpensiveEmptyEnumCheck` already
  covers all four forms (see above), so this is not an uncovered gap for a
  repo running the stock check too.

  A piped call (`list |> Enum.count() === 0`) is a false negative — the
  piped argument is not part of the call's own argument list in the raw
  AST, so it never matches the 1-arity shape this check looks for.

  A single-segment `remote_functions` module (e.g. `Enum`) can be shadowed
  by a `defmodule <Name>` of the same bare name anywhere in the file — but
  the deregistration is file-scoped, not lexical: it silences bare `Enum`
  for the ENTIRE file, including code written above the nested `defmodule`,
  not just from its definition onward.

  The guard-safe alternative (`=== []`) is only offered when the match came
  from `local_functions` — a `remote_functions` match such as `Enum.count/1`
  can never appear in a guard at all, and is not equivalent to `=== []` for
  every collection type, so that parenthetical is dropped from the message.
  """
  @explanation [check: @moduledoc]

  @equality_operators [:===, :==, :!==, :!=]
  @empty_operators [:===, :==]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    context = build_context(source_file, params)

    source_file
    |> Credo.Code.prewalk(&traverse(&1, &2, context))
    |> Enum.map(&issue_for(&1, issue_meta))
  end

  defp build_context(source_file, params) do
    local_functions = Params.get(params, :local_functions, __MODULE__)
    remote_functions = Params.get(params, :remote_functions, __MODULE__)

    shadowable_defmodule_names =
      source_file
      |> AstHelpers.defined_module_names()
      |> Enum.filter(&match?([_], &1))

    resolved_remote_functions =
      Enum.map(remote_functions, fn {module, function} ->
        resolved =
          AstHelpers.resolve_aliases(source_file, [module]) -- shadowable_defmodule_names

        {resolved, function}
      end)

    %{local_functions: local_functions, remote_functions: resolved_remote_functions}
  end

  defp traverse({operator, meta, [left, right]} = ast, issues, context)
       when operator in @equality_operators do
    case matched_length_arg(context, left, right, 0) do
      {:ok, arg, source} ->
        {ast, [violation(operator, 0, meaning(operator), arg, source, meta) | issues]}

      :error ->
        {ast, issues}
    end
  end

  defp traverse({:>, meta, [left, right]} = ast, issues, context) do
    case length_vs_literal(context, left, right, 0) do
      {:ok, arg, source} -> {ast, [violation(:>, 0, :not_empty, arg, source, meta) | issues]}
      :error -> {ast, issues}
    end
  end

  defp traverse({:>=, meta, [left, right]} = ast, issues, context) do
    case length_vs_literal(context, left, right, 1) do
      {:ok, arg, source} -> {ast, [violation(:>=, 1, :not_empty, arg, source, meta) | issues]}
      :error -> {ast, issues}
    end
  end

  defp traverse(ast, issues, _context), do: {ast, issues}

  defp meaning(operator) when operator in @empty_operators, do: :empty
  defp meaning(_operator), do: :not_empty

  # Both operand orders: the literal can sit on either side of an equality
  # comparison, so try the length-call on the left, then on the right.
  defp matched_length_arg(context, left, right, literal) do
    cond do
      literal?(right, literal) -> length_call_target(left, context)
      literal?(left, literal) -> length_call_target(right, context)
      true -> :error
    end
  end

  defp length_vs_literal(context, length_side, literal_side, literal) do
    if literal?(literal_side, literal) do
      length_call_target(length_side, context)
    else
      :error
    end
  end

  defp literal?(ast, value), do: ast === value

  defp length_call_target({function, _, [arg]}, context) when is_atom(function) do
    if function in context.local_functions, do: {:ok, arg, :local}, else: :error
  end

  defp length_call_target({{:., _, [receiver, function]}, _, [arg]}, context)
       when is_atom(function) do
    matches? =
      Enum.any?(context.remote_functions, fn {paths, wanted_function} ->
        function === wanted_function and AstHelpers.use_module?(receiver, paths)
      end)

    if matches?, do: {:ok, arg, :remote}, else: :error
  end

  defp length_call_target(_ast, _context), do: :error

  defp violation(operator, literal, meaning, arg, source, meta) do
    %{
      operator: operator,
      literal: literal,
      meaning: meaning,
      arg: arg,
      source: source,
      line_no: meta[:line],
      column: meta[:column]
    }
  end

  defp issue_for(violation, issue_meta) do
    trigger = to_string(violation.operator)

    format_issue(issue_meta,
      message:
        "#{trigger} #{violation.literal} found — " <>
          advice(violation.meaning, violation.arg, violation.source),
      trigger: trigger,
      line_no: violation.line_no,
      column: violation.column
    )
  end

  # The guard-safe alternative is only offered for a `local_functions` match
  # (e.g. `length/1`, itself a guard BIF). A `remote_functions` match (e.g.
  # `Enum.count/1`) can never appear in a guard at all, and `collection === []`
  # is not even equivalent to it for a map/MapSet/range subject.
  defp advice(:empty, arg, :local) do
    expression = Macro.to_string(arg)

    "use Enum.empty?(#{expression}) instead — or `#{expression} === []` in a guard, " <>
      "where Enum.empty?/1 is not allowed"
  end

  defp advice(:empty, arg, :remote) do
    "use Enum.empty?(#{Macro.to_string(arg)}) instead"
  end

  defp advice(:not_empty, arg, :local) do
    expression = Macro.to_string(arg)

    "use `not Enum.empty?(#{expression})` instead — or `#{expression} !== []` in a guard, " <>
      "where Enum.empty?/1 is not allowed"
  end

  defp advice(:not_empty, arg, :remote) do
    "use `not Enum.empty?(#{Macro.to_string(arg)})` instead"
  end
end
