defmodule MikaCredoRules.NoBlanketRescue do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      allowed_recovery_calls: [:reraise, :raise, Logger]
    ],
    explanations: [
      params: [
        allowed_recovery_calls: """
        A list of calls that count as handling a rescued exception. Module entries
        (e.g. `Logger`, `Sentry`) allow any call on that module; atom entries
        (e.g. `:reraise`, `:report_error`) allow local or imported calls with that
        name.

        Defaults to `[:reraise, :raise, Logger]`. Supplying the param replaces the
        default list, so include the defaults when adding to them.
        """
      ]
    ]

  @moduledoc """
  A rescue clause must not catch every exception only to swallow it.

  A blanket `rescue _ ->` or `rescue error ->` that neither reraises, raises, nor
  logs converts every crash — typos, match errors, genuine bugs — into a silent
  wrong value. Rescue the specific exceptions you can handle, and let everything
  else crash.

      # BAD — swallows every exception, bugs included
      def read_file(path) do
        File.read!(path)
      rescue
        _ -> :error
      end

      # GOOD — rescues only the exception it can handle
      def read_file(path) do
        File.read!(path)
      rescue
        error in File.Error -> {:error, error}
      end

  A blanket rescue is allowed when its body handles the exception it caught —
  reraising, raising a wrapping exception, or logging it:

      # GOOD — logs before returning an error value
      def read_file(path) do
        File.read!(path)
      rescue
        error ->
          Logger.error("\#{__MODULE__}: read failed, error: \#{inspect(error)}")
          {:error, error}
      end

  Both the explicit `try do ... rescue` block and the implicit `def ... rescue`
  form are checked.

  What counts as handling is configurable through `:allowed_recovery_calls`.
  Calls are matched by name, so a `Logger` renamed through an alias is not
  recognised.
  """
  @explanation [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    recovery_calls = build_recovery_calls(params)

    source_file
    |> Credo.Code.prewalk(&traverse(&1, &2, recovery_calls))
    |> Enum.map(&issue_for(&1, issue_meta))
  end

  defp build_recovery_calls(params) do
    {modules, functions} =
      params
      |> Params.get(:allowed_recovery_calls, __MODULE__)
      |> Enum.split_with(&module_entry?/1)

    %{modules: modules, functions: functions}
  end

  defp module_entry?(entry), do: entry |> Atom.to_string() |> String.starts_with?("Elixir.")

  # Both `try do ... rescue` and the implicit `def ... rescue` form carry their
  # clauses as a `rescue:` entry in the same block keyword list, so one match
  # covers both.
  defp traverse({:rescue, clauses} = ast, blanket_rescues, recovery_calls)
       when is_list(clauses) do
    {ast, collect_blanket_rescues(clauses, recovery_calls) ++ blanket_rescues}
  end

  defp traverse(ast, blanket_rescues, _recovery_calls), do: {ast, blanket_rescues}

  defp collect_blanket_rescues(clauses, recovery_calls) do
    for {:->, _meta, [[pattern], body]} <- clauses,
        untyped_pattern?(pattern),
        not handles_exception?(body, recovery_calls) do
      clause_details(pattern)
    end
  end

  # A bare variable (`error`, `_`, `_error`) has an atom context; the typed forms
  # (`error in File.Error`, `error in [...]`, a bare exception module) all carry a
  # list in the third element instead.
  defp untyped_pattern?({name, _meta, context}) when is_atom(name) and is_atom(context), do: true
  defp untyped_pattern?(_pattern), do: false

  defp handles_exception?(body, recovery_calls) do
    {_ast, handled} =
      Macro.prewalk(body, false, fn ast, handled ->
        {ast, handled or recovery_call?(ast, recovery_calls)}
      end)

    handled
  end

  defp recovery_call?(
         {{:., _, [{:__aliases__, _, segments}, _function]}, _meta, _args},
         recovery_calls
       ) do
    Module.concat(segments) in recovery_calls.modules
  end

  defp recovery_call?({function, _meta, args}, recovery_calls)
       when is_atom(function) and is_list(args) do
    function in recovery_calls.functions
  end

  defp recovery_call?(_ast, _recovery_calls), do: false

  defp clause_details({name, meta, _context}), do: %{name: name, line_no: meta[:line]}

  defp issue_for(blanket_rescue, issue_meta) do
    trigger = Atom.to_string(blanket_rescue.name)

    format_issue(issue_meta,
      message:
        "rescue #{trigger} found — rescue specific exceptions (e.g. `error in File.Error`), " <>
          "reraise, or log the error instead of swallowing every exception",
      trigger: trigger,
      line_no: blanket_rescue.line_no
    )
  end
end
