defmodule MikaCredoRules.NoMixEnvAtRuntimeTest do
  use Credo.Test.Case

  alias MikaCredoRules.NoMixEnvAtRuntime

  @lib_file "apps/my_app/lib/my_app/worker.ex"

  describe "&run/2 flags Mix env access in compiled files" do
    test "reports Mix.env() inside a function" do
      """
      defmodule MyApp.Worker do
        def env, do: Mix.env()
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoMixEnvAtRuntime)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.message =~ "Mix.env/0"
      end)
    end

    test "reports a Mix.env() comparison" do
      """
      defmodule MyApp.Worker do
        def prod?, do: Mix.env() === :prod
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoMixEnvAtRuntime)
      |> assert_issue(fn issue -> assert issue.message =~ "Mix.env/0" end)
    end

    test "reports Mix.target()" do
      """
      defmodule MyApp.Worker do
        def target, do: Mix.target()
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoMixEnvAtRuntime)
      |> assert_issue(fn issue -> assert issue.message =~ "Mix.target/0" end)
    end

    test "reports Mix.env() in a module attribute" do
      """
      defmodule MyApp.Worker do
        @env Mix.env()

        def env, do: @env
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoMixEnvAtRuntime)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.message =~ "Mix.env/0"
      end)
    end

    test "reports fully qualified Elixir.Mix.env()" do
      """
      defmodule MyApp.Worker do
        def env, do: Elixir.Mix.env()
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoMixEnvAtRuntime)
      |> assert_issue(fn issue -> assert issue.message =~ "Elixir.Mix.env/0" end)
    end

    test "reports each call site with its own line number" do
      """
      defmodule MyApp.Worker do
        def env, do: Mix.env()
        def target, do: Mix.target()
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoMixEnvAtRuntime)
      |> assert_issues(fn issues ->
        assert issues |> Enum.map(& &1.line_no) |> Enum.sort() === [2, 3]
      end)
    end
  end

  describe "&run/2 allows Mix env access in script files" do
    test "does not report Mix.env() in mix.exs" do
      """
      defmodule MyApp.MixProject do
        use Mix.Project

        def project do
          [app: :my_app, start_permanent: Mix.env() === :prod]
        end
      end
      """
      |> to_source_file("mix.exs")
      |> run_check(NoMixEnvAtRuntime)
      |> refute_issues()
    end

    test "does not report Mix.env() in a config script" do
      """
      import Config

      config :my_app, provider: if(Mix.env() === :test, do: :stub, else: :real)
      """
      |> to_source_file("config/config.exs")
      |> run_check(NoMixEnvAtRuntime)
      |> refute_issues()
    end

    test "does not report Mix.env() in a test script" do
      """
      defmodule MyApp.WorkerTest do
        test "it works" do
          assert Mix.env() === :test
        end
      end
      """
      |> to_source_file("apps/my_app/test/my_app/worker_test.exs")
      |> run_check(NoMixEnvAtRuntime)
      |> refute_issues()
    end
  end

  describe "&run/2 exempts Mix tasks" do
    test "does not report Mix.env() inside a use Mix.Task module" do
      """
      defmodule Mix.Tasks.MyApp.Build do
        use Mix.Task

        def run(_argv), do: build_for(Mix.env())
      end
      """
      |> to_source_file("lib/my_app/build_task.ex")
      |> run_check(NoMixEnvAtRuntime)
      |> refute_issues()
    end

    test "does not report Mix.env() in a file under mix/tasks/" do
      """
      defmodule Mix.Tasks.MyApp.Helper do
        def env, do: Mix.env()
      end
      """
      |> to_source_file("lib/mix/tasks/my_app.helper.ex")
      |> run_check(NoMixEnvAtRuntime)
      |> refute_issues()
    end
  end

  describe "&run/2 honours the :excluded_paths param" do
    test "treats a custom path as excluded" do
      """
      defmodule MyApp.Script do
        def env, do: Mix.env()
      end
      """
      |> to_source_file("lib/my_app/scripts/env.ex")
      |> run_check(NoMixEnvAtRuntime, excluded_paths: ["scripts/"])
      |> refute_issues()
    end

    test "flags mix/tasks once it is no longer excluded" do
      """
      defmodule MyApp.TaskHelper do
        def env, do: Mix.env()
      end
      """
      |> to_source_file("lib/mix/tasks/helper.ex")
      |> run_check(NoMixEnvAtRuntime, excluded_paths: [])
      |> assert_issue()
    end
  end

  describe "&run/2 ignores calls that are not Mix env access" do
    test "does not report other Mix functions" do
      """
      defmodule MyApp.Worker do
        def shell, do: Mix.shell()
        def config, do: Mix.Project.config()
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoMixEnvAtRuntime)
      |> refute_issues()
    end

    test "does not report env functions called on another module" do
      """
      defmodule MyApp.Worker do
        def env, do: MyApp.Mix.env()
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoMixEnvAtRuntime)
      |> refute_issues()
    end
  end

  describe "&run/2 honours the :functions param" do
    test "flags only the configured functions" do
      """
      defmodule MyApp.Worker do
        def env, do: Mix.env()
        def target, do: Mix.target()
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoMixEnvAtRuntime, functions: [:env])
      |> assert_issue(fn issue -> assert issue.message =~ "Mix.env/0" end)
    end
  end
end
