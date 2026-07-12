defmodule MikaCredoRules.NoApplicationEnvOutsideConfig do
  use Credo.Check,
    base_priority: :high,
    category: :design,
    param_defaults: [
      config_files: ["config.ex"],
      functions: [
        :get_env,
        :fetch_env,
        :fetch_env!,
        :get_all_env,
        :compile_env,
        :compile_env!,
        :put_env,
        :put_all_env,
        :delete_env
      ],
      erlang_functions: [:get_env, :get_all_env, :set_env, :unset_env]
    ],
    explanations: [
      params: [
        config_files: """
        A list of file path suffixes treated as config modules. A source file whose
        path ends with any of these is exempt from the check.

        Defaults to `["config.ex"]`, which exempts both `lib/my_app/config.ex` and
        `apps/my_app/lib/my_app/config.ex`.
        """,
        functions: """
        A list of atoms naming the `Application` functions that count as environment
        access. Defaults to every read and write in the `Application` env API.
        """,
        erlang_functions: """
        A list of atoms naming the erlang `:application` functions that count as
        environment access. Erlang names its writes differently from Elixir
        (`set_env`/`unset_env` rather than `put_env`/`delete_env`), so this is a
        separate list from `:functions`.
        """
      ]
    ]

  alias MikaCredoRules.SourceFilter

  @moduledoc """
  Application environment must only be read or written from a config module.

  Scattered `Application.get_env/2` and `Application.put_env/3` calls make
  configuration unauditable and untestable. Wrap every environment read and write in
  a single config module per app, and have the rest of the app call that module.

      # BAD — env read in a service module
      defmodule MyApp.Worker do
        def provider, do: Application.get_env(:my_app, :provider)
      end

      # GOOD — config.ex owns the env, the worker calls it
      defmodule MyApp.Config do
        def provider, do: Application.get_env(:my_app, :provider)
      end

      defmodule MyApp.Worker do
        def provider, do: MyApp.Config.provider()
      end

  Config modules are identified by filename via the `:config_files` param, so this
  works the same in an umbrella (`apps/my_app/lib/my_app/config.ex`) and a single app
  (`lib/my_app/config.ex`).

  There are no other exemptions. Test files and `application.ex` are checked too — a
  test reaching for `Application.put_env/3` is exactly the case this rule exists to
  catch.

  Env access is caught through every spelling of the module:

      alias Application, as: App
      App.get_env(:my_app, :provider)          # caught
      Elixir.Application.get_env(:my_app, :x)  # caught
      :application.get_env(:my_app, :x)        # caught

  Aliases are resolved from a flat, file-level table rather than a lexical scope
  stack. An alias declared inside one function is treated as applying to the whole
  file. Being wrong would require the same alias name to mean two different modules
  in two functions of one file.

  Aliases injected by a macro (via `__using__`) are invisible to Credo and cannot be
  resolved.
  """
  @explanation [check: @moduledoc]

  @application [:Application]
  @fully_qualified_application [Elixir, :Application]
  @erlang_application :application

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    if config_module?(source_file.filename, config_files(params)) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      context = build_context(source_file, params)

      source_file
      |> Credo.Code.prewalk(&traverse(&1, &2, context))
      |> Enum.map(&issue_for(&1, issue_meta))
    end
  end

  defp config_files(params), do: Params.get(params, :config_files, __MODULE__)

  defp config_module?(filename, config_files) do
    SourceFilter.matches_suffix?(filename, config_files)
  end

  defp build_context(source_file, params) do
    %{
      modules: application_modules(source_file),
      functions: Params.get(params, :functions, __MODULE__),
      erlang_functions: Params.get(params, :erlang_functions, __MODULE__)
    }
  end

  # Every module path in this file that refers to Elixir's `Application`, starting
  # from the two spellings that always do and folding each alias over that base.
  defp application_modules(source_file) do
    source_file
    |> Credo.Code.prewalk(&collect_aliases/2)
    |> Enum.reduce([@application, @fully_qualified_application], &apply_alias/2)
  end

  defp collect_aliases({:alias, _, [{:__aliases__, _, target}]} = ast, aliases) do
    {ast, [{[List.last(target)], target} | aliases]}
  end

  defp collect_aliases({:alias, _, [{:__aliases__, _, target}, opts]} = ast, aliases)
       when is_list(opts) do
    {ast, [{alias_name(target, opts), target} | aliases]}
  end

  defp collect_aliases(ast, aliases), do: {ast, aliases}

  defp alias_name(target, opts) do
    case Keyword.get(opts, :as) do
      {:__aliases__, _, name} -> name
      _ -> [List.last(target)]
    end
  end

  # `alias Application, as: App` — App now means Application.
  defp apply_alias({name, target}, modules)
       when target === @application
       when target === @fully_qualified_application do
    [name | modules]
  end

  # `alias MyApp.Application` — bare Application no longer means Elixir's.
  defp apply_alias({@application, _target}, modules), do: modules -- [@application]

  defp apply_alias(_alias, modules), do: modules

  defp traverse(
         {{:., _, [{:__aliases__, _, module}, function]}, meta, args} = ast,
         env_calls,
         context
       )
       when is_list(args) do
    if module in context.modules and function in context.functions do
      {ast, [env_call(Enum.join(module, "."), function, args, meta) | env_calls]}
    else
      {ast, env_calls}
    end
  end

  defp traverse({{:., _, [@erlang_application, function]}, meta, args} = ast, env_calls, context)
       when is_list(args) do
    if function in context.erlang_functions do
      {ast, [env_call(":application", function, args, meta) | env_calls]}
    else
      {ast, env_calls}
    end
  end

  defp traverse(ast, env_calls, _context), do: {ast, env_calls}

  defp env_call(module, function, args, meta) do
    %{module: module, function: function, arity: length(args), line_no: meta[:line]}
  end

  defp issue_for(env_call, issue_meta) do
    trigger = "#{env_call.module}.#{env_call.function}"

    format_issue(issue_meta,
      message:
        "#{trigger}/#{env_call.arity} found — application env must only be read or written from a config module (e.g. MyApp.Config)",
      trigger: trigger,
      line_no: env_call.line_no
    )
  end
end
