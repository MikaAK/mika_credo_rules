defmodule MikaCredoRules.FunWithFlagsAtomFlagNames do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      modules: [FunWithFlags],
      functions: [:enabled?, :enable, :disable, :clear, :get_flag],
      excluded_paths: []
    ],
    explanations: [
      params: [
        modules: """
        A list of modules whose flag-name argument is checked. Defaults to
        `[FunWithFlags]`; add a wrapper module (e.g. `MyApp.FeatureFlags`) so a
        project's own facade is covered too. Alias-aware, like every
        module-identity param in this package.
        """,
        functions: """
        A list of atoms naming the functions whose first argument is a flag
        name. Defaults to `[:enabled?, :enable, :disable, :clear, :get_flag]`
        — `FunWithFlags` has no `lookup/1`; the read function is `get_flag/1`.
        """,
        excluded_paths: """
        A list of path fragments naming files this check skips (matched on
        segment boundaries). Defaults to `[]`.
        """
      ]
    ]

  alias MikaCredoRules.AstHelpers
  alias MikaCredoRules.SourceFilter

  @moduledoc """
  `FunWithFlags` flag names must be atoms, never string literals.

  `FunWithFlags.enabled?/1` and the rest of its API match a flag by atom
  identity. A string flag name is a *different*, never-registered flag — the
  call silently returns `false` rather than raising, so the bug hides behind
  "the feature is off" instead of a crash.

      # BAD — a different, unregistered flag; always returns false
      FunWithFlags.enabled?("beta_feature")

      # GOOD
      FunWithFlags.enabled?(:beta_feature)

  Only string literals are flagged. A flag name built from a variable or
  interpolation is invisible to this check — an accepted false negative, since
  static analysis cannot know its runtime value.

  A wrapper module can be added through the `:modules` param so a project's own
  feature-flag facade is covered too.

  Aliases are resolved from a flat, file-level table rather than a lexical
  scope stack. Aliases injected by a macro (via `__using__`) are invisible to
  Credo and cannot be resolved.

  ## Limitations

    * `apply(FunWithFlags, :enabled?, ["beta_feature"])` is invisible — this
      check only matches the `Module.function(args)` call shape, not dynamic
      dispatch through `apply/3`.
    * A piped call (`"beta_feature" |> FunWithFlags.enabled?()`) is invisible:
      the pipe leaves the call node with no arguments of its own, so the flag
      name never appears in the position this check inspects.
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
      modules: AstHelpers.resolve_aliases(source_file, Params.get(params, :modules, __MODULE__)),
      functions: Params.get(params, :functions, __MODULE__)
    }
  end

  defp traverse(
         {{:., _, [{:__aliases__, alias_meta, module}, function]}, _meta, [flag_name | _rest]} =
           ast,
         calls,
         context
       )
       when is_binary(flag_name) do
    if module in context.modules and function in context.functions do
      {ast, [flag_call(module, function, alias_meta) | calls]}
    else
      {ast, calls}
    end
  end

  defp traverse(ast, calls, _context), do: {ast, calls}

  defp flag_call(module, function, meta) do
    %{
      trigger: "#{Enum.join(module, ".")}.#{function}",
      line_no: meta[:line],
      column: meta[:column]
    }
  end

  defp issue_for(call, issue_meta) do
    format_issue(issue_meta,
      message:
        "#{call.trigger} found — flags are matched by atom identity; a string flag name silently returns false instead of raising",
      trigger: call.trigger,
      line_no: call.line_no,
      column: call.column
    )
  end
end
