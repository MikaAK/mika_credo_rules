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

  Operator captures are exempt — `&Kernel.+/2`, `&Kernel.>=/2`, `&Kernel.!/1`
  are the *only* way to capture an operator, since `&+/2` is not valid syntax:

      # allowed — the only way to capture an operator
      Enum.reduce(list, 0, &Kernel.+/2)

  A capture of a non-operator function is not exempt — `&inspect/1` already
  works unqualified, so `&Kernel.inspect/1` is just as redundant as the call
  form and is still flagged.

  Sibling modules that merely start with `Kernel.` are untouched — the module
  must resolve to exactly `Kernel`, so `Kernel.SpecialForms` and
  `Kernel.ParallelCompiler` are never flagged. Aliases are resolved the same
  way as every other check in this package: `alias Kernel, as: K` is caught
  through `K`, and `alias MyApp.Kernel` shadows the bare name so plain
  `Kernel.foo` in that file stops referring to Elixir's `Kernel`.

  `LoggerModulePrefixAndInspect` tolerates `Kernel.inspect(value)` inside a
  Logger call — qualified spellings of its allowed functions match on the
  function name alone. This check tightens that: outside of a Logger message,
  `Kernel.inspect(value)` is flagged like every other `Kernel.`-prefixed call.
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
    %{
      kernel_modules: AstHelpers.resolve_aliases(source_file, [Kernel]),
      allowed_functions: Params.get(params, :allowed_functions, __MODULE__)
    }
  end

  # `&Kernel.+/2` is the only way to capture an operator — prune the subtree so
  # the general clause below never sees the inner dot-call. A capture of a
  # named function (`&Kernel.inspect/1`) is left untouched: `&inspect/1`
  # already works unqualified, so it is just as flagged as the call form.
  defp traverse(
         {:&, _, [{:/, _, [{{:., _, [{:__aliases__, _, module}, function]}, _, []}, _arity]}]} =
           ast,
         issues,
         context
       ) do
    if module in context.kernel_modules and operator_function?(function) do
      {nil, issues}
    else
      {ast, issues}
    end
  end

  defp traverse(
         {{:., _, [{:__aliases__, alias_meta, module}, function]}, _, args} = ast,
         issues,
         context
       )
       when is_list(args) do
    if module in context.kernel_modules and function not in context.allowed_functions do
      trigger = "#{Enum.join(module, ".")}.#{function}"
      {ast, [call(trigger, function, args, alias_meta) | issues]}
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _context), do: {ast, issues}

  defp operator_function?(function) when function in [:and, :or, :not, :in], do: true

  defp operator_function?(function) do
    function |> Atom.to_string() |> String.match?(~r/^[!&*+\-\/<=>|^~@\\]+$/)
  end

  defp call(trigger, function, args, meta) do
    %{
      trigger: trigger,
      arity: length(args),
      function: function,
      line_no: meta[:line],
      column: meta[:column]
    }
  end

  defp issue_for(call, issue_meta) do
    format_issue(issue_meta,
      message:
        "#{call.trigger}/#{call.arity} found — Kernel is auto-imported, call `#{call.function}` directly",
      trigger: call.trigger,
      line_no: call.line_no,
      column: call.column
    )
  end
end
