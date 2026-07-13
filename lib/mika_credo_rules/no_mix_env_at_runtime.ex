defmodule MikaCredoRules.NoMixEnvAtRuntime do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      functions: [:env, :target],
      excluded_paths: ["mix/tasks/"]
    ],
    explanations: [
      params: [
        functions: """
        A list of atoms naming the `Mix` functions that count as build environment
        access. Defaults to `[:env, :target]`.
        """,
        excluded_paths: """
        A list of path fragments treated as Mix-only code. A source file whose path
        contains any of these at a directory boundary is exempt from the check —
        `"test/"` matches `test/foo.ex` and `lib/test/foo.ex`, not `lib/latest/foo.ex`.

        Defaults to `["mix/tasks/"]`, which exempts the conventional Mix task
        directory. Modules that `use Mix.Task` are exempt regardless of path.
        """
      ]
    ]

  alias MikaCredoRules.AstHelpers
  alias MikaCredoRules.SourceFilter

  @moduledoc """
  `Mix.env()` and `Mix.target()` must not be called from compiled code.

  Mix is a build tool — it is not part of a release. A `Mix.env()` call that
  compiles fine in dev crashes in prod with `UndefinedFunctionError`. Branch on the
  environment at compile time via config instead.

      # BAD — a def/defp body re-executes on every call; crashes in a release
      defmodule MyApp.Worker do
        def start_link(opts) do
          if Mix.env() === :prod, do: connect(opts), else: :ignore
        end
      end

      # GOOD — a module attribute bakes the value in once, at compile time
      defmodule MyApp.Worker do
        @connect_on_start? Mix.env() === :prod

        def start_link(opts) do
          if @connect_on_start?, do: connect(opts), else: :ignore
        end
      end

      # GOOD — same for `use` option lists and a module-level `if`
      defmodule MyApp.Worker do
        use GenServer, restart: (if Mix.env() === :test, do: :temporary, else: :permanent)

        if Mix.env() === :test do
          def toplogy_supervisor(_opts), do: []
        else
          def toplogy_supervisor(_opts), do: real_impl()
        end
      end

  Only a `def`/`defp` *body* counts as runtime access — that is the only
  position where the call re-executes on every invocation and can crash a
  release. A module attribute, a `use` option list, and a module-level `if`
  all run exactly once, while the module compiles, and are never flagged —
  `Mix` is always available at compile time, in a release build same as dev.

  Script files are exempt: any file ending in `.exs` (`mix.exs`, `config/*.exs`,
  tests) runs under Mix, where `Mix.env()` is available and appropriate.

  Mix tasks are exempt too — they only ever run under Mix, never in a release. A
  file is treated as a Mix task when it contains `use Mix.Task` or when its path
  contains an entry of `:excluded_paths` (default `["mix/tasks/"]`).

  `test/support/*.ex` files are flagged the same as any other file when a call
  sits inside a `def`/`defp` body — they compile only for tests and never ship
  in a release, but the stance is the same as elsewhere: a runtime-position
  branch belongs in config, not a hardcoded `Mix.env()` check. Add
  `"test/support/"` to `:excluded_paths` to opt out.

  ## Known limitations

  The module is matched by spelling — `Mix.env()` and `Elixir.Mix.env()` are
  caught. A renamed alias (`alias Mix, as: Build`) is not resolved and escapes the
  check; shadowing (`alias MyApp.Mix`) is likewise not resolved and would be
  falsely flagged. Both spellings are pathological enough not to warrant alias
  tracking here.

  `use Mix.Task` exempts the whole file, not just the enclosing module. Being
  wrong would require a file to define both a Mix task and an ordinary runtime
  module — one module per file makes this moot.

  Dynamic dispatch escapes the check — `apply(Mix, :env, [])` crashes a release
  exactly like `Mix.env()` but is not a dot-call node and is not matched. This
  is an evasion vector, not an idiom; no static check catches it without taint
  analysis.
  """
  @explanation [check: @moduledoc]

  @mix_paths AstHelpers.module_paths(Mix)
  @mix_task_paths AstHelpers.module_paths(Mix.Task)

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    if mix_only_file?(source_file, params) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      functions = Params.get(params, :functions, __MODULE__)

      source_file
      |> Credo.Code.prewalk(&traverse(&1, &2, functions))
      |> Enum.map(&issue_for(&1, issue_meta))
    end
  end

  defp mix_only_file?(source_file, params) do
    SourceFilter.script_file?(source_file.filename) or
      excluded_path?(source_file.filename, excluded_paths(params)) or
      mix_task_file?(source_file)
  end

  defp excluded_paths(params), do: Params.get(params, :excluded_paths, __MODULE__)

  defp excluded_path?(filename, excluded_paths) do
    SourceFilter.matches_fragment?(filename, excluded_paths)
  end

  defp mix_task_file?(source_file) do
    Credo.Code.prewalk(source_file, &find_use_mix_task/2, false)
  end

  defp find_use_mix_task({:use, _, [{:__aliases__, _, target} | _]} = ast, _mix_task_found)
       when target in @mix_task_paths do
    {ast, true}
  end

  defp find_use_mix_task(ast, mix_task_found), do: {ast, mix_task_found}

  # `quote do ... end` defines code at the macro's call site, not in this
  # file — don't descend into quoted code.
  defp traverse({:quote, _, args}, mix_calls, _functions) when is_list(args) do
    {nil, mix_calls}
  end

  # Only a `def`/`defp` BODY re-executes on every call — that is the only
  # position where `Mix.env()`/`Mix.target()` crashes a release. Module
  # attributes, `use` option lists, and module-level `if` all run once, at
  # compile time, and are left alone. Pruning the def/defp subtree here and
  # walking it ourselves keeps the outer prewalk from visiting it a second
  # time.
  defp traverse({kind, _, [_head, _body]} = ast, mix_calls, functions)
       when kind in [:def, :defp] do
    {nil, collect_runtime_mix_calls(ast, functions) ++ mix_calls}
  end

  defp traverse(ast, mix_calls, _functions), do: {ast, mix_calls}

  defp collect_runtime_mix_calls(def_ast, functions) do
    def_ast
    |> Macro.prewalk([], &collect_mix_call(&1, &2, functions))
    |> elem(1)
    |> Enum.reverse()
  end

  defp collect_mix_call(
         {{:., _, [{:__aliases__, _, module}, function]}, meta, args} = ast,
         mix_calls,
         functions
       )
       when module in @mix_paths do
    if function in functions and args === [] do
      {ast, [mix_call(Enum.join(module, "."), function, meta) | mix_calls]}
    else
      {ast, mix_calls}
    end
  end

  defp collect_mix_call(ast, mix_calls, _functions), do: {ast, mix_calls}

  defp mix_call(module, function, meta) do
    %{module: module, function: function, line_no: meta[:line]}
  end

  defp issue_for(mix_call, issue_meta) do
    trigger = "#{mix_call.module}.#{mix_call.function}"

    format_issue(issue_meta,
      message:
        "#{trigger}/0 found — Mix is not available in a release; branch at compile time with Application.compile_env/3 and per-environment config",
      trigger: trigger,
      line_no: mix_call.line_no
    )
  end
end
