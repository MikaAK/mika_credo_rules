defmodule MikaCredoRules.NoKernelPrefix do
  use Credo.Check,
    base_priority: :high,
    category: :readability,
    param_defaults: [
      allowed_functions: [],
      excluded_paths: []
    ],
    explanations: [
      params: [
        allowed_functions: """
        A list of function name atoms that are allowed to be called with the
        `Kernel.` prefix anyway.

        Defaults to `[]`.
        """,
        excluded_paths: """
        A list of path fragments naming files this check skips. A fragment
        matches when the source file's path starts with it, ends with it, or
        contains it after a directory separator.

        Defaults to `[]`.
        """
      ]
    ]

  alias MikaCredoRules.AstHelpers
  alias MikaCredoRules.SourceFilter

  @moduledoc """
  `Kernel` is auto-imported — never prefix a `Kernel` function with the module
  name.

  Every function in `Kernel` is already callable unqualified. Writing
  `Kernel.inspect(value)` says nothing `inspect(value)` doesn't already say,
  and adds a name a reader has to strip before recognizing the function.

      # BAD
      Kernel.inspect(value)
      Kernel.length(list)

      # GOOD
      inspect(value)
      length(list)

  Operator captures are exempt as a readability allowance — `&Kernel.+/2`,
  `&Kernel.>=/2`, `&Kernel.!/1` read the intent (capturing an operator) more
  plainly than requiring every reader to know which operators can also be
  captured bare:

      # allowed — a readability allowance for operator captures
      Enum.reduce(list, 0, &Kernel.+/2)

  A capture of a non-operator function is not exempt — `&inspect/1` already
  works unqualified, so `&Kernel.inspect/1` is just as redundant as the call
  form and is still flagged.

  An operator used in *call* form is never flagged, in any position —
  `Kernel.++(a, b)`, `Kernel.<>(a, b)`, `list |> Kernel.||(fallback)` are the
  only valid spellings for calling those operators outside of infix position.
  Unlike the capture case, this is not a readability allowance: `++(a, b)`,
  `<>(a, b)` and `and(a, b)` are `SyntaxError`s, so there is no "call it
  directly" fix to suggest. `not/1` is an ordinary function, not an operator
  in this sense — `Kernel.not(value)` and `value |> not()` are equally valid,
  so it keeps being flagged like any other redundant prefix.

  A file that locally shadows a `Kernel` function via
  `import Kernel, except: [to_string: 1]` is honored automatically — a call
  to that exact name/arity is not flagged, because dropping the `Kernel.`
  prefix there would silently call the file's own same-named function
  instead (in the worst case, an infinite recursion) rather than Elixir's.

  Sibling modules that merely start with `Kernel.` are untouched — the module
  must resolve to exactly `Kernel`, so `Kernel.SpecialForms` and
  `Kernel.ParallelCompiler` are never flagged. Aliases are resolved the same
  way as every other check in this package, including `as:` renames — and a
  file that shadows the bare name (`alias MyApp.Kernel`) stops plain
  `Kernel.foo` in that file from referring to Elixir's `Kernel`.

  `LoggerModulePrefixAndInspect` tolerates `Kernel.inspect(value)` inside a
  Logger call — qualified spellings of its allowed functions match on the
  function name alone. This check tightens that: outside of a Logger message,
  `Kernel.inspect(value)` is flagged like every other `Kernel.`-prefixed call.

  ## Limitations

  `:"Elixir.Kernel".inspect(value)` and `apply(Kernel, :inspect, [value])`
  call the exact same function this check bans, but neither matches the
  `__aliases__` shape the traversal keys on, so both evade detection.
  """
  @explanation [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    if excluded_path?(source_file.filename, excluded_paths(params)) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      context = build_context(source_file, params)

      source_file
      |> Credo.Code.prewalk(&traverse(&1, &2, context))
      |> Enum.map(&issue_for(&1, issue_meta))
    end
  end

  defp excluded_paths(params), do: Params.get(params, :excluded_paths, __MODULE__)

  defp excluded_path?(filename, excluded_paths) do
    SourceFilter.matches_fragment?(filename, excluded_paths)
  end

  defp build_context(source_file, params) do
    kernel_modules = AstHelpers.resolve_aliases(source_file, [Kernel])

    %{
      kernel_modules: kernel_modules,
      allowed_functions: Params.get(params, :allowed_functions, __MODULE__),
      except_pairs: collect_except_pairs(source_file, kernel_modules)
    }
  end

  defp collect_except_pairs(source_file, kernel_modules) do
    Credo.Code.prewalk(source_file, &collect_except(&1, &2, kernel_modules))
  end

  defp collect_except(
         {:import, _, [{:__aliases__, _, module}, opts]} = ast,
         pairs,
         kernel_modules
       )
       when is_list(opts) do
    if module in kernel_modules do
      {ast, except_entries(opts) ++ pairs}
    else
      {ast, pairs}
    end
  end

  defp collect_except(ast, pairs, _kernel_modules), do: {ast, pairs}

  defp except_entries(opts) do
    case Keyword.get(opts, :except) do
      except when is_list(except) -> except
      _ -> []
    end
  end

  # `alias` declarations are never calls — pruning them here also stops the
  # multi-alias shape (`alias Kernel.{SpecialForms}`, desugared to a dot-call
  # on `:{}`) from being misread as a call to a function literally named `{}`.
  defp traverse({:alias, _, _}, issues, _context), do: {nil, issues}

  # A piped Kernel call is consumed here: the true arity is the argument
  # count plus the piped-in value, and the call's head is rewritten to a
  # block (arguments stay traversable) so the general clause below never
  # re-examines the same node with the wrong arity.
  defp traverse({:|>, pipe_meta, [lhs, piped_call]} = ast, issues, context) do
    case dot_call(piped_call) do
      {module, function, alias_meta, args} ->
        issues = maybe_flag_call(module, function, length(args) + 1, alias_meta, context, issues)
        {{:|>, pipe_meta, [lhs, {:__block__, [], args}]}, issues}

      nil ->
        {ast, issues}
    end
  end

  # `&Kernel.+/2` is the only way to capture an operator. This clause fully
  # resolves every Kernel-prefixed capture using the arity carried by the
  # capture syntax itself, then always prunes the subtree so the general
  # clause below never re-examines the inner call with a 0 (wrong) arity.
  defp traverse(
         {:&, _,
          [{:/, _, [{{:., _, [{:__aliases__, alias_meta, module}, function]}, _, []}, arity]}]},
         issues,
         context
       ) do
    {nil, maybe_flag_capture(module, function, arity, alias_meta, context, issues)}
  end

  defp traverse(ast, issues, context) do
    case dot_call(ast) do
      {module, function, alias_meta, args} ->
        {ast, maybe_flag_call(module, function, length(args), alias_meta, context, issues)}

      nil ->
        {ast, issues}
    end
  end

  defp dot_call({{:., _, [{:__aliases__, alias_meta, module}, function]}, _, args})
       when is_list(args) do
    {module, function, alias_meta, args}
  end

  defp dot_call(_ast), do: nil

  defp maybe_flag_call(module, function, arity, alias_meta, context, issues) do
    if module in context.kernel_modules and flag_call?(function, arity, context) do
      [call(module, function, alias_meta) | issues]
    else
      issues
    end
  end

  defp maybe_flag_capture(module, function, arity, alias_meta, context, issues) do
    if module in context.kernel_modules and flag_capture?(function, arity, context) do
      [call(module, function, alias_meta) | issues]
    else
      issues
    end
  end

  defp flag_call?(function, arity, context) do
    not call_syntax_error_if_unqualified?(function) and
      function not in context.allowed_functions and
      not excepted?(function, arity, context)
  end

  defp flag_capture?(function, arity, context) do
    not operator_function?(function) and not excepted?(function, arity, context)
  end

  defp excepted?(function, arity, context), do: {function, arity} in context.except_pairs

  defp operator_function?(function) when function in [:and, :or, :not, :in], do: true
  defp operator_function?(function), do: symbol_operator?(function)

  # `and(a, b)`, `or(a, b)` and `in(a, b)` are SyntaxErrors when written
  # unqualified — the infix form is the only valid spelling. `not/1` is a
  # genuine function (`not(value)` parses and behaves identically to
  # `Kernel.not(value)`), so it is deliberately excluded here.
  defp call_syntax_error_if_unqualified?(function) when function in [:and, :or, :in], do: true
  defp call_syntax_error_if_unqualified?(function), do: symbol_operator?(function)

  defp symbol_operator?(function) do
    function |> Atom.to_string() |> String.match?(~r/^[!&*+\-\/<=>|^~@\\]+$/)
  end

  defp call(module, function, meta) do
    %{
      trigger: "#{Enum.join(module, ".")}.#{function}",
      function: function,
      line_no: meta[:line],
      column: meta[:column]
    }
  end

  defp issue_for(call, issue_meta) do
    format_issue(issue_meta,
      message:
        "#{call.trigger} found — Kernel is auto-imported, call `#{call.function}` directly",
      trigger: call.trigger,
      line_no: call.line_no,
      column: call.column
    )
  end
end
