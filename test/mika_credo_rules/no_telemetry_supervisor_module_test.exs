defmodule MikaCredoRules.NoTelemetrySupervisorModuleTest do
  use Credo.Test.Case

  alias MikaCredoRules.NoTelemetrySupervisorModule

  @telemetry_file "apps/my_app_web/lib/my_app_web/telemetry.ex"

  describe "&run/2 flags a Telemetry module that uses Supervisor" do
    test "reports the phx.new-generated Telemetry supervisor" do
      """
      defmodule MyAppWeb.Telemetry do
        use Supervisor

        def start_link(arg), do: Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
      end
      """
      |> to_source_file(@telemetry_file)
      |> run_check(NoTelemetrySupervisorModule)
      |> assert_issue(fn issue ->
        assert issue.line_no === 1
        assert issue.trigger === "defmodule"
        assert issue.message =~ "Telemetry"
        assert issue.message =~ "application.ex"
      end)
    end

    test "reports a top-level Telemetry module" do
      """
      defmodule Telemetry do
        use Supervisor
        def init(_arg), do: Supervisor.init([], strategy: :one_for_one)
      end
      """
      |> to_source_file(@telemetry_file)
      |> run_check(NoTelemetrySupervisorModule)
      |> assert_issue()
    end

    test "reports use Supervisor under an alias" do
      """
      defmodule MyAppWeb.Telemetry do
        alias Supervisor, as: Sup

        use Sup

        def init(_arg), do: :ok
      end
      """
      |> to_source_file(@telemetry_file)
      |> run_check(NoTelemetrySupervisorModule)
      |> assert_issue()
    end

    test "reports a nested Telemetry module inside another module" do
      """
      defmodule MyApp.Endpoint do
        defmodule Telemetry do
          use Supervisor
          def init(_arg), do: :ok
        end

        def call(conn, _opts), do: conn
      end
      """
      |> to_source_file(@telemetry_file)
      |> run_check(NoTelemetrySupervisorModule)
      |> assert_issue(fn issue -> assert issue.line_no === 2 end)
    end

    test "honors a custom :module_suffixes param" do
      """
      defmodule MyAppWeb.Metrics do
        use Supervisor
        def init(_arg), do: :ok
      end
      """
      |> to_source_file(@telemetry_file)
      |> run_check(NoTelemetrySupervisorModule, module_suffixes: [:Metrics])
      |> assert_issue()
    end

    test "reports Elixir.Supervisor (qualified spelling) even when the bare name is shadowed" do
      """
      defmodule MyAppWeb.Telemetry do
        alias MyApp.Supervisor

        use Elixir.Supervisor

        def init(_arg), do: :ok
      end
      """
      |> to_source_file(@telemetry_file)
      |> run_check(NoTelemetrySupervisorModule)
      |> assert_issue()
    end

    test "reports a custom :supervisor_modules entry in its atom-quoted spelling" do
      """
      defmodule MyAppWeb.Telemetry do
        use :"Elixir.MyApp.OnlyThis"
        def init(_arg), do: :ok
      end
      """
      |> to_source_file(@telemetry_file)
      |> run_check(NoTelemetrySupervisorModule, supervisor_modules: [MyApp.OnlyThis])
      |> assert_issue()
    end
  end

  describe "&run/2 leaves plain and non-matching modules alone" do
    test "does not report a Telemetry module that is not a Supervisor" do
      """
      defmodule MyAppWeb.Telemetry do
        def metrics, do: []
      end
      """
      |> to_source_file(@telemetry_file)
      |> run_check(NoTelemetrySupervisorModule)
      |> refute_issues()
    end

    test "does not report a Supervisor module that is not named Telemetry" do
      """
      defmodule MyApp.Supervisor do
        use Supervisor
        def init(_arg), do: Supervisor.init([], strategy: :one_for_one)
      end
      """
      |> to_source_file(@telemetry_file)
      |> run_check(NoTelemetrySupervisorModule)
      |> refute_issues()
    end

    test "does not report Supervisor shadowed by a project alias" do
      """
      defmodule MyAppWeb.Telemetry do
        alias MyApp.Supervisor

        use Supervisor

        def init(_arg), do: :ok
      end
      """
      |> to_source_file(@telemetry_file)
      |> run_check(NoTelemetrySupervisorModule)
      |> refute_issues()
    end

    test "does not report the moduledoc GOOD example" do
      """
      defmodule MyApp.Application do
        @is_prod Application.compile_env(:my_app, :env) === :prod

        def start(_type, _args) do
          children = [{PrometheusTelemetry, exporter: [enabled?: @is_prod], metrics: []}]
          Supervisor.start_link(children, strategy: :one_for_one)
        end
      end
      """
      |> to_source_file("apps/my_app/lib/my_app/application.ex")
      |> run_check(NoTelemetrySupervisorModule)
      |> refute_issues()
    end

    test "does not report an unconfigured module in its atom-quoted spelling" do
      """
      defmodule MyAppWeb.Telemetry do
        use :"Elixir.Supervisor"
        def init(_arg), do: :ok
      end
      """
      |> to_source_file(@telemetry_file)
      |> run_check(NoTelemetrySupervisorModule, supervisor_modules: [MyApp.OnlyThis])
      |> refute_issues()
    end
  end

  describe "&run/2 respects excluded_paths" do
    test "does not report a file matching excluded_paths" do
      """
      defmodule MyAppWeb.Telemetry do
        use Supervisor
        def init(_arg), do: :ok
      end
      """
      |> to_source_file("apps/legacy_app/lib/legacy_app_web/telemetry.ex")
      |> run_check(NoTelemetrySupervisorModule, excluded_paths: ["legacy_app/"])
      |> refute_issues()
    end
  end
end
