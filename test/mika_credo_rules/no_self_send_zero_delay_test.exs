defmodule MikaCredoRules.NoSelfSendZeroDelayTest do
  use Credo.Test.Case

  alias MikaCredoRules.NoSelfSendZeroDelay

  describe "&run/2 flags Process.send_after(self(), _, 0) anywhere" do
    test "reports a zero-delay self send in a plain module" do
      """
      defmodule MyApp.Ticker do
        def schedule(state) do
          Process.send_after(self(), :tick, 0)
          state
        end
      end
      """
      |> to_source_file()
      |> run_check(NoSelfSendZeroDelay)
      |> assert_issue(fn issue ->
        assert issue.trigger === "Process.send_after"
        assert issue.message =~ "handle_continue/2"
      end)
    end

    test "reports it inside init/1 of a GenServer too" do
      """
      defmodule MyApp.Server do
        use GenServer

        def init(opts) do
          Process.send_after(self(), :load, 0)
          {:ok, opts}
        end
      end
      """
      |> to_source_file()
      |> run_check(NoSelfSendZeroDelay)
      |> assert_issue(fn issue -> assert issue.trigger === "Process.send_after" end)
    end

    test "does not report a nonzero delay" do
      """
      defmodule MyApp.Ticker do
        def schedule(state) do
          Process.send_after(self(), :tick, 1_000)
          state
        end
      end
      """
      |> to_source_file()
      |> run_check(NoSelfSendZeroDelay)
      |> refute_issues()
    end

    test "does not report send_after to a different destination" do
      """
      defmodule MyApp.Ticker do
        def schedule(pid, state) do
          Process.send_after(pid, :tick, 0)
          state
        end
      end
      """
      |> to_source_file()
      |> run_check(NoSelfSendZeroDelay)
      |> refute_issues()
    end

    test "does not report send_after with a variable delay" do
      """
      defmodule MyApp.Ticker do
        def schedule(state, delay) do
          Process.send_after(self(), :tick, delay)
          state
        end
      end
      """
      |> to_source_file()
      |> run_check(NoSelfSendZeroDelay)
      |> refute_issues()
    end

    test "derives the trigger from the module path instead of hardcoding it" do
      """
      defmodule MyApp.Ticker do
        def schedule(state) do
          Elixir.Process.send_after(self(), :tick, 0)
          state
        end
      end
      """
      |> to_source_file()
      |> run_check(NoSelfSendZeroDelay)
      |> assert_issue(fn issue -> assert issue.trigger === "Elixir.Process.send_after" end)
    end

    test "reports a piped self() |> Process.send_after(:tick, 0)" do
      """
      defmodule MyApp.Ticker do
        def schedule(state) do
          self() |> Process.send_after(:tick, 0)
          state
        end
      end
      """
      |> to_source_file()
      |> run_check(NoSelfSendZeroDelay)
      |> assert_issue(fn issue -> assert issue.trigger === "Process.send_after" end)
    end

    test "does not report a piped self() |> Process.send_after(:tick, 1_000) nonzero delay" do
      """
      defmodule MyApp.Ticker do
        def schedule(state) do
          self() |> Process.send_after(:tick, 1_000)
          state
        end
      end
      """
      |> to_source_file()
      |> run_check(NoSelfSendZeroDelay)
      |> refute_issues()
    end
  end

  describe "&run/2 flags send(self(), _) inside init/1 of a use GenServer module" do
    test "reports send(self(), :load) inside init/1" do
      """
      defmodule MyApp.Server do
        use GenServer

        def init(opts) do
          send(self(), :load)
          {:ok, opts}
        end
      end
      """
      |> to_source_file()
      |> run_check(NoSelfSendZeroDelay)
      |> assert_issue(fn issue ->
        assert issue.trigger === "send"
        assert issue.message =~ "handle_continue/2"
      end)
    end

    test "does not report send(self(), _) inside handle_continue/2" do
      """
      defmodule MyApp.Server do
        use GenServer

        def init(opts), do: {:ok, opts, {:continue, :load}}

        def handle_continue(:load, state) do
          send(self(), :again)
          {:noreply, state}
        end
      end
      """
      |> to_source_file()
      |> run_check(NoSelfSendZeroDelay)
      |> refute_issues()
    end

    test "does not report send(self(), _) inside init/1 of a plain module" do
      """
      defmodule MyApp.Loader do
        def init(opts) do
          send(self(), :load)
          {:ok, opts}
        end
      end
      """
      |> to_source_file()
      |> run_check(NoSelfSendZeroDelay)
      |> refute_issues()
    end

    test "does not report send/2 to a different destination inside init/1" do
      """
      defmodule MyApp.Server do
        use GenServer

        def init(opts) do
          send(opts[:pid], :load)
          {:ok, opts}
        end
      end
      """
      |> to_source_file()
      |> run_check(NoSelfSendZeroDelay)
      |> refute_issues()
    end

    test "reports send(self(), _) inside init/1 of a use GenStage module too" do
      """
      defmodule MyApp.Producer do
        use GenStage

        def init(opts) do
          send(self(), :init)
          {:producer, opts}
        end
      end
      """
      |> to_source_file()
      |> run_check(NoSelfSendZeroDelay)
      |> assert_issue(fn issue -> assert issue.trigger === "send" end)
    end

    test "does not report send(self(), _) inside an anonymous fn stored in init/1 state" do
      """
      defmodule MyApp.Server do
        use GenServer

        def init(opts) do
          {:ok, %{opts: opts, callback: fn -> send(self(), :ping) end}}
        end
      end
      """
      |> to_source_file()
      |> run_check(NoSelfSendZeroDelay)
      |> refute_issues()
    end
  end

  describe "&run/2 honours :also_flag_send_self_in_init" do
    test "does not report send(self(), _) in init/1 when disabled" do
      """
      defmodule MyApp.Server do
        use GenServer

        def init(opts) do
          send(self(), :load)
          {:ok, opts}
        end
      end
      """
      |> to_source_file()
      |> run_check(NoSelfSendZeroDelay, also_flag_send_self_in_init: false)
      |> refute_issues()
    end
  end

  describe "&run/2 honours :excluded_paths" do
    test "does not report a zero-delay send_after in an excluded path" do
      """
      defmodule MyApp.Ticker do
        def schedule(state) do
          Process.send_after(self(), :tick, 0)
          state
        end
      end
      """
      |> to_source_file("test/support/ticker_fixture.ex")
      |> run_check(NoSelfSendZeroDelay, excluded_paths: ["test/support/"])
      |> refute_issues()
    end
  end

  describe "moduledoc examples" do
    test "moduledoc BAD example 1 (send_after) fires" do
      """
      defmodule MyApp.Server do
        use GenServer

        def init(opts) do
          Process.send_after(self(), :load, 0)
          {:ok, opts}
        end

        def handle_info(:load, state), do: {:noreply, state}
      end
      """
      |> to_source_file()
      |> run_check(NoSelfSendZeroDelay)
      |> assert_issue()
    end

    test "moduledoc GOOD example 1 (continue) is clean" do
      """
      defmodule MyApp.Server do
        use GenServer

        def init(opts), do: {:ok, opts, {:continue, :load}}
        def handle_continue(:load, state), do: {:noreply, state}
      end
      """
      |> to_source_file()
      |> run_check(NoSelfSendZeroDelay)
      |> refute_issues()
    end

    test "moduledoc BAD example 2 (send in init) fires" do
      """
      defmodule MyApp.Server do
        use GenServer

        def init(opts) do
          send(self(), :load)
          {:ok, opts}
        end
      end
      """
      |> to_source_file()
      |> run_check(NoSelfSendZeroDelay)
      |> assert_issue()
    end

    test "moduledoc GOOD example 2 is clean" do
      """
      defmodule MyApp.Server do
        use GenServer

        def init(opts), do: {:ok, opts, {:continue, :load}}
      end
      """
      |> to_source_file()
      |> run_check(NoSelfSendZeroDelay)
      |> refute_issues()
    end
  end
end
