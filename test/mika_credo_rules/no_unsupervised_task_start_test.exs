defmodule MikaCredoRules.NoUnsupervisedTaskStartTest do
  use Credo.Test.Case, async: true

  alias MikaCredoRules.NoUnsupervisedTaskStart

  describe "&run/2 flags Task.start" do
    test "reports Task.start/1" do
      """
      defmodule MyApp.Webhooks do
        def notify(payload) do
          Task.start(fn -> send_webhook(payload) end)
        end
      end
      """
      |> to_source_file()
      |> run_check(NoUnsupervisedTaskStart)
      |> assert_issue(fn issue ->
        assert issue.trigger === "Task.start"
        assert issue.message =~ "Task.Supervisor.start_child/2"
      end)
    end

    test "reports Task.start/3 (module, function, args form)" do
      """
      defmodule MyApp.Webhooks do
        def notify(payload) do
          Task.start(MyApp.Webhooks, :send_webhook, [payload])
        end
      end
      """
      |> to_source_file()
      |> run_check(NoUnsupervisedTaskStart)
      |> assert_issue(fn issue -> assert issue.trigger === "Task.start" end)
    end

    test "does not report Task.Supervisor.start_child" do
      """
      defmodule MyApp.Webhooks do
        def notify(payload) do
          Task.Supervisor.start_child(MyApp.TaskSupervisor, fn -> send_webhook(payload) end)
        end
      end
      """
      |> to_source_file()
      |> run_check(NoUnsupervisedTaskStart)
      |> refute_issues()
    end

    test "does not report unrelated Task functions" do
      """
      defmodule MyApp.Webhooks do
        def notify(items) do
          Task.async_stream(items, &send_webhook/1, timeout: 5_000)
        end
      end
      """
      |> to_source_file()
      |> run_check(NoUnsupervisedTaskStart)
      |> refute_issues()
    end
  end

  describe "&run/2 leaves Task.start_link alone by default" do
    test "does not report Task.start_link/1" do
      """
      defmodule MyApp.Webhooks do
        def notify(payload) do
          Task.start_link(fn -> send_webhook(payload) end)
        end
      end
      """
      |> to_source_file()
      |> run_check(NoUnsupervisedTaskStart)
      |> refute_issues()
    end

    test "reports Task.start_link when :also_flag_start_link is true" do
      """
      defmodule MyApp.Webhooks do
        def notify(payload) do
          Task.start_link(fn -> send_webhook(payload) end)
        end
      end
      """
      |> to_source_file()
      |> run_check(NoUnsupervisedTaskStart, also_flag_start_link: true)
      |> assert_issue(fn issue -> assert issue.trigger === "Task.start_link" end)
    end
  end

  describe "&run/2 is alias-aware" do
    test "fires through an as: rename" do
      """
      defmodule MyApp.Webhooks do
        alias Task, as: T

        def notify(payload) do
          T.start(fn -> send_webhook(payload) end)
        end
      end
      """
      |> to_source_file()
      |> run_check(NoUnsupervisedTaskStart)
      |> assert_issue(fn issue -> assert issue.trigger === "T.start" end)
    end

    test "does not fire when a project alias shadows the bare Task name" do
      """
      defmodule MyApp.Webhooks do
        alias MyApp.Task

        def notify(payload) do
          Task.start(payload)
        end
      end
      """
      |> to_source_file()
      |> run_check(NoUnsupervisedTaskStart)
      |> refute_issues()
    end
  end

  describe "&run/2 honours :excluded_paths" do
    test "does not report in a _test.exs file by default" do
      """
      defmodule MyApp.WebhooksTest do
        use ExUnit.Case

        test "fires a task" do
          Task.start(fn -> :ok end)
        end
      end
      """
      |> to_source_file("test/my_app/webhooks_test.exs")
      |> run_check(NoUnsupervisedTaskStart)
      |> refute_issues()
    end

    test "does not report under test/ by default" do
      """
      defmodule MyApp.TestSupport do
        def fire, do: Task.start(fn -> :ok end)
      end
      """
      |> to_source_file("test/support/fixture.ex")
      |> run_check(NoUnsupervisedTaskStart)
      |> refute_issues()
    end

    test "reports in lib code outside the excluded paths" do
      """
      defmodule MyApp.Webhooks do
        def notify(payload), do: Task.start(fn -> send_webhook(payload) end)
      end
      """
      |> to_source_file("lib/my_app/webhooks.ex")
      |> run_check(NoUnsupervisedTaskStart)
      |> assert_issue()
    end
  end

  describe "moduledoc examples" do
    test "moduledoc BAD example fires" do
      """
      defmodule MyApp.Webhooks do
        def notify(payload), do: Task.start(fn -> send_webhook(payload) end)
      end
      """
      |> to_source_file()
      |> run_check(NoUnsupervisedTaskStart)
      |> assert_issue()
    end

    test "moduledoc GOOD example is clean" do
      """
      defmodule MyApp.Webhooks do
        def notify(payload) do
          Task.Supervisor.start_child(MyApp.TaskSupervisor, fn -> send_webhook(payload) end)
        end
      end
      """
      |> to_source_file()
      |> run_check(NoUnsupervisedTaskStart)
      |> refute_issues()
    end
  end
end
