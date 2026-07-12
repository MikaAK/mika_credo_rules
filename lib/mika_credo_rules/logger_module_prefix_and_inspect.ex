defmodule MikaCredoRules.LoggerModulePrefixAndInspect do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      logger_functions: [:debug, :info, :warning, :warn, :error, :critical],
      enforce_prefix: true,
      allowed_interpolations: [:__MODULE__, :inspect]
    ],
    explanations: [
      params: [
        logger_functions: """
        A list of atoms naming the `Logger` functions whose messages are checked.
        Defaults to every level function: `debug`, `info`, `warning`, `warn`,
        `error` and `critical`.
        """,
        enforce_prefix: """
        Whether every message must start with the `__MODULE__` interpolation as
        its very first segment. Set to `false` to only check that interpolated
        values go through `inspect/1`. Defaults to `true`.
        """,
        allowed_interpolations: """
        A list of atoms naming what may appear inside a message interpolation
        without being flagged — `:__MODULE__` for the prefix itself, plus the
        functions whose calls are considered safe to interpolate. Qualified
        spellings match on the function name, so `Kernel.inspect(value)` is
        covered by `:inspect`.

        Defaults to `[:__MODULE__, :inspect]`. Add your own formatting helpers to
        allow `"\#{format_id(id)}"` style interpolations.
        """
      ]
    ]

  @moduledoc """
  Logger messages must start with `"\#{__MODULE__}: "` and wrap every interpolated
  value in `inspect/1`.

  A bare `\#{value}` crashes at runtime whenever the value has no `String.Chars`
  implementation — a tuple, a map, a pid. `inspect/1` renders anything. The
  `__MODULE__` prefix attributes every log line to the module that wrote it.

      # BAD — crashes when reason is a tuple like {:error, :timeout}
      Logger.error("failed: \#{reason}")

      # BAD — safe, but the log line has no source module
      Logger.error("failed: \#{inspect(reason)}")

      # GOOD
      Logger.error("\#{__MODULE__}: request failed, reason: \#{inspect(reason)}")

  The message must literally *start* with the `__MODULE__` interpolation — it has
  to be the very first segment of the string. A literal before it, as in
  `"[worker] \#{__MODULE__}: started"`, is flagged.

  Both the direct string form and the lazy zero-arity function form are checked:

      Logger.debug(fn -> "\#{__MODULE__}: state: \#{inspect(state)}" end)

  Messages the check cannot see into — a variable, a module attribute, a function
  call, a function body that is not a string literal — are skipped, since their
  content cannot be verified statically.

  A renamed alias (`alias Logger, as: Log`) is not resolved, and `import Logger`
  followed by a bare `info/1` is not detected.
  """
  @explanation [check: @moduledoc]

  @logger_modules [[:Logger], [Elixir, :Logger]]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    context = build_context(params)

    source_file
    |> Credo.Code.prewalk(&traverse(&1, &2, context))
    |> Enum.map(&issue_for(&1, issue_meta))
  end

  defp build_context(params) do
    %{
      logger_functions: Params.get(params, :logger_functions, __MODULE__),
      enforce_prefix: Params.get(params, :enforce_prefix, __MODULE__),
      allowed_interpolations: Params.get(params, :allowed_interpolations, __MODULE__)
    }
  end

  defp traverse(
         {{:., _, [{:__aliases__, _, module}, function]}, meta, args} = ast,
         violations,
         context
       )
       when module in @logger_modules and is_list(args) do
    if function in context.logger_functions do
      {ast, message_violations(module, function, args, meta, context) ++ violations}
    else
      {ast, violations}
    end
  end

  defp traverse(ast, violations, _context), do: {ast, violations}

  defp message_violations(module, function, args, meta, context) do
    call = %{
      module: Enum.join(module, "."),
      function: function,
      arity: length(args),
      line_no: meta[:line]
    }

    args
    |> List.first()
    |> message_body()
    |> check_message(call, context)
  end

  # The message is either the argument itself or, in the lazy form
  # `Logger.debug(fn -> "..." end)`, the body of the zero-arity function.
  defp message_body({:fn, _, [{:->, _, [[], body]}]}), do: body
  defp message_body(message), do: message

  defp check_message(message, call, context) when is_binary(message) do
    if context.enforce_prefix, do: [violation(:missing_prefix, call)], else: []
  end

  defp check_message({:<<>>, _, segments}, call, context) do
    prefix_violations(segments, call, context) ++
      interpolation_violations(segments, call, context)
  end

  defp check_message(_unverifiable_message, _call, _context), do: []

  defp prefix_violations(segments, call, context) do
    if context.enforce_prefix and not module_prefix?(segments) do
      [violation(:missing_prefix, call)]
    else
      []
    end
  end

  defp module_prefix?([first_segment | _other_segments]) do
    module_interpolation?(first_segment)
  end

  defp module_prefix?(_segments), do: false

  defp interpolation_violations(segments, call, context) do
    if Enum.any?(segments, &bare_interpolation?(&1, context.allowed_interpolations)) do
      [violation(:bare_interpolation, call)]
    else
      []
    end
  end

  defp bare_interpolation?(segment, allowed_interpolations) do
    interpolation?(segment) and
      not allowed_expression?(interpolated_expression(segment), allowed_interpolations)
  end

  defp interpolation?({:"::", _, [{{:., _, [Kernel, :to_string]}, _, [_expr]}, _type]}), do: true
  defp interpolation?(_segment), do: false

  defp module_interpolation?(segment) do
    match?({:"::", _, [{{:., _, [Kernel, :to_string]}, _, [{:__MODULE__, _, _}]}, _]}, segment)
  end

  defp interpolated_expression({:"::", _, [{{:., _, [Kernel, :to_string]}, _, [expr]}, _type]}) do
    expr
  end

  # A qualified call such as `Kernel.inspect(value)` is allowed whenever its
  # function name is, regardless of how the module is spelled.
  defp allowed_expression?({{:., _, [_module, function]}, _, _args}, allowed_interpolations)
       when is_atom(function) do
    function in allowed_interpolations
  end

  defp allowed_expression?({name, _, _}, allowed_interpolations) when is_atom(name) do
    name in allowed_interpolations
  end

  defp allowed_expression?(_expr, _allowed_interpolations), do: false

  defp violation(kind, call), do: Map.put(call, :kind, kind)

  defp issue_for(violation, issue_meta) do
    trigger = "#{violation.module}.#{violation.function}"

    format_issue(issue_meta,
      message: violation_message(violation, trigger),
      trigger: trigger,
      line_no: violation.line_no
    )
  end

  defp violation_message(%{kind: :missing_prefix} = violation, trigger) do
    "#{trigger}/#{violation.arity} without a __MODULE__ prefix found — start every Logger message with \"\#{__MODULE__}: \""
  end

  defp violation_message(%{kind: :bare_interpolation} = violation, trigger) do
    "#{trigger}/#{violation.arity} interpolating a bare value found — wrap interpolated values in inspect/1, bare values crash without a String.Chars implementation"
  end
end
