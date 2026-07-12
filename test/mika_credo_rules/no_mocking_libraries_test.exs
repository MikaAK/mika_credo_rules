defmodule MikaCredoRules.NoMockingLibrariesTest do
  use Credo.Test.Case

  alias MikaCredoRules.NoMockingLibraries

  @test_file "apps/my_app/test/my_app/worker_test.exs"

  describe "&run/2 flags mocking library references" do
    test "reports import Mox" do
      """
      defmodule MyApp.WorkerTest do
        import Mox

        test "it works", do: :ok
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoMockingLibraries)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.message =~ "Mox found"
      end)
    end

    test "reports a Mox remote call" do
      """
      defmodule MyApp.WorkerTest do
        Mox.defmock(MyApp.ClientStub, for: MyApp.Client)
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoMockingLibraries)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.message =~ "Mox found"
      end)
    end

    test "reports use Mimic" do
      """
      defmodule MyApp.WorkerTest do
        use Mimic

        test "it works", do: :ok
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoMockingLibraries)
      |> assert_issue(fn issue -> assert issue.message =~ "Mimic found" end)
    end

    test "reports every module in the default list" do
      """
      defmodule MyApp.WorkerTest do
        import Mox
        import Hammox
        import Mock
        use Mimic
        use Patch
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoMockingLibraries)
      |> assert_issues(fn issues ->
        assert length(issues) === 5
        assert issues |> Enum.map(& &1.line_no) |> Enum.sort() === [2, 3, 4, 5, 6]
      end)
    end

    test "reports fully qualified Elixir.Mox" do
      """
      defmodule MyApp.WorkerTest do
        def stub, do: Elixir.Mox.stub(MyApp.ClientStub, :fetch, fn -> :ok end)
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoMockingLibraries)
      |> assert_issue(fn issue -> assert issue.message =~ "Elixir.Mox found" end)
    end
  end

  describe "&run/2 flags erlang mocking modules" do
    test "reports :meck.new/1" do
      """
      defmodule MyApp.WorkerTest do
        def setup_mock, do: :meck.new(:module)
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoMockingLibraries)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.message =~ ":meck.new/1 found"
      end)
    end

    test "does not report other erlang remote calls" do
      """
      defmodule MyApp.WorkerTest do
        def wait, do: :timer.sleep(10)
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoMockingLibraries)
      |> refute_issues()
    end
  end

  describe "&run/2 passes code without mocking libraries" do
    test "does not report behaviours and dependency injection" do
      """
      defmodule MyApp.WorkerTest do
        use ExUnit.Case, async: true

        defmodule TestClient do
          @behaviour MyApp.Client

          @impl MyApp.Client
          def fetch(id), do: {:ok, %{id: id}}
        end

        test "fetches through the injected client" do
          assert {:ok, %{id: 1}} = MyApp.Worker.fetch(1, client: TestClient)
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoMockingLibraries)
      |> refute_issues()
    end

    test "does not report a module that merely contains a banned name" do
      """
      defmodule MyApp.WorkerTest do
        alias MyApp.MockingBird

        def sing, do: MockingBird.sing()
        def sing_qualified, do: MyApp.MockingBird.sing()
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoMockingLibraries)
      |> refute_issues()
    end

    test "does not report a project submodule grouped in a multi-alias" do
      """
      defmodule MyApp.WorkerTest do
        alias MyApp.{Mock, Worker}

        def build, do: Worker.build(Mock)
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoMockingLibraries)
      |> refute_issues()
    end

    test "does not report bare uses of a name shadowed by a project alias" do
      """
      defmodule MyApp.WorkerTest do
        alias MyApp.Mock

        def build, do: Mock.build()
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoMockingLibraries)
      |> refute_issues()
    end
  end

  describe "&run/2 resolves aliases of banned modules" do
    test "reports uses through a renamed mocking library alias" do
      """
      defmodule MyApp.WorkerTest do
        alias Mox, as: M

        def stub, do: M.stub(MyApp.ClientStub, :fetch, fn -> :ok end)
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoMockingLibraries)
      |> assert_issues(fn issues ->
        assert issues |> Enum.map(& &1.line_no) |> Enum.sort() === [2, 4]
      end)
    end
  end

  describe "&run/2 honours the :modules param" do
    test "flags only the listed modules" do
      """
      defmodule MyApp.WorkerTest do
        import Mox
        import FakeLib
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoMockingLibraries, modules: [FakeLib])
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.message =~ "FakeLib found"
      end)
    end
  end

  describe "&run/2 honours the :erlang_modules param" do
    test "flags only the listed erlang modules" do
      """
      defmodule MyApp.WorkerTest do
        def old, do: :meck.new(:module)
        def new, do: :mocklib.stub(:module)
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoMockingLibraries, erlang_modules: [:mocklib])
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.message =~ ":mocklib.stub/1 found"
      end)
    end
  end
end
