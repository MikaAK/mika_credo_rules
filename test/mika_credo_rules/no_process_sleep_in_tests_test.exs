defmodule MikaCredoRules.NoProcessSleepInTestsTest do
  use Credo.Test.Case

  alias MikaCredoRules.NoProcessSleepInTests

  @test_file "apps/my_app/test/my_app/worker_test.exs"
  @lib_file "apps/my_app/lib/my_app/worker.ex"

  describe "&run/2 flags sleeping inside a test file" do
    test "reports Process.sleep/1" do
      """
      defmodule MyApp.WorkerTest do
        test "eventually finishes" do
          Process.sleep(100)
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoProcessSleepInTests)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.message =~ "Process.sleep/1"
      end)
    end

    test "reports :timer.sleep/1" do
      """
      defmodule MyApp.WorkerTest do
        test "eventually finishes" do
          :timer.sleep(100)
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoProcessSleepInTests)
      |> assert_issue(fn issue -> assert issue.message =~ ":timer.sleep/1" end)
    end

    test "reports fully qualified Elixir.Process.sleep/1" do
      """
      defmodule MyApp.WorkerTest do
        test "eventually finishes" do
          Elixir.Process.sleep(100)
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoProcessSleepInTests)
      |> assert_issue(fn issue -> assert issue.message =~ "Elixir.Process.sleep/1" end)
    end

    test "reports each call site with its own line number" do
      """
      defmodule MyApp.WorkerTest do
        test "waits a lot" do
          Process.sleep(10)
          :timer.sleep(20)
          Process.sleep(30)
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoProcessSleepInTests)
      |> assert_issues(fn issues ->
        assert issues |> Enum.map(& &1.line_no) |> Enum.sort() === [3, 4, 5]
      end)
    end

    test "suggests synchronizing with assert_receive instead of sleeping" do
      """
      defmodule MyApp.WorkerTest do
        test "eventually finishes" do
          Process.sleep(100)
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoProcessSleepInTests)
      |> assert_issue(fn issue -> assert issue.message =~ "assert_receive" end)
    end
  end

  describe "&run/2 ignores non-test files" do
    test "does not report Process.sleep in a lib file" do
      """
      defmodule MyApp.Worker do
        def backoff, do: Process.sleep(100)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoProcessSleepInTests)
      |> refute_issues()
    end

    test "does not report :timer.sleep in a lib file" do
      """
      defmodule MyApp.Worker do
        def backoff, do: :timer.sleep(100)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoProcessSleepInTests)
      |> refute_issues()
    end

    test "does not report a test support file that is not a test module" do
      """
      defmodule MyApp.Support.SlowStub do
        def call, do: Process.sleep(100)
      end
      """
      |> to_source_file("apps/my_app/test/support/slow_stub.ex")
      |> run_check(NoProcessSleepInTests)
      |> refute_issues()
    end
  end

  describe "&run/2 ignores functions that do not sleep" do
    test "does not report other Process functions" do
      """
      defmodule MyApp.WorkerTest do
        test "schedules a message" do
          Process.send_after(self(), :tick, 100)
          Process.flag(:trap_exit, true)
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoProcessSleepInTests)
      |> refute_issues()
    end

    test "does not report other :timer functions" do
      """
      defmodule MyApp.WorkerTest do
        test "measures a call" do
          :timer.tc(fn -> :ok end)
          :timer.send_after(100, :tick)
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoProcessSleepInTests)
      |> refute_issues()
    end

    test "does not report sleep called on another module" do
      """
      defmodule MyApp.WorkerTest do
        test "uses a fake clock" do
          MyApp.FakeClock.sleep(100)
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoProcessSleepInTests)
      |> refute_issues()
    end

    test "does not report assert_receive with a timeout" do
      """
      defmodule MyApp.WorkerTest do
        test "waits for the broadcast" do
          assert_receive {:order_updated, _order}, 500
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoProcessSleepInTests)
      |> refute_issues()
    end
  end

  describe "&run/2 honours the :test_files param" do
    test "treats a custom suffix as a test file" do
      """
      defmodule MyApp.WorkerSpec do
        test "eventually finishes" do
          Process.sleep(100)
        end
      end
      """
      |> to_source_file("apps/my_app/spec/my_app/worker_spec.exs")
      |> run_check(NoProcessSleepInTests, test_files: ["_spec.exs"])
      |> assert_issue()
    end

    test "no longer flags _test.exs files once :test_files is overridden" do
      """
      defmodule MyApp.WorkerTest do
        test "eventually finishes" do
          Process.sleep(100)
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoProcessSleepInTests, test_files: ["_spec.exs"])
      |> refute_issues()
    end
  end

  describe "&run/2 honours the :functions param" do
    test "flags only the configured sleep functions" do
      """
      defmodule MyApp.WorkerTest do
        test "eventually finishes" do
          Process.sleep(100)
          :timer.sleep(100)
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoProcessSleepInTests, functions: [{:timer, :sleep}])
      |> assert_issue(fn issue -> assert issue.message =~ ":timer.sleep/1" end)
    end
  end
end
