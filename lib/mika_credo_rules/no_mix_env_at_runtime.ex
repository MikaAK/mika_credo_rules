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

  @moduledoc """
  `Mix.env()` and `Mix.target()` must not be called from compiled code.

  Mix is a build tool — it is not part of a release. A `Mix.env()` call that
  compiles fine in dev crashes in prod with `UndefinedFunctionError`. Branch on the
  environment at compile time via config instead.

      # BAD — crashes in a release
      defmodule MyApp.Worker do
        def start_link(opts) do
          if Mix.env() === :prod, do: connect(opts), else: :ignore
        end
      end

      # GOOD — config decides, code reads config
      # config/prod.exs
      config :my_app, connect_on_start: true

      # worker.ex
      defmodule MyApp.Worker do
        @connect_on_start Application.compile_env(:my_app, :connect_on_start, false)

        def start_link(opts) do
          if @connect_on_start, do: connect(opts), else: :ignore
        end
      end

  Script files are exempt: any file ending in `.exs` (`mix.exs`, `config/*.exs`,
  tests) runs under Mix, where `Mix.env()` is available and appropriate.

  Mix tasks are exempt too — they only ever run under Mix, never in a release. A
  file is treated as a Mix task when it contains `use Mix.Task` or when its path
  contains an entry of `:excluded_paths` (default `["mix/tasks/"]`).

  Module attributes are still flagged. `@env Mix.env()` is evaluated at compile
  time and does not crash a release, but it bakes the build environment into the
  code invisibly — use `Application.compile_env/3` with per-environment config so
  the branch is auditable from `config/`.

  `test/support/*.ex` files are still flagged too. They compile only for tests and
  never ship in a release, but the stance is the same as for module attributes:
  the environment branch belongs in config. Add `"test/support/"` to
  `:excluded_paths` to opt out.

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

  @mix [:Mix]
  @fully_qualified_mix [Elixir, :Mix]
  @mix_task [:Mix, :Task]
  @fully_qualified_mix_task [Elixir, :Mix, :Task]

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
    script_file?(source_file.filename) or
      excluded_path?(source_file.filename, excluded_paths(params)) or
      mix_task_file?(source_file)
  end

  defp script_file?(filename), do: String.ends_with?(filename, ".exs")

  defp excluded_paths(params), do: Params.get(params, :excluded_paths, __MODULE__)

  defp excluded_path?(filename, excluded_paths) do
    Enum.any?(excluded_paths, &fragment_matches?(filename, &1))
  end

  defp fragment_matches?(filename, fragment) do
    String.ends_with?(filename, fragment) or String.starts_with?(filename, fragment) or
      String.contains?(filename, "/#{fragment}")
  end

  defp mix_task_file?(source_file) do
    Credo.Code.prewalk(source_file, &find_use_mix_task/2, false)
  end

  defp find_use_mix_task({:use, _, [{:__aliases__, _, target} | _]} = ast, _mix_task_found)
       when target === @mix_task
       when target === @fully_qualified_mix_task do
    {ast, true}
  end

  defp find_use_mix_task(ast, mix_task_found), do: {ast, mix_task_found}

  defp traverse(
         {{:., _, [{:__aliases__, _, module}, function]}, meta, args} = ast,
         mix_calls,
         functions
       )
       when module === @mix
       when module === @fully_qualified_mix do
    if function in functions and args === [] do
      {ast, [mix_call(Enum.join(module, "."), function, meta) | mix_calls]}
    else
      {ast, mix_calls}
    end
  end

  defp traverse(ast, mix_calls, _functions), do: {ast, mix_calls}

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
