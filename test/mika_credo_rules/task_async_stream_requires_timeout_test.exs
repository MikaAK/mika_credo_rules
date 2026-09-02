defmodule MikaCredoRules.TaskAsyncStreamRequiresTimeoutTest do
  use Credo.Test.Case, async: true

  alias MikaCredoRules.TaskAsyncStreamRequiresTimeout

  describe "&run/2 flags a call with no options argument at all" do
    test "reports Task.async_stream/2" do
      """
      defmodule MyApp.Batch do
        def process(items), do: Task.async_stream(items, &process_one/1)
      end
      """
      |> to_source_file()
      |> run_check(TaskAsyncStreamRequiresTimeout)
      |> assert_issue(fn issue ->
        assert issue.trigger === "Task.async_stream"
        assert issue.message =~ "timeout"
      end)
    end

    test "reports the module/function/args form with no options" do
      """
      defmodule MyApp.Batch do
        def process(items) do
          Task.async_stream(items, MyApp.Worker, :process_one, [self()])
        end
      end
      """
      |> to_source_file()
      |> run_check(TaskAsyncStreamRequiresTimeout)
      |> assert_issue(fn issue -> assert issue.trigger === "Task.async_stream" end)
    end
  end

  describe "&run/2 flags a literal opts list missing :timeout" do
    test "reports Task.async_stream/3 with max_concurrency but no timeout" do
      """
      defmodule MyApp.Batch do
        def process(items) do
          Task.async_stream(items, &process_one/1, max_concurrency: 5)
        end
      end
      """
      |> to_source_file()
      |> run_check(TaskAsyncStreamRequiresTimeout)
      |> assert_issue(fn issue -> assert issue.trigger === "Task.async_stream" end)
    end

    test "reports an empty literal opts list" do
      """
      defmodule MyApp.Batch do
        def process(items), do: Task.async_stream(items, &process_one/1, [])
      end
      """
      |> to_source_file()
      |> run_check(TaskAsyncStreamRequiresTimeout)
      |> assert_issue()
    end

    test "reports Task.Supervisor.async_stream missing timeout" do
      """
      defmodule MyApp.Batch do
        def process(sup, items) do
          Task.Supervisor.async_stream(sup, items, &process_one/1, max_concurrency: 5)
        end
      end
      """
      |> to_source_file()
      |> run_check(TaskAsyncStreamRequiresTimeout)
      |> assert_issue(fn issue -> assert issue.trigger === "Task.Supervisor.async_stream" end)
    end

    test "reports Task.Supervisor.async_stream_nolink missing timeout" do
      """
      defmodule MyApp.Batch do
        def process(sup, items) do
          Task.Supervisor.async_stream_nolink(sup, items, &process_one/1, max_concurrency: 3)
        end
      end
      """
      |> to_source_file()
      |> run_check(TaskAsyncStreamRequiresTimeout)
      |> assert_issue(fn issue ->
        assert issue.trigger === "Task.Supervisor.async_stream_nolink"
      end)
    end
  end

  describe "&run/2 passes calls with an explicit literal :timeout" do
    test "does not report timeout: 35_000 alongside other options" do
      """
      defmodule MyApp.Batch do
        def process(items) do
          Task.async_stream(items, &process_one/1, max_concurrency: 5, timeout: 35_000)
        end
      end
      """
      |> to_source_file()
      |> run_check(TaskAsyncStreamRequiresTimeout)
      |> refute_issues()
    end

    test "does not report timeout: :infinity" do
      """
      defmodule MyApp.Batch do
        def process(items), do: Task.async_stream(items, &process_one/1, timeout: :infinity)
      end
      """
      |> to_source_file()
      |> run_check(TaskAsyncStreamRequiresTimeout)
      |> refute_issues()
    end

    test "does not report the module/function/args form with an explicit timeout" do
      """
      defmodule MyApp.Batch do
        def process(items) do
          Task.async_stream(items, MyApp.Worker, :process_one, [self()], timeout: 35_000)
        end
      end
      """
      |> to_source_file()
      |> run_check(TaskAsyncStreamRequiresTimeout)
      |> refute_issues()
    end
  end

  describe "&run/2 skips opts passed as a variable (accepted false negative)" do
    test "does not report when the trailing argument is a variable" do
      """
      defmodule MyApp.Batch do
        def process(items, opts), do: Task.async_stream(items, &process_one/1, opts)
      end
      """
      |> to_source_file()
      |> run_check(TaskAsyncStreamRequiresTimeout)
      |> refute_issues()
    end

    test "does not report when the trailing argument is a module attribute" do
      """
      defmodule MyApp.Batch do
        @opts [timeout: 30_000]

        def process(items), do: Task.async_stream(items, &process_one/1, @opts)
      end
      """
      |> to_source_file()
      |> run_check(TaskAsyncStreamRequiresTimeout)
      |> refute_issues()
    end

    test "does not report when the trailing argument is a Keyword.merge call" do
      """
      defmodule MyApp.Batch do
        def process(items, extra) do
          Task.async_stream(items, &process_one/1, Keyword.merge([timeout: 1], extra))
        end
      end
      """
      |> to_source_file()
      |> run_check(TaskAsyncStreamRequiresTimeout)
      |> refute_issues()
    end

    test "does not report when the trailing argument is a list concatenation expression" do
      """
      defmodule MyApp.Batch do
        def process(items, extra) do
          Task.async_stream(items, &process_one/1, [max_concurrency: 4] ++ extra)
        end
      end
      """
      |> to_source_file()
      |> run_check(TaskAsyncStreamRequiresTimeout)
      |> refute_issues()
    end
  end

  describe "&run/2 does not flag unrelated functions" do
    test "does not report Task.async" do
      """
      defmodule MyApp.Batch do
        def process(item), do: Task.async(fn -> process_one(item) end)
      end
      """
      |> to_source_file()
      |> run_check(TaskAsyncStreamRequiresTimeout)
      |> refute_issues()
    end
  end

  describe "&run/2 is alias-aware for Task.Supervisor" do
    test "fires when Task.Supervisor is aliased down to Supervisor" do
      """
      defmodule MyApp.Batch do
        alias Task.Supervisor

        def process(sup, items) do
          Supervisor.async_stream(sup, items, &process_one/1, max_concurrency: 5)
        end
      end
      """
      |> to_source_file()
      |> run_check(TaskAsyncStreamRequiresTimeout)
      |> assert_issue(fn issue -> assert issue.trigger === "Supervisor.async_stream" end)
    end

    test "does not fire when Supervisor is aliased away from Task.Supervisor (shadowing)" do
      """
      defmodule MyApp.Batch do
        alias MyApp.Supervisor

        def process(sup, items) do
          Supervisor.async_stream(sup, items)
        end
      end
      """
      |> to_source_file()
      |> run_check(TaskAsyncStreamRequiresTimeout)
      |> refute_issues()
    end
  end

  describe "&run/2 honours :excluded_paths" do
    test "does not report inside an excluded path" do
      """
      defmodule MyApp.Batch do
        def process(items), do: Task.async_stream(items, &process_one/1)
      end
      """
      |> to_source_file("test/support/batch_fixture.ex")
      |> run_check(TaskAsyncStreamRequiresTimeout, excluded_paths: ["test/support/"])
      |> refute_issues()
    end
  end

  describe "moduledoc examples" do
    test "moduledoc BAD example 1 (no timeout among other opts) fires" do
      """
      defmodule MyApp.Batch do
        def process(symbols), do: Task.async_stream(symbols, &process_one/1, max_concurrency: 5)
      end
      """
      |> to_source_file()
      |> run_check(TaskAsyncStreamRequiresTimeout)
      |> assert_issue()
    end

    test "moduledoc BAD example 2 (no options at all) fires" do
      """
      defmodule MyApp.Batch do
        def process(symbols), do: Task.async_stream(symbols, &process_one/1)
      end
      """
      |> to_source_file()
      |> run_check(TaskAsyncStreamRequiresTimeout)
      |> assert_issue()
    end

    test "moduledoc GOOD example is clean" do
      """
      defmodule MyApp.Batch do
        def process(symbols) do
          Task.async_stream(symbols, &process_one/1, max_concurrency: 5, timeout: 35_000)
        end
      end
      """
      |> to_source_file()
      |> run_check(TaskAsyncStreamRequiresTimeout)
      |> refute_issues()
    end
  end
end
