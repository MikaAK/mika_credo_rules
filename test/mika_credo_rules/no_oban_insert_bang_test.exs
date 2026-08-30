defmodule MikaCredoRules.NoObanInsertBangTest do
  use Credo.Test.Case

  alias MikaCredoRules.NoObanInsertBang

  @worker_file "apps/my_app/lib/my_app/worker.ex"

  describe "&run/2 flags Oban bang inserts in lib code" do
    test "reports Oban.insert!/1" do
      """
      defmodule MyApp.Worker do
        def enqueue(id) do
          Oban.insert!(MyApp.Workers.Sync.new(%{id: id}))
        end
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoObanInsertBang)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.message =~ "Oban.insert!"
      end)
    end

    test "reports Oban.insert!/2" do
      """
      defmodule MyApp.Worker do
        def enqueue(id) do
          Oban.insert!(MyApp.Oban, MyApp.Workers.Sync.new(%{id: id}))
        end
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoObanInsertBang)
      |> assert_issue()
    end

    test "reports Oban.insert_all!/1" do
      """
      defmodule MyApp.Worker do
        def enqueue_many(ids) do
          Oban.insert_all!(Enum.map(ids, &MyApp.Workers.Sync.new(%{id: &1})))
        end
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoObanInsertBang)
      |> assert_issue(fn issue -> assert issue.message =~ "Oban.insert_all!" end)
    end

    test "points the fix at the non-bang form" do
      """
      defmodule MyApp.Worker do
        def enqueue(id) do
          Oban.insert!(MyApp.Workers.Sync.new(%{id: id}))
        end
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoObanInsertBang)
      |> assert_issue(fn issue -> assert issue.message =~ "Oban.insert/1..3" end)
    end

    test "reports each bang call on a shared line at its own column" do
      """
      defmodule MyApp.Worker do
        def enqueue(id), do: Oban.insert!(a(id)) && Oban.insert!(b(id))
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoObanInsertBang)
      |> assert_issues(fn issues ->
        assert issues |> Enum.map(& &1.column) |> Enum.uniq() |> length() === 2
      end)
    end
  end

  describe "&run/2 allows the non-bang forms" do
    test "does not report Oban.insert/1" do
      """
      defmodule MyApp.Worker do
        def enqueue(id) do
          Oban.insert(MyApp.Workers.Sync.new(%{id: id}))
        end
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoObanInsertBang)
      |> refute_issues()
    end

    test "does not report Oban.insert_all/1" do
      """
      defmodule MyApp.Worker do
        def enqueue_many(ids) do
          Oban.insert_all(Enum.map(ids, &MyApp.Workers.Sync.new(%{id: &1})))
        end
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoObanInsertBang)
      |> refute_issues()
    end

    test "does not report insert! called on an unrelated module" do
      """
      defmodule MyApp.Worker do
        def enqueue(id), do: MyApp.Jobs.insert!(id)
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoObanInsertBang)
      |> refute_issues()
    end
  end

  describe "&run/2 resolves aliases of Oban" do
    test "reports a bang insert through a renamed alias" do
      """
      defmodule MyApp.Worker do
        alias Oban, as: MyOban

        def enqueue(id), do: MyOban.insert!(MyApp.Workers.Sync.new(%{id: id}))
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoObanInsertBang)
      |> assert_issue(fn issue -> assert issue.message =~ "MyOban.insert!" end)
    end

    test "reports the fully qualified Elixir.Oban.insert!" do
      """
      defmodule MyApp.Worker do
        def enqueue(id), do: Elixir.Oban.insert!(MyApp.Workers.Sync.new(%{id: id}))
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoObanInsertBang)
      |> assert_issue()
    end

    test "does not report when Oban is shadowed by another module's alias" do
      """
      defmodule MyApp.Worker do
        alias MyApp.Oban

        def enqueue(id), do: Oban.insert!(id)
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoObanInsertBang)
      |> refute_issues()
    end
  end

  describe "&run/2 honours the :excluded_paths param" do
    test "does not report a bang insert inside a _test.exs file" do
      """
      defmodule MyApp.WorkerTest do
        test "enqueues" do
          Oban.insert!(MyApp.Workers.Sync.new(%{id: 1}))
        end
      end
      """
      |> to_source_file("apps/my_app/test/my_app/worker_test.exs")
      |> run_check(NoObanInsertBang)
      |> refute_issues()
    end

    test "does not report a bang insert under test/" do
      """
      defmodule MyApp.WorkerFixture do
        def enqueue!, do: Oban.insert!(MyApp.Workers.Sync.new(%{id: 1}))
      end
      """
      |> to_source_file("apps/my_app/test/support/worker_fixture.ex")
      |> run_check(NoObanInsertBang)
      |> refute_issues()
    end

    test "does not report a bang insert in a seeds script" do
      """
      Oban.insert!(MyApp.Workers.Sync.new(%{id: 1}))
      """
      |> to_source_file("apps/my_app/priv/repo/seeds.exs")
      |> run_check(NoObanInsertBang)
      |> refute_issues()
    end

    test "still reports a lookalike lib path that merely contains the test/ substring" do
      """
      defmodule MyApp.Latest do
        def enqueue(id), do: Oban.insert!(MyApp.Workers.Sync.new(%{id: id}))
      end
      """
      |> to_source_file("apps/my_app/lib/latest/reminders.ex")
      |> run_check(NoObanInsertBang)
      |> assert_issue()
    end

    test "honours a custom :excluded_paths list" do
      """
      defmodule MyApp.Worker do
        def enqueue(id), do: Oban.insert!(MyApp.Workers.Sync.new(%{id: id}))
      end
      """
      |> to_source_file("apps/my_app/lib/my_app/scripts/backfill.ex")
      |> run_check(NoObanInsertBang, excluded_paths: ["scripts/"])
      |> refute_issues()
    end
  end

  describe "&run/2 honours the :functions param" do
    test "flags only the configured functions" do
      """
      defmodule MyApp.Worker do
        def one, do: Oban.insert!(MyApp.Workers.Sync.new(%{id: 1}))
        def two, do: Oban.insert_all!([MyApp.Workers.Sync.new(%{id: 2})])
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoObanInsertBang, functions: [:insert!])
      |> assert_issue(fn issue -> assert issue.message =~ "Oban.insert!" end)
    end
  end

  describe "moduledoc examples" do
    test "the BAD example fires" do
      """
      defmodule MyApp.Worker do
        def enqueue(id) do
          Oban.insert!(MyApp.Workers.Sync.new(%{id: id}))
        end
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoObanInsertBang)
      |> assert_issue()
    end

    test "the GOOD example is clean" do
      """
      defmodule MyApp.Worker do
        def enqueue(id) do
          with {:ok, _job} <- Oban.insert(MyApp.Workers.Sync.new(%{id: id})) do
            :ok
          end
        end
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoObanInsertBang)
      |> refute_issues()
    end
  end
end
