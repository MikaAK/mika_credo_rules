defmodule MikaCredoRules.SingleModulePerFileTest do
  use Credo.Test.Case

  alias MikaCredoRules.SingleModulePerFile

  @lib_file "apps/my_app/lib/my_app/worker.ex"
  @test_file "apps/my_app/test/my_app/worker_test.exs"

  describe "&run/2 fires on the moduledoc BAD examples" do
    test "reports the sibling-modules BAD example" do
      """
      defmodule MyApp.Worker do
        def run, do: :ok
      end

      defmodule MyApp.WorkerSupervisor do
        def start_link, do: :ok
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(SingleModulePerFile)
      |> assert_issue(fn issue ->
        assert issue.line_no === 5
        assert issue.trigger === "defmodule"

        assert issue.message ===
                 "multiple modules in one file found — move MyApp.WorkerSupervisor to its own file"
      end)
    end

    test "reports the nested-module BAD example" do
      """
      defmodule MyApp.Worker do
        defmodule State do
          defstruct [:status]
        end

        def run, do: :ok
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(SingleModulePerFile)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.message === "multiple modules in one file found — move State to its own file"
      end)
    end

    test "does not report the GOOD single-module example" do
      """
      defmodule MyApp.Worker do
        def run, do: :ok
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(SingleModulePerFile)
      |> refute_issues()
    end
  end

  describe "&run/2 flags every module after the first" do
    test "reports two issues for three sibling modules" do
      """
      defmodule MyApp.One do
      end

      defmodule MyApp.Two do
      end

      defmodule MyApp.Three do
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(SingleModulePerFile)
      |> assert_issues(fn issues ->
        assert issues |> Enum.map(& &1.line_no) |> Enum.sort() === [4, 7]

        assert issues |> Enum.map(& &1.message) |> Enum.sort() === [
                 "multiple modules in one file found — move MyApp.Three to its own file",
                 "multiple modules in one file found — move MyApp.Two to its own file"
               ]
      end)
    end

    test "renders a __MODULE__-based name argument" do
      """
      defmodule MyApp.Worker do
        defmodule __MODULE__.State do
          defstruct [:status]
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(SingleModulePerFile)
      |> assert_issue(fn issue ->
        assert issue.message =~ "move __MODULE__.State to its own file"
      end)
    end
  end

  describe "&run/2 allows single-module files and non-defmodule definitions" do
    test "does not report a defimpl alongside a module" do
      """
      defmodule MyApp.Money do
        defstruct [:amount]
      end

      defimpl String.Chars, for: MyApp.Money do
        def to_string(money), do: Integer.to_string(money.amount)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(SingleModulePerFile)
      |> refute_issues()
    end

    test "does not report a defmodule inside a quote block" do
      """
      defmodule MyApp.MacroHelpers do
        defmacro define_worker(name) do
          quote do
            defmodule unquote(name) do
              def run, do: :ok
            end
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(SingleModulePerFile)
      |> refute_issues()
    end
  end

  describe "&run/2 excludes test files by default" do
    test "does not report multiple modules in a _test.exs file" do
      """
      defmodule MyApp.WorkerTest do
        defmodule FakeAdapter do
          def fetch, do: :ok
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(SingleModulePerFile)
      |> refute_issues()
    end

    test "does not report multiple modules in a test support file" do
      """
      defmodule MyApp.Factory do
        defmodule Defaults do
          def build, do: :ok
        end
      end
      """
      |> to_source_file("test/support/factory.ex")
      |> run_check(SingleModulePerFile)
      |> refute_issues()
    end
  end

  describe "&run/2 honours the :excluded_paths param" do
    test "excludes files under a custom path fragment" do
      """
      defmodule MyApp.FixtureOne do
      end

      defmodule MyApp.FixtureTwo do
      end
      """
      |> to_source_file("apps/my_app/lib/fixtures/multi.ex")
      |> run_check(SingleModulePerFile, excluded_paths: ["fixtures/"])
      |> refute_issues()
    end

    test "still checks a boundary-lookalike path" do
      """
      defmodule MyApp.LatestOne do
      end

      defmodule MyApp.LatestTwo do
      end
      """
      |> to_source_file("lib/latest/foo.ex")
      |> run_check(SingleModulePerFile)
      |> assert_issue(fn issue ->
        assert issue.line_no === 4
        assert issue.message =~ "move MyApp.LatestTwo to its own file"
      end)
    end

    test "reports test files again once the exclusions are overridden" do
      """
      defmodule MyApp.WorkerTest do
        defmodule FakeAdapter do
          def fetch, do: :ok
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(SingleModulePerFile, excluded_paths: [])
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.message =~ "move FakeAdapter to its own file"
      end)
    end
  end
end
