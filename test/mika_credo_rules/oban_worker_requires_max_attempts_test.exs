defmodule MikaCredoRules.ObanWorkerRequiresMaxAttemptsTest do
  use Credo.Test.Case

  alias MikaCredoRules.ObanWorkerRequiresMaxAttempts

  @worker_file "apps/my_app/lib/my_app/workers/sync_order.ex"

  describe "&run/2 flags use Oban.Worker missing :max_attempts" do
    test "reports opts that omit max_attempts" do
      """
      defmodule MyApp.Workers.SyncOrder do
        use Oban.Worker, queue: :orders
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(ObanWorkerRequiresMaxAttempts)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.message =~ "max_attempts"
      end)
    end

    test "reports use Oban.Worker with no opts at all" do
      """
      defmodule MyApp.Workers.SyncOrder do
        use Oban.Worker
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(ObanWorkerRequiresMaxAttempts)
      |> assert_issue()
    end
  end

  describe "&run/2 allows use Oban.Worker with :max_attempts set" do
    test "does not report when max_attempts is present" do
      """
      defmodule MyApp.Workers.SyncOrder do
        use Oban.Worker, queue: :orders, max_attempts: 3
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(ObanWorkerRequiresMaxAttempts)
      |> refute_issues()
    end

    test "does not require :unique" do
      """
      defmodule MyApp.Workers.SyncOrder do
        use Oban.Worker, queue: :orders, max_attempts: 3
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(ObanWorkerRequiresMaxAttempts)
      |> refute_issues()
    end

    test "does not report a non-literal option list" do
      """
      defmodule MyApp.Workers.SyncOrder do
        use Oban.Worker, @worker_opts
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(ObanWorkerRequiresMaxAttempts)
      |> refute_issues()
    end

    test "does not report use of an unrelated module also named Worker" do
      """
      defmodule MyApp.Workers.SyncOrder do
        use Worker, queue: :orders
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(ObanWorkerRequiresMaxAttempts)
      |> refute_issues()
    end
  end

  describe "&run/2 resolves aliases of Oban.Worker" do
    test "reports through an alias" do
      """
      defmodule MyApp.Workers.SyncOrder do
        alias Oban.Worker

        use Worker, queue: :orders
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(ObanWorkerRequiresMaxAttempts)
      |> assert_issue()
    end

    test "reports the fully qualified Elixir.Oban.Worker" do
      """
      defmodule MyApp.Workers.SyncOrder do
        use Elixir.Oban.Worker, queue: :orders
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(ObanWorkerRequiresMaxAttempts)
      |> assert_issue()
    end
  end

  describe "&run/2 honours the :excluded_paths param" do
    test "does not report a fixture worker under test/" do
      """
      defmodule MyApp.WorkerFixture do
        use Oban.Worker, queue: :fixtures
      end
      """
      |> to_source_file("apps/my_app/test/support/worker_fixture.ex")
      |> run_check(ObanWorkerRequiresMaxAttempts)
      |> refute_issues()
    end

    test "still reports a lookalike lib path that merely contains the test/ substring" do
      """
      defmodule MyApp.Latest.SyncOrder do
        use Oban.Worker, queue: :orders
      end
      """
      |> to_source_file("apps/my_app/lib/latest/sync_order.ex")
      |> run_check(ObanWorkerRequiresMaxAttempts)
      |> assert_issue()
    end
  end

  describe "&run/2 honours the :required_keys param" do
    test "flags a custom required key that is missing" do
      """
      defmodule MyApp.Workers.SyncOrder do
        use Oban.Worker, max_attempts: 3
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(ObanWorkerRequiresMaxAttempts, required_keys: [:queue])
      |> assert_issue(fn issue -> assert issue.message =~ "queue" end)
    end

    test "passes when every custom required key is present" do
      """
      defmodule MyApp.Workers.SyncOrder do
        use Oban.Worker, queue: :orders, max_attempts: 3
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(ObanWorkerRequiresMaxAttempts, required_keys: [:queue, :max_attempts])
      |> refute_issues()
    end
  end

  describe "moduledoc examples" do
    test "the BAD example (opts without max_attempts) fires" do
      """
      defmodule MyApp.Workers.SyncOrder do
        use Oban.Worker, queue: :orders
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(ObanWorkerRequiresMaxAttempts)
      |> assert_issue()
    end

    test "the BAD example (no opts) fires" do
      """
      defmodule MyApp.Workers.SyncOrder do
        use Oban.Worker
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(ObanWorkerRequiresMaxAttempts)
      |> assert_issue()
    end

    test "the GOOD example is clean" do
      """
      defmodule MyApp.Workers.SyncOrder do
        use Oban.Worker, queue: :orders, max_attempts: 3
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(ObanWorkerRequiresMaxAttempts)
      |> refute_issues()
    end
  end
end
