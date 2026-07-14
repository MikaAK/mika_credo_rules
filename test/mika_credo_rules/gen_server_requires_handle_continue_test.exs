defmodule MikaCredoRules.GenServerRequiresHandleContinueTest do
  use Credo.Test.Case

  alias MikaCredoRules.GenServerRequiresHandleContinue

  describe "&run/2 flags init/1 that does work without {:continue, _}" do
    test "reports init/1 that queries the repo and returns {:ok, state}" do
      """
      defmodule MyApp.Server do
        use GenServer

        def init(opts) do
          rows = MyApp.Repo.all(MyApp.Row)
          {:ok, %{rows: rows, opts: opts}}
        end
      end
      """
      |> to_source_file()
      |> run_check(GenServerRequiresHandleContinue)
      |> assert_issue(fn issue ->
        assert issue.line_no === 5
        assert issue.trigger === "MyApp.Repo.all"
        assert issue.message =~ "handle_continue/2"
      end)
    end

    test "reports only the violating clause when init/1 has several clauses" do
      """
      defmodule MyApp.Server do
        use GenServer

        def init(:empty), do: {:ok, %{}}

        def init(opts) do
          rows = MyApp.Repo.all(MyApp.Row)
          {:ok, %{rows: rows, opts: opts}}
        end
      end
      """
      |> to_source_file()
      |> run_check(GenServerRequiresHandleContinue)
      |> assert_issue(fn issue -> assert issue.line_no === 7 end)
    end

    test "reports one issue per violating clause, anchored at the first call" do
      """
      defmodule MyApp.Server do
        use GenServer

        def init(opts) do
          rows = MyApp.Repo.all(MyApp.Row)
          count = MyApp.Repo.aggregate(MyApp.Row, :count)
          {:ok, %{rows: rows, count: count, opts: opts}}
        end
      end
      """
      |> to_source_file()
      |> run_check(GenServerRequiresHandleContinue)
      |> assert_issue(fn issue -> assert issue.line_no === 5 end)
    end

    test "reports erlang remote calls" do
      """
      defmodule MyApp.Server do
        use GenServer

        def init(opts) do
          {:ok, response} = :httpc.request(opts[:url])
          {:ok, %{response: response}}
        end
      end
      """
      |> to_source_file()
      |> run_check(GenServerRequiresHandleContinue)
      |> assert_issue(fn issue -> assert issue.message =~ ":httpc.request" end)
    end

    test "still reports Process.sleep/1 even though some Process functions are allowed" do
      """
      defmodule MyApp.Server do
        use GenServer

        def init(opts) do
          Process.sleep(1_000)
          {:ok, %{opts: opts}}
        end
      end
      """
      |> to_source_file()
      |> run_check(GenServerRequiresHandleContinue)
      |> assert_issue(fn issue -> assert issue.trigger === "Process.sleep" end)
    end
  end

  describe "&run/2 allows cheap non-blocking init idioms by default" do
    test "does not report Process.flag(:trap_exit, true)" do
      """
      defmodule MyApp.Server do
        use GenServer

        def init(opts) do
          Process.flag(:trap_exit, true)
          {:ok, %{opts: opts}}
        end
      end
      """
      |> to_source_file()
      |> run_check(GenServerRequiresHandleContinue)
      |> refute_issues()
    end

    test "does not report Logger calls" do
      """
      defmodule MyApp.Server do
        use GenServer

        require Logger

        def init(opts) do
          Logger.info("starting, opts: " <> inspect(opts))
          {:ok, %{opts: opts}}
        end
      end
      """
      |> to_source_file()
      |> run_check(GenServerRequiresHandleContinue)
      |> refute_issues()
    end

    test "does not report :ets.new/2" do
      """
      defmodule MyApp.Server do
        use GenServer

        def init(opts) do
          table = :ets.new(:my_table, [:set, :named_table])
          {:ok, %{opts: opts, table: table}}
        end
      end
      """
      |> to_source_file()
      |> run_check(GenServerRequiresHandleContinue)
      |> refute_issues()
    end

    test "still reports :ets.lookup/2 (only :ets.new/2 is allowed)" do
      """
      defmodule MyApp.Server do
        use GenServer

        def init(opts) do
          rows = :ets.lookup(:other_table, opts.key)
          {:ok, %{rows: rows}}
        end
      end
      """
      |> to_source_file()
      |> run_check(GenServerRequiresHandleContinue)
      |> assert_issue(fn issue -> assert issue.message =~ ":ets.lookup" end)
    end
  end

  describe "&run/2 does not let a {:continue, _} excuse work left in init/1" do
    test "reports the blocking call even when init/1 also returns {:continue, term}" do
      """
      defmodule MyApp.Server do
        use GenServer

        def init(opts) do
          rows = MyApp.Repo.all(MyApp.Row)
          {:ok, %{rows: rows, opts: opts}, {:continue, :load}}
        end
      end
      """
      |> to_source_file()
      |> run_check(GenServerRequiresHandleContinue)
      |> assert_issue(&assert(&1.trigger === "MyApp.Repo.all"))
    end

    test "reports a blocking call in the branch a {:continue, _} elsewhere does not defer" do
      """
      defmodule MyApp.Server do
        use GenServer

        def init(opts) do
          if opts[:eager] do
            {:ok, %{rows: MyApp.Repo.all(MyApp.Row)}}
          else
            {:ok, %{rows: []}, {:continue, :load}}
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(GenServerRequiresHandleContinue)
      |> assert_issue(&assert(&1.trigger === "MyApp.Repo.all"))
    end

    test "does not report init/1 that only builds state and returns a continue" do
      """
      defmodule MyApp.Server do
        use GenServer

        def init(opts) do
          {:ok, %{rows: [], opts: opts}, {:continue, :load}}
        end
      end
      """
      |> to_source_file()
      |> run_check(GenServerRequiresHandleContinue)
      |> refute_issues()
    end
  end

  describe "&run/2 allows registration for asynchronous delivery in init/1" do
    test "does not report pubsub subscribe, registry register or telemetry attach" do
      """
      defmodule MyApp.Server do
        use GenServer

        def init(opts) do
          Phoenix.PubSub.subscribe(MyApp.PubSub, "topic")
          Registry.register(MyApp.Registry, :key, nil)
          :telemetry.attach_many("id", [[:a, :b]], &__MODULE__.handle/4, self())
          {:ok, opts, {:continue, :schedule_tick}}
        end
      end
      """
      |> to_source_file()
      |> run_check(GenServerRequiresHandleContinue)
      |> refute_issues()
    end

    test "allows a one-off telemetry emit but still reports a span that wraps a function" do
      """
      defmodule MyApp.Server do
        use GenServer

        def init(host) do
          :telemetry.execute([:my_app, :cold_start], %{}, %{host: host})
          :telemetry.span([:my_app, :load], %{}, fn -> {slow_fetch(), %{}} end)
          {:ok, host}
        end
      end
      """
      |> to_source_file()
      |> run_check(GenServerRequiresHandleContinue)
      |> assert_issue(&assert(&1.trigger === ":telemetry.span"))
    end

    test "allows Application.get_env/2 but still reports Application.ensure_all_started/1" do
      """
      defmodule MyApp.Server do
        use GenServer

        def init(_opts) do
          config = Application.get_env(:my_app, :key)
          Application.ensure_all_started(:inets)
          {:ok, config}
        end
      end
      """
      |> to_source_file()
      |> run_check(GenServerRequiresHandleContinue)
      |> assert_issue(&assert(&1.trigger === "Application.ensure_all_started"))
    end
  end

  describe "&run/2 passes init/1 that only builds state" do
    test "does not report state built with Keyword, Map, Access and structs" do
      """
      defmodule MyApp.Server do
        use GenServer

        defstruct [:name, :timeout, rows: []]

        def init(opts) do
          config = opts |> Keyword.take([:name, :timeout]) |> Map.new()
          {:ok, %__MODULE__{name: config[:name], timeout: config[:timeout] || 5_000}}
        end
      end
      """
      |> to_source_file()
      |> run_check(GenServerRequiresHandleContinue)
      |> refute_issues()
    end

    test "does not report local function calls" do
      """
      defmodule MyApp.Server do
        use GenServer

        def init(opts) do
          {:ok, build_state(opts)}
        end

        defp build_state(opts), do: Map.new(opts)
      end
      """
      |> to_source_file()
      |> run_check(GenServerRequiresHandleContinue)
      |> refute_issues()
    end
  end

  describe "&run/2 skips modules that do not use GenServer" do
    test "does not report a plain init/1 function" do
      """
      defmodule MyApp.Loader do
        def init(opts) do
          rows = MyApp.Repo.all(MyApp.Row)
          {:ok, %{rows: rows, opts: opts}}
        end
      end
      """
      |> to_source_file()
      |> run_check(GenServerRequiresHandleContinue)
      |> refute_issues()
    end
  end

  describe "&run/2 honours the :allowed_modules param" do
    test "does not report calls to modules added to the list" do
      """
      defmodule MyApp.Server do
        use GenServer

        def init(opts) do
          rows = MyApp.Repo.all(MyApp.Row)
          {:ok, %{rows: rows, opts: opts}}
        end
      end
      """
      |> to_source_file()
      |> run_check(GenServerRequiresHandleContinue, allowed_modules: [MyApp.Repo])
      |> refute_issues()
    end

    test "extra_allowed_modules extends the defaults instead of replacing them" do
      """
      defmodule MyApp.Server do
        use GenServer

        def init(_opts) do
          MyApp.Cache.warm()
          {:ok, Map.new()}
        end
      end
      """
      |> to_source_file()
      |> run_check(GenServerRequiresHandleContinue, extra_allowed_modules: [MyApp.Cache])
      |> refute_issues()
    end

    test "replaces the default list instead of extending it" do
      """
      defmodule MyApp.Server do
        use GenServer

        def init(opts) do
          {:ok, Map.new(opts)}
        end
      end
      """
      |> to_source_file()
      |> run_check(GenServerRequiresHandleContinue, allowed_modules: [MyApp.Repo])
      |> assert_issue(fn issue -> assert issue.trigger === "Map.new" end)
    end

    test "accepts erlang modules given as plain atoms" do
      """
      defmodule MyApp.Server do
        use GenServer

        def init(opts) do
          table = :ets.new(:my_table, [:set])
          {:ok, %{table: table, opts: opts}}
        end
      end
      """
      |> to_source_file()
      |> run_check(GenServerRequiresHandleContinue, allowed_modules: [:ets])
      |> refute_issues()
    end

    test "grants only the named function with a {module, function} tuple" do
      """
      defmodule MyApp.Server do
        use GenServer

        def init(opts) do
          rows = MyApp.Repo.all(MyApp.Row)
          row = MyApp.Repo.one(MyApp.Row)
          {:ok, %{rows: rows, row: row, opts: opts}}
        end
      end
      """
      |> to_source_file()
      |> run_check(GenServerRequiresHandleContinue, allowed_modules: [{MyApp.Repo, :all}])
      |> assert_issue(fn issue -> assert issue.trigger === "MyApp.Repo.one" end)
    end
  end
end
