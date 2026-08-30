defmodule MikaCredoRules.NoTaskAsyncInGenServerTest do
  use Credo.Test.Case

  alias MikaCredoRules.NoTaskAsyncInGenServer

  describe "&run/2 flags Task.async in a GenServer callback body" do
    test "reports Task.async/1 inside handle_continue/2" do
      """
      defmodule MyApp.Server do
        use GenServer

        def handle_continue(:init_work, state) do
          task = Task.async(fn -> expensive_fetch(state.config) end)
          {:noreply, %{state | task_ref: task.ref}}
        end
      end
      """
      |> to_source_file()
      |> run_check(NoTaskAsyncInGenServer)
      |> assert_issue(fn issue ->
        assert issue.line_no === 5
        assert issue.trigger === "Task.async"
        assert issue.message =~ "Task.Supervisor.async_nolink/2"
      end)
    end

    test "reports Task.async/3 (module, function, args form) inside handle_info/2" do
      """
      defmodule MyApp.Server do
        use GenServer

        def handle_info(:tick, state) do
          Task.async(MyApp.Worker, :run, [state])
          {:noreply, state}
        end
      end
      """
      |> to_source_file()
      |> run_check(NoTaskAsyncInGenServer)
      |> assert_issue(fn issue -> assert issue.trigger === "Task.async" end)
    end

    test "reports Task.Supervisor.async/2 inside init/1" do
      """
      defmodule MyApp.Server do
        use GenServer

        def init(opts) do
          Task.Supervisor.async(MyApp.TaskSupervisor, fn -> warm(opts) end)
          {:ok, opts}
        end
      end
      """
      |> to_source_file()
      |> run_check(NoTaskAsyncInGenServer)
      |> assert_issue(fn issue -> assert issue.trigger === "Task.Supervisor.async" end)
    end

    test "reports every Task.async call in a callback, not just the first" do
      """
      defmodule MyApp.Server do
        use GenServer

        def handle_continue(:init_work, state) do
          a = Task.async(fn -> fetch_a() end)
          b = Task.async(fn -> fetch_b() end)
          {:noreply, %{state | refs: [a.ref, b.ref]}}
        end
      end
      """
      |> to_source_file()
      |> run_check(NoTaskAsyncInGenServer)
      |> assert_issues(fn issues -> assert length(issues) === 2 end)
    end

    test "does not flag Task.async_stream — exact function name only, never a prefix" do
      """
      defmodule MyApp.Server do
        use GenServer

        def handle_continue(:init_work, state) do
          Task.async_stream(state.items, &process/1, timeout: 5_000)
          {:noreply, state}
        end
      end
      """
      |> to_source_file()
      |> run_check(NoTaskAsyncInGenServer)
      |> refute_issues()
    end
  end

  describe "&run/2 only inspects callback bodies, not client-side functions" do
    test "does not report Task.async in a public function outside any callback" do
      """
      defmodule MyApp.Server do
        use GenServer

        def fetch_all(ids) do
          Task.async(fn -> Enum.map(ids, &fetch_one/1) end)
        end

        def init(opts), do: {:ok, opts}
      end
      """
      |> to_source_file()
      |> run_check(NoTaskAsyncInGenServer)
      |> refute_issues()
    end
  end

  describe "&run/2 only fires in GenServer/GenStage modules" do
    test "does not report Task.async in a plain module" do
      """
      defmodule MyApp.Loader do
        def handle_info(:tick, state) do
          Task.async(fn -> reload() end)
          state
        end
      end
      """
      |> to_source_file()
      |> run_check(NoTaskAsyncInGenServer)
      |> refute_issues()
    end

    test "reports Task.async inside a use GenStage module's handle_events/3" do
      """
      defmodule MyApp.Consumer do
        use GenStage

        def handle_events(events, _from, state) do
          Task.async(fn -> Enum.each(events, &process/1) end)
          {:noreply, [], state}
        end
      end
      """
      |> to_source_file()
      |> run_check(NoTaskAsyncInGenServer)
      |> assert_issue(fn issue -> assert issue.trigger === "Task.async" end)
    end
  end

  describe "&run/2 is alias-aware for Task.Supervisor" do
    test "fires when Task.Supervisor is aliased down to Supervisor" do
      """
      defmodule MyApp.Server do
        use GenServer
        alias Task.Supervisor

        def handle_continue(:init_work, state) do
          Supervisor.async(MyApp.TaskSupervisor, fn -> warm(state) end)
          {:noreply, state}
        end
      end
      """
      |> to_source_file()
      |> run_check(NoTaskAsyncInGenServer)
      |> assert_issue(fn issue -> assert issue.trigger === "Supervisor.async" end)
    end

    test "does not fire when Supervisor is aliased away from Task.Supervisor (shadowing)" do
      """
      defmodule MyApp.Server do
        use GenServer
        alias MyApp.Supervisor

        def handle_continue(:init_work, state) do
          Supervisor.async(state)
          {:noreply, state}
        end
      end
      """
      |> to_source_file()
      |> run_check(NoTaskAsyncInGenServer)
      |> refute_issues()
    end
  end

  describe "moduledoc examples" do
    test "moduledoc BAD example fires" do
      """
      defmodule MyApp.Server do
        use GenServer

        def handle_continue(:init_work, state) do
          task = Task.async(fn -> expensive_fetch(state.config) end)
          {:noreply, %{state | task_ref: task.ref}}
        end
      end
      """
      |> to_source_file()
      |> run_check(NoTaskAsyncInGenServer)
      |> assert_issue()
    end

    test "moduledoc GOOD example is clean" do
      """
      defmodule MyApp.Server do
        use GenServer

        def handle_continue(:init_work, state) do
          task = Task.Supervisor.async_nolink(MyApp.TaskSupervisor, fn -> expensive_fetch(state.config) end)
          {:noreply, %{state | task_ref: task.ref}}
        end

        def handle_info({ref, result}, %{task_ref: ref} = state) do
          Process.demonitor(ref, [:flush])
          {:noreply, %{state | task_ref: nil, data: result}}
        end

        def handle_info({:DOWN, ref, :process, _pid, reason}, %{task_ref: ref} = state) do
          Logger.error("\#{__MODULE__}: task crashed, reason: \#{inspect(reason)}")
          {:noreply, %{state | task_ref: nil}}
        end
      end
      """
      |> to_source_file()
      |> run_check(NoTaskAsyncInGenServer)
      |> refute_issues()
    end
  end

  describe "&run/2 honours params" do
    test "additional callbacks may be named via :callbacks" do
      """
      defmodule MyApp.Server do
        use GenServer

        def custom_callback(state) do
          Task.async(fn -> reload(state) end)
        end
      end
      """
      |> to_source_file()
      |> run_check(NoTaskAsyncInGenServer, callbacks: [:custom_callback])
      |> assert_issue(fn issue -> assert issue.trigger === "Task.async" end)
    end

    test "additional behaviour modules may be named via :behaviour_modules" do
      """
      defmodule MyApp.Registry do
        use Registry, keys: :unique

        def handle_continue(:init_work, state) do
          Task.async(fn -> warm(state) end)
          {:noreply, state}
        end
      end
      """
      |> to_source_file()
      |> run_check(NoTaskAsyncInGenServer, behaviour_modules: [Registry])
      |> assert_issue(fn issue -> assert issue.trigger === "Task.async" end)
    end

    test ":banned replaces the default ban list instead of extending it" do
      """
      defmodule MyApp.Server do
        use GenServer

        def handle_continue(:init_work, state) do
          Task.async(fn -> warm(state) end)
          {:noreply, state}
        end
      end
      """
      |> to_source_file()
      |> run_check(NoTaskAsyncInGenServer, banned: [{Task, :start}])
      |> refute_issues()
    end
  end
end
