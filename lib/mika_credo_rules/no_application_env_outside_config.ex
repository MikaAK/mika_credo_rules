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
      ]
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
        """
      ]
    ]

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

  Calls made through an alias (`alias Application, as: App`) are not detected.
  """
  @explanation [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    if config_module?(source_file.filename, config_files(params)) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)

      source_file
      |> Credo.Code.prewalk(&traverse(&1, &2, functions(params)))
      |> Enum.map(&issue_for(&1, issue_meta))
    end
  end

  defp config_files(params), do: Params.get(params, :config_files, __MODULE__)

  defp functions(params), do: Params.get(params, :functions, __MODULE__)

  defp config_module?(filename, config_files) do
    Enum.any?(config_files, &String.ends_with?(filename, &1))
  end

  defp traverse(
         {{:., _, [{:__aliases__, _, [:Application]}, function]}, meta, args} = ast,
         env_calls,
         functions
       )
       when is_list(args) do
    if function in functions do
      {ast, [{function, length(args), meta[:line]} | env_calls]}
    else
      {ast, env_calls}
    end
  end

  defp traverse(ast, env_calls, _functions), do: {ast, env_calls}

  defp issue_for({function, arity, line_no}, issue_meta) do
    format_issue(issue_meta,
      message:
        "Application.#{function}/#{arity} found — application env must only be read or written from a config module (e.g. MyApp.Config)",
      trigger: "Application.#{function}",
      line_no: line_no
    )
  end
end
