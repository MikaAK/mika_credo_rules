defmodule MikaCredoRules.NoApplicationEnvOutsideConfigTest do
  use Credo.Test.Case

  alias MikaCredoRules.NoApplicationEnvOutsideConfig

  @worker_file "apps/my_app/lib/my_app/worker.ex"
  @config_file "apps/my_app/lib/my_app/config.ex"

  describe "&run/2 flags env access outside a config module" do
    test "reports Application.get_env/2" do
      """
      defmodule MyApp.Worker do
        def provider, do: Application.get_env(:my_app, :provider)
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoApplicationEnvOutsideConfig)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.message =~ "Application.get_env/2"
      end)
    end

    test "reports Application.compile_env/3" do
      """
      defmodule MyApp.Worker do
        @provider Application.compile_env(:my_app, :provider, :default)
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoApplicationEnvOutsideConfig)
      |> assert_issue(fn issue -> assert issue.message =~ "Application.compile_env/3" end)
    end

    test "reports Application.put_env/3" do
      """
      defmodule MyApp.Worker do
        def override do
          Application.put_env(:my_app, :provider, :stub)
        end
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoApplicationEnvOutsideConfig)
      |> assert_issue(fn issue -> assert issue.message =~ "Application.put_env/3" end)
    end

    test "reports every env function in the default list" do
      """
      defmodule MyApp.Worker do
        def all do
          Application.get_env(:my_app, :one)
          Application.fetch_env(:my_app, :two)
          Application.fetch_env!(:my_app, :three)
          Application.get_all_env(:my_app)
          Application.compile_env(:my_app, :four)
          Application.compile_env!(:my_app, :five)
          Application.put_env(:my_app, :six, 6)
          Application.put_all_env(my_app: [seven: 7])
          Application.delete_env(:my_app, :eight)
        end
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoApplicationEnvOutsideConfig)
      |> assert_issues(fn issues -> assert length(issues) === 9 end)
    end

    test "reports each call site with its own line number" do
      """
      defmodule MyApp.Worker do
        def one, do: Application.get_env(:my_app, :one)
        def two, do: Application.get_env(:my_app, :two)
        def three, do: Application.get_env(:my_app, :three)
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoApplicationEnvOutsideConfig)
      |> assert_issues(fn issues ->
        assert issues |> Enum.map(& &1.line_no) |> Enum.sort() === [2, 3, 4]
      end)
    end

    test "reports env access inside a test file" do
      """
      defmodule MyApp.WorkerTest do
        test "it works" do
          Application.put_env(:my_app, :provider, :stub)
        end
      end
      """
      |> to_source_file("apps/my_app/test/my_app/worker_test.exs")
      |> run_check(NoApplicationEnvOutsideConfig)
      |> assert_issue()
    end

    test "reports env access inside application.ex" do
      """
      defmodule MyApp.Application do
        def start(_type, _args) do
          Supervisor.start_link(children(), strategy: :one_for_one)
        end

        defp children, do: Application.get_env(:my_app, :children, [])
      end
      """
      |> to_source_file("apps/my_app/lib/my_app/application.ex")
      |> run_check(NoApplicationEnvOutsideConfig)
      |> assert_issue()
    end
  end

  describe "&run/2 allows env access inside a config module" do
    test "does not report reads and writes in config.ex" do
      """
      defmodule MyApp.Config do
        @app :my_app

        def provider, do: Application.get_env(@app, :provider)
        def timeout!, do: Application.fetch_env!(@app, :timeout)
        def put_provider(provider), do: Application.put_env(@app, :provider, provider)
      end
      """
      |> to_source_file(@config_file)
      |> run_check(NoApplicationEnvOutsideConfig)
      |> refute_issues()
    end

    test "does not report a config.ex outside an umbrella" do
      """
      defmodule MyApp.Config do
        def provider, do: Application.get_env(:my_app, :provider)
      end
      """
      |> to_source_file("lib/my_app/config.ex")
      |> run_check(NoApplicationEnvOutsideConfig)
      |> refute_issues()
    end
  end

  describe "&run/2 ignores non-env Application functions" do
    test "does not report app_dir, get_application, spec or ensure_all_started" do
      """
      defmodule MyApp.Worker do
        def priv, do: Application.app_dir(:my_app, "priv")
        def owner, do: Application.get_application(__MODULE__)
        def version, do: Application.spec(:my_app, :vsn)
        def boot, do: Application.ensure_all_started(:my_app)
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoApplicationEnvOutsideConfig)
      |> refute_issues()
    end

    test "does not report env functions called on another module" do
      """
      defmodule MyApp.Worker do
        def provider, do: MyApp.Config.get_env(:my_app, :provider)
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoApplicationEnvOutsideConfig)
      |> refute_issues()
    end
  end

  describe "&run/2 honours the :config_files param" do
    test "treats a custom filename as a config module" do
      """
      defmodule MyApp.Settings do
        def provider, do: Application.get_env(:my_app, :provider)
      end
      """
      |> to_source_file("apps/my_app/lib/my_app/settings.ex")
      |> run_check(NoApplicationEnvOutsideConfig, config_files: ["settings.ex"])
      |> refute_issues()
    end

    test "flags config.ex once it is no longer in :config_files" do
      """
      defmodule MyApp.Config do
        def provider, do: Application.get_env(:my_app, :provider)
      end
      """
      |> to_source_file(@config_file)
      |> run_check(NoApplicationEnvOutsideConfig, config_files: ["settings.ex"])
      |> assert_issue()
    end
  end

  describe "&run/2 honours the :functions param" do
    test "flags only the configured functions" do
      """
      defmodule MyApp.Worker do
        def read, do: Application.get_env(:my_app, :provider)
        def write, do: Application.put_env(:my_app, :provider, :stub)
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoApplicationEnvOutsideConfig, functions: [:get_env])
      |> assert_issue(fn issue -> assert issue.message =~ "Application.get_env/2" end)
    end
  end

  describe "&run/2 resolves aliases of Application" do
    test "reports env access through an aliased name" do
      """
      defmodule MyApp.Worker do
        alias Application, as: App

        def provider, do: App.get_env(:my_app, :provider)
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoApplicationEnvOutsideConfig)
      |> assert_issue(fn issue -> assert issue.message =~ "App.get_env/2" end)
    end

    test "reports env access when Application is aliased without renaming" do
      """
      defmodule MyApp.Worker do
        alias Application

        def provider, do: Application.get_env(:my_app, :provider)
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoApplicationEnvOutsideConfig)
      |> assert_issue()
    end

    test "reports fully qualified Elixir.Application" do
      """
      defmodule MyApp.Worker do
        def provider, do: Elixir.Application.get_env(:my_app, :provider)
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoApplicationEnvOutsideConfig)
      |> assert_issue(fn issue -> assert issue.message =~ "Elixir.Application.get_env/2" end)
    end

    test "does not report when Application is shadowed by another module's alias" do
      """
      defmodule MyApp.Worker do
        alias MyApp.Application

        def children, do: Application.get_env(:my_app, :children)
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoApplicationEnvOutsideConfig)
      |> refute_issues()
    end

    test "still reports Application when a shadowing alias is renamed away" do
      """
      defmodule MyApp.Worker do
        alias MyApp.Application, as: AppSupervisor

        def provider, do: Application.get_env(:my_app, :provider)
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoApplicationEnvOutsideConfig)
      |> assert_issue()
    end

    test "ignores unrelated aliases" do
      """
      defmodule MyApp.Worker do
        alias MyApp.{Config, Repo}
        alias MyApp.Worker.State, as: State

        def provider, do: Application.get_env(:my_app, :provider)
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoApplicationEnvOutsideConfig)
      |> assert_issue()
    end
  end

  describe "&run/2 flags the erlang :application module" do
    test "reports :application.get_env/2" do
      """
      defmodule MyApp.Worker do
        def provider, do: :application.get_env(:my_app, :provider)
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoApplicationEnvOutsideConfig)
      |> assert_issue(fn issue -> assert issue.message =~ ":application.get_env/2" end)
    end

    test "reports every erlang env function in the default list" do
      """
      defmodule MyApp.Worker do
        def all do
          :application.get_env(:my_app, :one)
          :application.get_all_env(:my_app)
          :application.set_env(:my_app, :two, 2)
          :application.unset_env(:my_app, :three)
        end
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoApplicationEnvOutsideConfig)
      |> assert_issues(fn issues -> assert length(issues) === 4 end)
    end

    test "does not report non-env :application functions" do
      """
      defmodule MyApp.Worker do
        def boot, do: :application.ensure_all_started(:my_app)
        def which, do: :application.which_applications()
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoApplicationEnvOutsideConfig)
      |> refute_issues()
    end

    test "does not report erlang env access inside a config module" do
      """
      defmodule MyApp.Config do
        def provider, do: :application.get_env(:my_app, :provider)
      end
      """
      |> to_source_file(@config_file)
      |> run_check(NoApplicationEnvOutsideConfig)
      |> refute_issues()
    end

    test "honours the :erlang_functions param" do
      """
      defmodule MyApp.Worker do
        def read, do: :application.get_env(:my_app, :provider)
        def write, do: :application.set_env(:my_app, :provider, :stub)
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoApplicationEnvOutsideConfig, erlang_functions: [:set_env])
      |> assert_issue(fn issue -> assert issue.message =~ ":application.set_env/3" end)
    end
  end
end
